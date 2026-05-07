import AVFoundation

enum AudioCaptureError: LocalizedError {
    case noInputAvailable

    var errorDescription: String? { "No microphone input available." }
}

final class AudioCapture {
    private var recorder: AVAudioRecorder?
    private(set) var outputURL: URL?

    var onLevelUpdate: ((Float) -> Void)?
    private var levelTimer: Timer?

    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey:               Int(kAudioFormatLinearPCM),
            AVSampleRateKey:             16000.0,
            AVNumberOfChannelsKey:       1,
            AVLinearPCMBitDepthKey:      16,
            AVLinearPCMIsFloatKey:       false,
            AVLinearPCMIsBigEndianKey:   false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.isMeteringEnabled = true
        guard rec.record() else { throw AudioCaptureError.noInputAvailable }

        recorder          = rec
        outputURL         = url
        recordingStartedAt = Date()

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let rec = self?.recorder else { return }
            rec.updateMeters()
            let db    = rec.averagePower(forChannel: 0)
            let level = max(0, (db + 50) / 50)
            self?.onLevelUpdate?(level)
        }
    }

    // Duration in seconds of the completed recording
    private(set) var recordingDuration: TimeInterval = 0
    private var recordingStartedAt: Date?

    func stop() {
        levelTimer?.invalidate()
        levelTimer = nil
        recordingDuration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recorder?.stop()
        recorder = nil
    }

    func cleanup() {
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
            outputURL = nil
        }
    }
}
