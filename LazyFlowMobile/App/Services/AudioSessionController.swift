import AVFoundation
import Foundation

enum AudioSessionError: LocalizedError {
    case permissionDenied
    case unavailableInput
    case noRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Microphone access is required for a voice session."
        case .unavailableInput:
            "No microphone input is available."
        case .noRecording:
            "There is no recording to transcribe."
        }
    }
}

@MainActor
final class AudioSessionController: ObservableObject {
    @Published private(set) var isArmed = false
    @Published private(set) var isRecording = false
    @Published private(set) var level = 0.0

    private let engine = AVAudioEngine()
    private let sink = AudioFileSink()
    private var lastMeterUpdate = Date.distantPast

    func arm() async throws {
        guard await requestPermission() else {
            throw AudioSessionError.permissionDenied
        }
        guard !isArmed else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.allowBluetoothHFP, .duckOthers]
        )
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioSessionError.unavailableInput
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self, sink] buffer, _ in
            sink.append(buffer)
            let measuredLevel = Self.meterLevel(for: buffer)
            Task { @MainActor [weak self] in
                self?.receiveMeterLevel(measuredLevel)
            }
        }

        engine.prepare()
        do {
            try engine.start()
            isArmed = true
        } catch {
            input.removeTap(onBus: 0)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    func beginRecording() throws {
        guard isArmed else { throw AudioSessionError.unavailableInput }
        let format = engine.inputNode.outputFormat(forBus: 0)
        try sink.begin(format: format)
        isRecording = true
    }

    func finishRecording() throws -> URL {
        guard isRecording, let url = sink.finish() else {
            throw AudioSessionError.noRecording
        }
        isRecording = false
        level = 0
        return url
    }

    func cancelRecording() {
        if let url = sink.finish() {
            try? FileManager.default.removeItem(at: url)
        }
        isRecording = false
        level = 0
    }

    func disarm() {
        cancelRecording()
        guard isArmed else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        isArmed = false
    }

    private func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func receiveMeterLevel(_ value: Double) {
        guard isRecording else {
            level = 0
            return
        }
        guard Date().timeIntervalSince(lastMeterUpdate) > 0.08 else { return }
        lastMeterUpdate = Date()
        level = (level * 0.35) + (value * 0.65)
    }

    nonisolated private static func meterLevel(for buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?.pointee else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        let decibels = 20 * log10(max(rms, 0.000_001))
        return Double(max(0, min(1, (decibels + 52) / 42)))
    }
}

private final class AudioFileSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var url: URL?

    func begin(format: AVAudioFormat) throws {
        lock.lock()
        defer { lock.unlock() }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("lazyflow-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        file = try AVAudioFile(forWriting: destination, settings: format.settings)
        url = destination
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        try? file?.write(from: buffer)
    }

    func finish() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        file = nil
        defer { url = nil }
        return url
    }
}
