import Foundation
import CoreML
import WhisperKit
import FluidAudio

// MARK: - Service

actor LocalSTTService {

    private enum Backend {
        case parakeet(AsrManager)
        case whisper(WhisperKit)
    }

    private var backend: Backend?
    private(set) var loadedModel: LocalSTTModel?

    var isReady: Bool { backend != nil }

    // MARK: - Load

    func load(_ model: LocalSTTModel,
              onProgress: @escaping @Sendable (Double, String) -> Void) async throws {
        if loadedModel == model, backend != nil { return }
        backend   = nil
        loadedModel = nil

        switch model {
        case .parakeetV3:
            try await loadParakeet(onProgress: onProgress)
        case .whisperSmall, .whisperLargeTurbo:
            guard let variant = model.whisperKitVariant else { return }
            try await loadWhisper(variant: variant, onProgress: onProgress)
        }
        loadedModel = model
    }

    // MARK: - Transcribe

    func transcribe(audioURL: URL, vocabularyHint: String = "") async throws -> String {
        guard let backend else { throw LocalSTTError.notLoaded }
        switch backend {
        case .parakeet(let manager):
            // FluidAudio 0.15+ transcription is decoder-state driven; one-shot files use a fresh state.
            var decoderState = try TdtDecoderState()
            let result = try await manager.transcribe(audioURL, decoderState: &decoderState)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .whisper(let kit):
            let results = try await kit.transcribe(audioPath: audioURL.path)
            return results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Unload (clears memory without touching disk)

    func unload(_ model: LocalSTTModel) {
        guard loadedModel == model else { return }
        backend     = nil
        loadedModel = nil
    }

    // MARK: - Disk helpers (static — callable without actor hop)

    static func isDownloaded(_ model: LocalSTTModel) -> Bool {
        switch model {
        case .parakeetV3:
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml")
            // Require the vocab file as a proxy for a complete install
            let vocab = dir.appendingPathComponent("parakeet_vocab.json")
            return FileManager.default.fileExists(atPath: vocab.path)
        case .whisperSmall, .whisperLargeTurbo:
            guard let variant = model.whisperKitVariant else { return false }
            return whisperIsDownloaded(variant)
        }
    }

    static func delete(_ model: LocalSTTModel) {
        switch model {
        case .parakeetV3:
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml")
            try? FileManager.default.removeItem(at: dir)
        case .whisperSmall, .whisperLargeTurbo:
            if let variant = model.whisperKitVariant { deleteWhisper(variant) }
        }
    }

    // MARK: - Parakeet (FluidAudio)

    private func loadParakeet(onProgress: @escaping @Sendable (Double, String) -> Void) async throws {
        onProgress(0.03, "Downloading Parakeet v3…")
        let models = try await AsrModels.downloadAndLoad(version: .v3) { p in
            let frac = min(max(p.fractionCompleted * 0.85, 0.03), 0.85)
            onProgress(frac, "Downloading… \(Int(frac / 0.85 * 100))%")
        }
        onProgress(0.90, "Initializing…")
        let manager = AsrManager(config: .default, models: models)
        backend = .parakeet(manager)
        onProgress(1.0, "Ready")
    }

    // MARK: - WhisperKit

    private func loadWhisper(variant: String,
                             onProgress: @escaping @Sendable (Double, String) -> Void) async throws {
        let totalBytes = Self.whisperEstimatedBytes(variant)
        let totalLabel = Self.formatMB(totalBytes)

        let modelFolder: URL?
        if Self.whisperIsDownloaded(variant) {
            modelFolder = nil
            onProgress(0.5, "Loading model…")
        } else {
            onProgress(0.02, "0 MB / \(totalLabel)")
            modelFolder = try await WhisperKit.download(variant: variant) { p in
                let frac = min(max(p.fractionCompleted * 0.85, 0.02), 0.85)
                let done = Self.formatMB(Int64(Double(totalBytes) * (frac / 0.85)))
                let bps  = p.userInfo[.throughputKey] as? Double ?? 0
                let status = bps > 0
                    ? "\(done) / \(totalLabel) · \(Self.formatMB(Int64(bps)))/s"
                    : "\(done) / \(totalLabel)"
                onProgress(frac, status)
            }
        }

        onProgress(0.88, "Initializing CoreML…")
        let config = WhisperKitConfig(
            model:       modelFolder == nil ? variant : nil,
            modelFolder: modelFolder?.path,
            computeOptions: ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute:  .cpuAndNeuralEngine
            )
        )
        let kit = try await WhisperKit(config)

        // Warmup: pays the CoreML compilation cost now so first dictation is instant
        onProgress(0.95, "Warming up…")
        let silence = [Float](repeating: 0, count: 16_000)
        let _ = try await kit.transcribe(audioArray: silence)

        backend = .whisper(kit)
        onProgress(1.0, "Ready")
    }

    // MARK: - Whisper static helpers

    private static func whisperIsDownloaded(_ variant: String) -> Bool {
        let fullName = variant.hasPrefix("openai_whisper-") ? variant : "openai_whisper-\(variant)"
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml/\(fullName)")
        return FileManager.default.fileExists(atPath: dir.path)
    }

    private static func deleteWhisper(_ variant: String) {
        let fullName = variant.hasPrefix("openai_whisper-") ? variant : "openai_whisper-\(variant)"
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml/\(fullName)")
        try? FileManager.default.removeItem(at: dir)
    }

    private static func whisperEstimatedBytes(_ variant: String) -> Int64 {
        switch variant {
        case "small.en":       return 250 * 1_000_000
        case "large-v3-turbo": return 874 * 1_000_000
        default:                         return 250 * 1_000_000
        }
    }

    private static func formatMB(_ bytes: Int64) -> String {
        bytes >= 1_000_000_000
            ? String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
            : "\(bytes / 1_000_000) MB"
    }
}

// MARK: - Error

enum LocalSTTError: LocalizedError {
    case notLoaded
    var errorDescription: String? {
        "Local STT model not ready. Select and download a model in Settings → Transcription."
    }
}
