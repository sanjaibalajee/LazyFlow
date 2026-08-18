import SwiftUI

// MARK: - STT

enum STTBackend: String, Codable {
    case cloud  // Configured cloud transcription provider
    case local  // On-device (Parakeet v3 / WhisperKit)
}

enum LocalSTTModel: String, CaseIterable, Codable, Identifiable {
    case parakeetV3       = "parakeet-v3"
    case whisperSmall     = "whisper-small"
    case whisperLargeTurbo = "whisper-large-turbo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .parakeetV3:        return "Parakeet v3"
        case .whisperSmall:      return "Whisper Small"
        case .whisperLargeTurbo: return "Whisper Large Turbo"
        }
    }

    var sizeLabel: String {
        switch self {
        case .parakeetV3:        return "450 MB"
        case .whisperSmall:      return "250 MB"
        case .whisperLargeTurbo: return "~874 MB"
        }
    }

    var detail: String {
        switch self {
        case .parakeetV3:
            return "Fastest (~0.13 s). 25 languages. Runs entirely on the Neural Engine. Recommended."
        case .whisperSmall:
            return "Fast. English-only. CoreML on Neural Engine."
        case .whisperLargeTurbo:
            return "Best accuracy. Multilingual. Quantized CoreML on Neural Engine."
        }
    }

    var badge: String {
        switch self {
        case .parakeetV3:        return "Recommended"
        case .whisperSmall:      return "Lightweight"
        case .whisperLargeTurbo: return "Accurate"
        }
    }

    var badgeColor: Color {
        switch self {
        case .parakeetV3:        return .green
        case .whisperSmall:      return .blue
        case .whisperLargeTurbo: return .purple
        }
    }

    // WhisperKit variant string — nil means Parakeet (FluidAudio)
    nonisolated var whisperKitVariant: String? {
        switch self {
        case .parakeetV3:        return nil
        case .whisperSmall:      return "small.en"
        case .whisperLargeTurbo: return "large-v3-turbo"
        }
    }
}

// MARK: - LLM

enum LLMBackend: String, Codable {
    case cloud  // Configured cloud LLM provider
    case local  // MLX on-device
}

enum LocalLLMModel: String, CaseIterable, Codable, Identifiable {
    case qwen3_0_6b = "mlx-community/Qwen3-0.6B-4bit"
    case qwen3_1_7b = "mlx-community/Qwen3-1.7B-4bit"
    case qwen3_4b   = "mlx-community/Qwen3-4B-4bit"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwen3_0_6b: return "Qwen3 0.6B"
        case .qwen3_1_7b: return "Qwen3 1.7B"
        case .qwen3_4b:   return "Qwen3 4B"
        }
    }

    var sizeLabel: String {
        switch self {
        case .qwen3_0_6b: return "~390 MB"
        case .qwen3_1_7b: return "~1.0 GB"
        case .qwen3_4b:   return "~2.3 GB"
        }
    }

    var detail: String {
        switch self {
        case .qwen3_0_6b: return "~80 tok/s. Sufficient for dictation cleanup."
        case .qwen3_1_7b: return "~55 tok/s. Better tone reasoning, still fast."
        case .qwen3_4b:   return "~35 tok/s. Highest local quality."
        }
    }

    var badge: String {
        switch self {
        case .qwen3_0_6b: return "Fastest"
        case .qwen3_1_7b: return "Balanced"
        case .qwen3_4b:   return "Best Quality"
        }
    }

    var badgeColor: Color {
        switch self {
        case .qwen3_0_6b: return .green
        case .qwen3_1_7b: return .blue
        case .qwen3_4b:   return .purple
        }
    }
}

// MARK: - Operation state (shared by STT and LLM)

enum LocalOpState: Equatable {
    case idle
    case busy(progress: Double, status: String)
    case error(String)

    var isBusy: Bool {
        if case .busy = self { return true }
        return false
    }
}
