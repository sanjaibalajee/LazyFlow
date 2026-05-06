import Foundation
import AppKit
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

    // MARK: - History

    var history: [TranscriptEntry] = []

    // MARK: - Settings  (API key stored in Keychain, not UserDefaults)

    var apiKey: String = Keychain.load(forKey: "groq_api_key") ?? "" {
        didSet {
            apiKey.isEmpty
                ? Keychain.delete(forKey: "groq_api_key")
                : Keychain.save(apiKey, forKey: "groq_api_key")
        }
    }

    // MARK: - Callbacks (used by AppDelegate for non-SwiftUI observers)

    var onRecordingChanged: ((Bool) -> Void)?

    // MARK: - Private state

    private let audioCapture = AudioCapture()

    // Target app captured at recording START so paste always goes to the right place
    private var recordingTargetApp: NSRunningApplication?

    // MARK: - Recording Pipeline

    func startRecording() {
        guard recordingMode == .idle else { return }
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
        let service   = TranscriptionService(apiKey: apiKey)
        let targetApp = recordingTargetApp

        let startedAt = Date()

        Task {
            defer { audioCapture.cleanup() }
            guard let url = audioURL else { recordingMode = .idle; return }
            do {
                let transcript = try await service.transcribe(audioURL: url)
                let elapsed = Date().timeIntervalSince(startedAt)
                print("[LazyFlow] ✅ \(String(format: "%.2fs", elapsed)) | \(targetApp?.localizedName ?? "unknown app") | \"\(transcript)\"")
                finishProcessing(transcript: transcript,
                                 appName: targetApp?.localizedName,
                                 bundleIdentifier: targetApp?.bundleIdentifier)
                pasteAtCursor(transcript, targetApp: targetApp)
            } catch {
                print("[LazyFlow] ❌ Transcription failed: \(error.localizedDescription)")
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                saved.restore(to: pb)
            }
        }
    }

    // MARK: - Helpers

    private func finishProcessing(transcript: String, appName: String?, bundleIdentifier: String?) {
        currentTranscript = transcript
        recordingMode     = .idle
        guard !transcript.isEmpty else { return }
        let entry = TranscriptEntry(text: transcript, appName: appName, bundleIdentifier: bundleIdentifier)
        history.insert(entry, at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
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

struct TranscriptEntry: Identifiable {
    let id   = UUID()
    let text: String
    let date = Date()
    let appName:          String?
    let bundleIdentifier: String?
}
