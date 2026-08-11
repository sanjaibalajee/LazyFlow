import Foundation
import Speech
import AVFoundation

// Optional, opt-in live transcription preview using Apple's on-device recognizer.
//
// It runs ALONGSIDE the real recorder purely to populate the overlay with partial text —
// it never affects the final transcript, which still comes from Groq/Parakeet. It's a
// completely separate audio consumer from `AudioCapture`, and every failure is swallowed,
// so it cannot disrupt the core dictation flow. Off by default (see AppState.liveTranscriptPreviewEnabled).
final class SpeechPreviewService {
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Delivered on the main thread as partial results arrive.
    var onPartial: ((String) -> Void)?

    static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { completion(status == .authorized) }
        }
    }

    func start() {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              let recognizer, recognizer.isAvailable else { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input  = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A zero-channel/invalid input format means no usable mic route — bail quietly.
        guard format.channelCount > 0 else { request = nil; return }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            cleanup()
            return
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { self?.onPartial?(text) }
            }
            if error != nil || (result?.isFinal ?? false) {
                DispatchQueue.main.async { self?.cleanup() }
            }
        }
    }

    func stop() { cleanup() }

    private func cleanup() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
