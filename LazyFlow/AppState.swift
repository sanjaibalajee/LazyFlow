import Foundation
import AppKit
import AVFoundation
import Observation

@Observable
final class AppState {

    // MARK: - Recording

    /// Single source of truth for where we are in the capture → transcribe → paste pipeline.
    /// Every transition notifies `onRecordingModeChanged` so the floating overlay stays in
    /// sync even for the transitions that happen deep inside the processing task.
    var recordingMode: RecordingMode = .idle {
        didSet {
            guard oldValue != recordingMode else { return }
            onRecordingModeChanged?(recordingMode)
        }
    }

    /// Derived rather than stored — the two used to be updated side by side and could drift.
    var isRecording: Bool { recordingMode == .recording }

    var audioLevel: Float = 0

    enum RecordingMode { case idle, recording, processing }

    // MARK: - Transcript

    var liveTranscript    = ""
    var currentTranscript = ""
    var errorMessage:     String?

    /// Set to request the correction sheet for an entry. The main window owns the sheet, so
    /// the menu bar can hand off a transcript to it — sheets cannot be presented from inside
    /// a `MenuBarExtra` popover, which dismisses itself as soon as the sheet takes focus.
    var pendingCorrection: TranscriptEntry?

    // MARK: - History (backed by TranscriptStore → GRDB)

    var history: [TranscriptEntry] { transcriptStore.entries }
    let transcriptStore  = TranscriptStore()
    let correctionStore  = CorrectionStore()

    // MARK: - Multi-provider store

    let providerStore = LLMProviderStore.shared

    // MARK: - Legacy Groq API key bridge

    var apiKey: String {
        get { providerStore.apiKey(for: LLMProvider.groq) }
        set { providerStore.setApiKey(newValue, for: LLMProvider.groq) }
    }

    /// Groq key used for cloud Whisper. Prefers the per-provider Keychain entry that Settings
    /// writes and falls back to the legacy single-key entry from onboarding/older builds.
    /// Reading only the legacy entry meant a key added in Settings → Providers never reached
    /// transcription, which failed as "no API key" while the UI showed a key was configured.
    var groqAPIKey: String {
        providerStore.apiKey(for: LLMProvider.groq)
    }

    var sttProvider: TranscriptionProvider {
        get { providerStore.transcriptionProvider }
        set { providerStore.transcriptionProvider = newValue }
    }

    var sttModel: String {
        get { providerStore.transcriptionModel }
        set { providerStore.transcriptionModel = newValue }
    }

    var dictationLanguage: DictationLanguage = {
        let raw = UserDefaults.standard.string(forKey: "lf_dictation_language") ?? "automatic"
        return DictationLanguage(rawValue: raw) ?? .automatic
    }() {
        didSet { UserDefaults.standard.set(dictationLanguage.rawValue, forKey: "lf_dictation_language") }
    }

    // Cloud LLM — forwarded through provider store for UI compatibility
    var llmModel: String {
        get { providerStore.dictationModel }
        set { providerStore.dictationModel = newValue }
    }

    // How cleaned text is inserted at the cursor (clipboard paste vs direct typing)
    var insertionMode: InsertionMode = {
        InsertionMode(rawValue: UserDefaults.standard.string(forKey: "lf_insertion_mode") ?? "") ?? .clipboardPaste
    }() {
        didSet { UserDefaults.standard.set(insertionMode.rawValue, forKey: "lf_insertion_mode") }
    }

    // Live on-device transcription preview in the recording overlay. Opt-in and experimental:
    // it runs a separate Apple recognizer alongside the recorder and never affects the final
    // transcript. Off by default so it can't touch the core dictation path.
    var liveTranscriptPreviewEnabled: Bool = UserDefaults.standard.bool(forKey: "lf_live_preview") {
        didSet { UserDefaults.standard.set(liveTranscriptPreviewEnabled, forKey: "lf_live_preview") }
    }

