import Foundation
import AppKit
import AVFoundation
import Observation

@Observable
final class AppState {

    // MARK: - Recording

    var isRecording    = false
    var recordingMode: RecordingMode = .idle
    var audioLevel:    Float = 0

    enum RecordingMode { case idle, recording, processing }

    // MARK: - Transcript

    var liveTranscript    = ""
    var currentTranscript = ""
    var errorMessage:     String?

    // MARK: - History (backed by TranscriptStore → GRDB)

    var history: [TranscriptEntry] { transcriptStore.entries }
    let transcriptStore  = TranscriptStore()
    let correctionStore  = CorrectionStore()

    // MARK: - Settings  (API key stored in Keychain; model choices in UserDefaults)

    var apiKey: String = Keychain.load(forKey: "groq_api_key") ?? "" {
        didSet {
            apiKey.isEmpty
                ? Keychain.delete(forKey: "groq_api_key")
                : Keychain.save(apiKey, forKey: "groq_api_key")
        }
    }

    var sttModel: String = UserDefaults.standard.string(forKey: "lazyflow_stt_model") ?? "whisper-large-v3" {
        didSet { UserDefaults.standard.set(sttModel, forKey: "lazyflow_stt_model") }
    }

    var llmModel: String = UserDefaults.standard.string(forKey: "lazyflow_llm_model") ?? "llama-3.3-70b-versatile" {
        didSet { UserDefaults.standard.set(llmModel, forKey: "lazyflow_llm_model") }
    }

    // MARK: - Callbacks (used by AppDelegate for non-SwiftUI observers)

    var onRecordingChanged: ((Bool) -> Void)?

    // MARK: - Profiles

    let profileStore = AppProfileStore()

    // MARK: - Private state

    private let audioCapture = AudioCapture()

    // Target app captured at recording START so paste always goes to the right place
    private var recordingTargetApp: NSRunningApplication?

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
        recordingTargetApp = NSWorkspace.shared.frontmostApplication

        audioCapture.onLevelUpdate = { [weak self] level in
            Task { @MainActor [weak self] in self?.audioLevel = level }
        }