    var pressEnterCommandEnabled: Bool = {
        UserDefaults.standard.object(forKey: "lf_press_enter_enabled") as? Bool ?? true
    }() {
        didSet { UserDefaults.standard.set(pressEnterCommandEnabled, forKey: "lf_press_enter_enabled") }
    }

    // Show a Dock icon. Off by default — LazyFlow is a menu-bar utility; the menu bar icon
    // and the "Open LazyFlow" command keep the app fully reachable without a Dock presence.
    var showDockIcon: Bool = UserDefaults.standard.object(forKey: "lf_show_dock_icon") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "lf_show_dock_icon")
            AppState.applyActivationPolicy(showDockIcon: showDockIcon)
        }
    }

    /// Applies the Dock-icon preference. `.regular` shows a Dock icon; `.accessory` hides it
    /// (menu-bar-only). Must run on the main thread.
    static func applyActivationPolicy(showDockIcon: Bool) {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        if Thread.isMainThread {
            NSApp.setActivationPolicy(policy)
        } else {
            DispatchQueue.main.async { NSApp.setActivationPolicy(policy) }
        }
    }

    // STT backend
    var sttBackend: STTBackend = {
        let raw = UserDefaults.standard.string(forKey: "lazyflow_stt_backend") ?? "cloud"
        return STTBackend(rawValue: raw) ?? .cloud
    }() {
        didSet {
            UserDefaults.standard.set(sttBackend.rawValue, forKey: "lazyflow_stt_backend")
            if sttBackend == .cloud {
                Task { await localSTT.unload(localSTTModel) }
            }
        }
    }

    var localSTTModel: LocalSTTModel = {
        let raw = UserDefaults.standard.string(forKey: "lazyflow_local_stt_model") ?? LocalSTTModel.parakeetV3.rawValue
        return LocalSTTModel(rawValue: raw) ?? .parakeetV3
    }() {
        didSet { UserDefaults.standard.set(localSTTModel.rawValue, forKey: "lazyflow_local_stt_model") }
    }

    // LLM backend
    var llmBackend: LLMBackend = {
        let raw = UserDefaults.standard.string(forKey: "lazyflow_llm_backend") ?? "cloud"
        return LLMBackend(rawValue: raw) ?? .cloud
    }() {
        didSet {
            UserDefaults.standard.set(llmBackend.rawValue, forKey: "lazyflow_llm_backend")
            if llmBackend == .cloud {
                llmLoadTask?.cancel(); llmLoadTask = nil
                Task { await localLLM.unload(localLLMModel) }
                localLLMOpState = .idle
            }
        }
    }

    var localLLMModel: LocalLLMModel = {
        let raw = UserDefaults.standard.string(forKey: "lazyflow_local_llm_model") ?? LocalLLMModel.qwen3_0_6b.rawValue
        return LocalLLMModel(rawValue: raw) ?? .qwen3_0_6b
    }() {
        didSet { UserDefaults.standard.set(localLLMModel.rawValue, forKey: "lazyflow_local_llm_model") }
    }

    // MARK: - Local services

    let localSTT = LocalSTTService()
    let localLLM = LocalLLMService()

    // Observable download/load state — drives Settings UI
    var localSTTOpState: LocalOpState = .idle
    var localLLMOpState: LocalOpState = .idle

    private var llmLoadTask: Task<Void, Never>?

    // MARK: - Toggle / overlay state

    var isToggleMode: Bool = false
    private(set) var targetAppName: String?

    // MARK: - Callbacks (used by AppDelegate for non-SwiftUI observers)

    var onRecordingModeChanged: ((RecordingMode) -> Void)?
    var onRecordingCancelled:   (() -> Void)?  // notifies HotkeyManager to reset its state

    // MARK: - Profiles

    let profileStore = AppProfileStore()
    let snippetStore = SnippetStore()
    let permissions = PermissionsService()

    // MARK: - Knowledge Base

    let knowledgeStore = KnowledgeStore.shared

    // MARK: - Private state

    private let audioCapture = AudioCapture()
    private let speechPreview = SpeechPreviewService()

    // Target app captured at recording START so paste always goes to the right place
    private var recordingTargetApp: NSRunningApplication?

    // Focus context captured at recording START — the field that was focused when dictation began
    private var recordingFocusContext: FocusContext?

    // MARK: - Recording Pipeline

    func startRecording() {
        guard recordingMode == .idle else { return }

        // Check microphone permission before doing anything else
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .denied || micStatus == .restricted {
            errorMessage = "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone."
            return
        }
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard granted else {
                        self?.errorMessage = "Microphone access is required to use LazyFlow."
                        return
                    }
                    self?.startRecording()
                }
            }
            return
        }
        // .authorized falls through

        errorMessage    = nil
        liveTranscript  = ""
        currentTranscript = ""

        // Capture the frontmost app NOW — before any async work
        recordingTargetApp  = NSWorkspace.shared.frontmostApplication
        targetAppName       = recordingTargetApp?.localizedName
        recordingFocusContext = nil

        audioCapture.onLevelUpdate = { [weak self] level in
            Task { @MainActor [weak self] in self?.audioLevel = level }
        }

        do {
            // Start capturing audio before querying Accessibility. AX calls can occasionally
            // stall; they must never delay the microphone and clip the first spoken syllable.
            try audioCapture.start()
            recordingMode = .recording
            recordingFocusContext = recordingTargetApp.flatMap { FocusContextService.capture(for: $0) }

            // Best-effort live preview (opt-in). Never blocks or affects the real recording.
            if liveTranscriptPreviewEnabled {
                speechPreview.onPartial = { [weak self] text in self?.liveTranscript = text }
                speechPreview.start()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        guard recordingMode == .recording else { return }
        let releasedAt = Date()
        audioCapture.stop()
        let recorderFinalizationTime = Date().timeIntervalSince(releasedAt)
        speechPreview.stop()
        recordingMode = .processing
        audioLevel    = 0

        let audioURL      = audioCapture.outputURL
        let groqKey       = groqAPIKey
        let cloudSTT      = TranscriptionService(
            config: providerStore.transcriptionConfig(language: dictationLanguage.apiCode)
        )
        let dictCfg       = providerStore.dictationConfig
        // Fall back to the legacy single Groq key when the provider store has no key yet.
        let effectiveCfg: LLMConfig = dictCfg.apiKey.isEmpty
            ? LLMConfig(provider: .groq,
                        baseURL:  LLMProvider.groq.defaultBaseURL,
                        apiKey:   groqKey,
                        model:    LLMProvider.groq.defaultModel)
            : dictCfg
        let cloudLLM      = PostProcessingService(config: effectiveCfg)
        let capturedSTTBackend = sttBackend
        let capturedLLMBackend = llmBackend
        let targetApp    = recordingTargetApp
        let capturedKB   = knowledgeStore.contextBlock
        let capturedFocus = recordingFocusContext
        // Only create a profile for apps with a real bundle ID — nil-bundle apps
        // (e.g. some system processes) are excluded so they don't share a junk profile.
        let profile: AppProfile? = targetApp.flatMap { app in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return profileStore.profileOrDefault(
                for: bundleID,
                displayName: app.localizedName ?? bundleID
            )
        }

        let duration = audioCapture.recordingDuration

        // Build a focused vocabulary list for cloud and local transcription models.
        // Manual vocabulary is always included, followed by the most frequent corrections.
        let sttTerms: [String] = {
            guard let p = profile else { return [] }

            // Vocabulary words first (always included), then top-frequency correct spellings
            var terms: [String] = p.vocabulary
            let correctionTerms = correctionStore
                .allCorrections(for: p.bundleIdentifier)
                .sorted { $0.frequency > $1.frequency }
                .prefix(max(0, 20 - terms.count))
                .map(\.correct)
            terms.append(contentsOf: correctionTerms)

            // Deduplicate (case-insensitive)
            var seen = Set<String>()
            return terms.filter { seen.insert($0.lowercased()).inserted }
        }()

        let sttHint = sttTerms.isEmpty
            ? ""
            : "The following terms may appear in this transcript: \(sttTerms.joined(separator: ", "))."

#if DEBUG
        if !sttHint.isEmpty {
            print("[LazyFlow] 🎙 STT vocabulary: \(sttHint)")
        }
#endif

        Task {
            defer { audioCapture.cleanup() }
            guard let url = audioURL else { recordingMode = .idle; return }
            let preparationTime = Date().timeIntervalSince(releasedAt) - recorderFinalizationTime

            // Skip transcription for very short recordings — Whisper hallucinates
            // multilingual text on near-silence when given < ~0.8s of audio
            guard duration >= 0.8 else {
                print("[LazyFlow] ⏭ Recording too short (\(String(format: "%.2fs", duration))) — skipped")
                recordingMode = .idle
                return
            }

            do {
                // Route STT: configured cloud provider or on-device
                let sttStartedAt = Date()
                let raw: String
                switch capturedSTTBackend {
                case .cloud:
                    raw = try await cloudSTT.transcribe(audioURL: url, vocabularyTerms: sttTerms)
                case .local:
                    if localSTTOpState.isBusy {
                        recordingMode = .idle
                        errorMessage  = "Local STT model is still loading — try again in a moment."
                        return
                    }
                    raw = try await localSTT.transcribe(audioURL: url, vocabularyHint: sttHint)
                }
                let sttTime = Date().timeIntervalSince(sttStartedAt)

                // Strip vocal fillers before corrections and LLM — deterministic, cheap, and
                // catches cases the LLM might miss. Skipped when keepFillerWords is toggled on.
                let filterFillers = profile.map { !$0.formattingOptions.keepFillerWords } ?? true
                let defiltered    = filterFillers ? FillerWordFilter.filter(raw) : raw

                // Post-processing is best-effort — STT result is never lost if LLM fails
                var final = defiltered
                var cleanupTime: TimeInterval = 0
                if let p = profile {
                    do {
                        let corrections = correctionStore.relevantCorrections(
                            for: defiltered, bundleID: p.bundleIdentifier
                        )
                        // All corrections are applied as exact Swift substitutions before the
                        // LLM sees the text. LLM-based substitution is unreliable for proper
                        // names — the model capitalises, rephrases, or skips them unpredictably.
                        let application = CorrectionEngine.apply(defiltered, corrections: corrections)
                        let preApplied = application.text
                        final = preApplied
                        if !application.appliedIDs.isEmpty {
                            correctionStore.incrementFrequency(for: Array(application.appliedIDs))
                        }
                        let cleanupStartedAt = Date()
                        // Route LLM: configured cloud provider or on-device (MLX)
                        switch capturedLLMBackend {
                        case .cloud:
                            final = try await cloudLLM.process(
                                rawTranscript: preApplied,
                                profile: p,
                                corrections: [],
                                kbContext: capturedKB,
                                focusContext: capturedFocus)
                        case .local:
                            final = try await localLLM.process(
                                rawTranscript: preApplied,
                                profile: p,
                                corrections: [],
                                kbContext: capturedKB,
                                focusContext: capturedFocus)
                        }
                        cleanupTime = Date().timeIntervalSince(cleanupStartedAt)
                        let customAllowsTitleCase = p.customInstructions
                            .localizedCaseInsensitiveContains("title case")
                        final = OutputCapitalization.sanitize(
                            final,
                            reference: preApplied,
                            forceLowercase: p.formattingOptions.lowercase,
                            allowTitleCase: customAllowsTitleCase || capturedFocus?.allowsTitleCase == true,
                            protectedTerms: p.vocabulary + corrections.map(\.correct)
                        )
                    } catch {
                        print("[LazyFlow] ⚠️ Cleanup failed, pasting corrected transcript: \(error.localizedDescription)")
                        errorMessage = "Cleanup unavailable — transcript pasted."
                    }
                }

                let command = DictationCommands.prepare(
                    final,
                    pressEnterEnabled: pressEnterCommandEnabled
                )
                final = command.text
                if profile?.formattingOptions.omitTrailingPeriod == true {
                    final = DictationCommands.removeTrailingPeriod(from: final)
                }
                final = snippetStore.expand(in: final)

                let readyTime = Date().timeIntervalSince(releasedAt)
                let tone    = profile?.tone.displayName ?? "none"
                print("[LazyFlow] ✅ \(String(format: "%.2fs", readyTime)) | \(targetApp?.localizedName ?? "?") [\(tone)]")
                print("[LazyFlow] ⏱ finalize=\(Self.milliseconds(recorderFinalizationTime))ms prep=\(Self.milliseconds(preparationTime))ms stt=\(Self.milliseconds(sttTime))ms cleanup=\(Self.milliseconds(cleanupTime))ms ready=\(Self.milliseconds(readyTime))ms")

                // Return to idle and hide the overlay before restoring focus and inserting text.
                // Changing window state after posting ⌘V can disrupt delivery in some apps.
                finishProcessing(
                    transcript: final,
                    appName: targetApp?.localizedName,
                    bundleIdentifier: targetApp?.bundleIdentifier
                )
                pasteAtCursor(final, targetApp: targetApp, pressEnter: command.pressEnter)
            } catch {
                print("[LazyFlow] ❌ \(error.localizedDescription)")
                errorMessage  = error.localizedDescription
                recordingMode = .idle
            }
        }
    }

    func cancelRecording() {
        audioCapture.stop()
        speechPreview.stop()
        audioCapture.cleanup()
        recordingMode         = .idle
        audioLevel            = 0
        isToggleMode          = false
        targetAppName         = nil
        recordingFocusContext = nil
        liveTranscript        = ""
        onRecordingCancelled?()
    }

    func clearError() { errorMessage = nil }

    // MARK: - Local model management

    func loadLocalSTT(_ model: LocalSTTModel) {
        localSTTModel   = model
        localSTTOpState = .busy(progress: 0, status: "Starting…")
        Task {
            do {
                try await localSTT.load(model) { progress, status in
                    Task { @MainActor in
                        self.localSTTOpState = progress < 1.0
                            ? .busy(progress: progress, status: status)
                            : .idle
                    }
                }
                localSTTOpState = .idle
            } catch {
                localSTTOpState = .error(error.localizedDescription)
            }
        }
    }

    func deleteLocalSTT(_ model: LocalSTTModel) {
        Task {
            await localSTT.unload(model)
            LocalSTTService.delete(model)
        }
    }

    func loadLocalLLM(_ model: LocalLLMModel) {
        llmLoadTask?.cancel()
        localLLMModel   = model
        localLLMOpState = .busy(progress: 0, status: "Starting…")
        llmLoadTask = Task {
            do {
                try await localLLM.load(model) { progress, status in
                    Task { @MainActor in
                        self.localLLMOpState = progress < 1.0
                            ? .busy(progress: progress, status: status)
                            : .idle
                    }
                }
                guard !Task.isCancelled else { return }
                localLLMOpState = .idle
            } catch {
                guard !Task.isCancelled else { return }
                localLLMOpState = .error(error.localizedDescription)
            }
        }
    }

    func cancelLocalLLM() {
        llmLoadTask?.cancel()
        llmLoadTask = nil
        Task { await localLLM.unload(localLLMModel) }
        localLLMOpState = .idle
    }

    func deleteLocalLLM(_ model: LocalLLMModel) {
        Task {
            await localLLM.unload(model)
            LocalLLMService.delete(model)
        }
    }

    // Auto-load previously selected local models on launch — sequential so both
    // don't spike memory at the same time. STT loads first (faster, needed sooner);
    // LLM only starts once STT is fully resident.
    func setupLocalServicesIfNeeded() {
        let needSTT = sttBackend == .local && LocalSTTService.isDownloaded(localSTTModel)
        let needLLM = llmBackend == .local && LocalLLMService.isDownloaded(localLLMModel)
        guard needSTT || needLLM else { return }
        Task {
            if needSTT { await loadSTLAsync(localSTTModel) }
            if needLLM { loadLocalLLM(localLLMModel) }
        }
    }

    // Awaitable STT load — used only by setupLocalServicesIfNeeded for sequencing.
    private func loadSTLAsync(_ model: LocalSTTModel) async {
        localSTTModel   = model
        localSTTOpState = .busy(progress: 0, status: "Starting…")
        do {
            try await localSTT.load(model) { p, s in
                Task { @MainActor in
                    self.localSTTOpState = p < 1 ? .busy(progress: p, status: s) : .idle
                }
            }
            localSTTOpState = .idle
        } catch {
            localSTTOpState = .error(error.localizedDescription)
        }
    }

    // MARK: - Text Injection

    private func pasteAtCursor(
        _ text: String,
        targetApp: NSRunningApplication?,
        pressEnter: Bool
    ) {
        TextInjector.insert(
            text,
            into: targetApp,
            mode: insertionMode,
            pressEnter: pressEnter
        )
    }

    private func finishProcessing(transcript: String, appName: String?, bundleIdentifier: String?) {
        currentTranscript = transcript
        recordingMode     = .idle
        targetAppName     = nil
        guard !transcript.isEmpty else { return }
        let entry = TranscriptEntry(text: transcript, appName: appName, bundleIdentifier: bundleIdentifier)
        transcriptStore.insert(entry)
    }

    private static func milliseconds(_ interval: TimeInterval) -> Int {
        Int((max(0, interval) * 1000).rounded())
    }
}