        do {
            try audioCapture.start()
            isRecording   = true
            recordingMode = .recording
            onRecordingChanged?(true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        guard recordingMode == .recording else { return }
        audioCapture.stop()
        isRecording   = false
        recordingMode = .processing
        audioLevel    = 0
        onRecordingChanged?(false)

        let audioURL  = audioCapture.outputURL
        let stt       = TranscriptionService(apiKey: apiKey, model: sttModel)
        let llm       = PostProcessingService(apiKey: apiKey, model: llmModel)
        let targetApp = recordingTargetApp
        // Only create a profile for apps with a real bundle ID — nil-bundle apps
        // (e.g. some system processes) are excluded so they don't share a junk profile.
        let profile: AppProfile? = targetApp.flatMap { app in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return profileStore.profileOrDefault(
                for: bundleID,
                displayName: app.localizedName ?? bundleID
            )
        }

        let startedAt = Date()

        let duration = audioCapture.recordingDuration

        // Build the Whisper prompt hint.
        //
        // Whisper treats the `prompt` field as preceding context — it continues the text,
        // so a natural sentence activates vocabulary biasing much more effectively than a
        // raw comma-separated list. Cap corrections at 20 by frequency so the prompt stays
        // focused; vocabulary words (manually added) always get included in full.
        let sttHint: String = {
            guard let p = profile else { return "" }

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
            let unique = terms.filter { seen.insert($0.lowercased()).inserted }
            guard !unique.isEmpty else { return "" }

            // Shape into a natural sentence so Whisper treats these as in-context words
            // rather than an unrelated vocabulary dump.
            let listed = unique.joined(separator: ", ")
            return "The following terms may appear in this transcript: \(listed)."
        }()

#if DEBUG
        if !sttHint.isEmpty {
            print("[LazyFlow] 🎙 Whisper prompt: \(sttHint)")
        }
#endif

        Task {
            defer { audioCapture.cleanup() }
            guard let url = audioURL else { recordingMode = .idle; return }

            // Skip transcription for very short recordings — Whisper hallucinates
            // multilingual text on near-silence when given < ~0.8s of audio
            guard duration >= 0.8 else {
                print("[LazyFlow] ⏭ Recording too short (\(String(format: "%.2fs", duration))) — skipped")
                recordingMode = .idle
                return
            }

            do {
                let raw = try await stt.transcribe(audioURL: url, vocabularyHint: sttHint)

                // Post-processing is best-effort — STT result is never lost if LLM fails
                var final = raw
                if let p = profile {
                    do {
                        let corrections = correctionStore.relevantCorrections(
                            for: raw, bundleID: p.bundleIdentifier
                        )
                        // All corrections are applied as exact Swift substitutions before the
                        // LLM sees the text. LLM-based substitution is unreliable for proper
                        // names — the model capitalises, rephrases, or skips them unpredictably.
                        let preApplied = applyCorrections(raw, corrections: corrections)
                        final = try await llm.process(rawTranscript: preApplied, profile: p,
                                                      corrections: [])
                        if !corrections.isEmpty {
                            correctionStore.incrementFrequency(for: corrections.map(\.id))
                        }
                    } catch {
                        print("[LazyFlow] ⚠️ Cleanup failed, pasting raw transcript: \(error.localizedDescription)")
                        errorMessage = "Cleanup unavailable — raw transcript pasted."
                    }
                }

                let elapsed = Date().timeIntervalSince(startedAt)
                let tone    = profile?.tone.displayName ?? "none"
                print("[LazyFlow] ✅ \(String(format: "%.2fs", elapsed)) | \(targetApp?.localizedName ?? "?") [\(tone)]")
                finishProcessing(transcript: final,
                                 appName: targetApp?.localizedName,
                                 bundleIdentifier: targetApp?.bundleIdentifier)
                pasteAtCursor(final, targetApp: targetApp)
            } catch {
                print("[LazyFlow] ❌ \(error.localizedDescription)")
                errorMessage  = error.localizedDescription
                recordingMode = .idle
            }
        }
    }

    func cancelRecording() {
        audioCapture.stop()
        audioCapture.cleanup()
        isRecording       = false
        recordingMode     = .idle
        audioLevel        = 0
        liveTranscript    = ""
        onRecordingChanged?(false)
    }

    func clearError() { errorMessage = nil }

    // MARK: - Text Injection

    private func pasteAtCursor(_ text: String, targetApp: NSRunningApplication?) {
        let pb = NSPasteboard.general

        // Preserve ALL clipboard types, not just plain string
        let saved = ClipboardSnapshot(pb)

        pb.clearContents()
        pb.setString(text, forType: .string)
        let changeCountAfterWrite = pb.changeCount

        // Re-activate the app that was frontmost when recording started
        let activate: () -> Void = {
            targetApp?.activate()
        }
        let paste: () -> Void = {
            let src   = CGEventSource(stateID: .hidSystemState)
            let down  = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let up    = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            down?.flags = .maskCommand
            up?.flags   = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }

        activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            paste()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                // Only restore if nothing else has written to the clipboard since we did —
                // if changeCount changed, the user copied something new and we leave it alone.
                guard pb.changeCount == changeCountAfterWrite else { return }
                saved.restore(to: pb)
            }
        }
    }

    // MARK: - Helpers

    // Applies correction pairs as exact Swift substitutions (case-insensitive, word-boundary-aware).
    // Normalises the heard key at match time so entries stored with punctuation ("rishin,") work
    // identically to clean ones ("rishin") — surrounding punctuation in the text is preserved.
    private func applyCorrections(_ text: String, corrections: [CorrectionEntry]) -> String {
        let punct = CharacterSet(charactersIn: ".,;:!?\"'")
        var result = text
        for correction in corrections.sorted(by: { $0.frequency > $1.frequency }) {
            let heard = correction.heard
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: punct)
            guard !heard.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: heard)
            guard let regex = try? NSRegularExpression(pattern: "(?i)\\b\(escaped)\\b") else { continue }
            let full = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: full,
                withTemplate: NSRegularExpression.escapedTemplate(for: correction.correct)
            )
        }
        return result
    }

    private func finishProcessing(transcript: String, appName: String?, bundleIdentifier: String?) {
        currentTranscript = transcript
        recordingMode     = .idle
        guard !transcript.isEmpty else { return }
        let entry = TranscriptEntry(text: transcript, appName: appName, bundleIdentifier: bundleIdentifier)
        transcriptStore.insert(entry)
    }
}

// MARK: - Full clipboard preservation

private struct ClipboardSnapshot {
    private struct Item {
        let types: [NSPasteboard.PasteboardType]
        let data:  [NSPasteboard.PasteboardType: Data]
    }
    private let items: [Item]

    init(_ pb: NSPasteboard) {
        items = (pb.pasteboardItems ?? []).map { raw in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in raw.types { data[type] = raw.data(forType: type) }
            return Item(types: raw.types, data: data)
        }
    }

    func restore(to pb: NSPasteboard) {
        pb.clearContents()
        let restored: [NSPasteboardItem] = items.map { saved in
            let item = NSPasteboardItem()
            for type in saved.types {
                if let d = saved.data[type] { item.setData(d, forType: type) }
            }
            return item
        }
        pb.writeObjects(restored)
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
        var copy = self
        return TranscriptEntry(_id: id, text: newText, date: date,
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