// MARK: - Filler Word Filter

private enum FillerWordFilter {
    // Matches common vocal fillers (uh, um, er, hmm, etc.) plus optional trailing comma/period.
    // Word boundaries prevent clipping real words ("umbrella", "uh-oh", etc.).
    private static let pattern = try? NSRegularExpression(
        pattern: #"(?i)\b(u+h+|u+m+|e+r+|h?mm+|mhm)\b[,.]?\s*|uh-huh[,.]?\s*"#
    )

    static func filter(_ text: String) -> String {
        guard let pattern else { return text }
        var result = pattern.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: " "
        )
        // Collapse runs of spaces left by removals
        while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
        result = result.trimmingCharacters(in: .whitespaces)
        // Re-capitalize if a leading filler was removed
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }
}

// MARK: - Models

import GRDB

struct TranscriptEntry: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "transcripts"

    let id:               String
    let text:             String
    let date:             Date
    let appName:          String?
    let bundleIdentifier: String?

    init(text: String, appName: String?, bundleIdentifier: String?) {
        self.id              = UUID().uuidString
        self.text            = text
        self.date            = Date()
        self.appName         = appName
        self.bundleIdentifier = bundleIdentifier
    }

    // Used by CorrectionSheet to update the text of an existing entry
    func withText(_ newText: String) -> TranscriptEntry {
        TranscriptEntry(_id: id, text: newText, date: date,
                        appName: appName, bundleIdentifier: bundleIdentifier)
    }

    private init(_id: String, text: String, date: Date, appName: String?, bundleIdentifier: String?) {
        self.id              = _id
        self.text            = text
        self.date            = date
        self.appName         = appName
        self.bundleIdentifier = bundleIdentifier
    }
}
