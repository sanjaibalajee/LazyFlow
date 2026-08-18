import Foundation

enum TranscriptionProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case apple
    case groq

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple On-Device"
        case .groq: "Groq Cloud"
        }
    }

    var subtitle: String {
        switch self {
        case .apple: "Private, downloaded to this iPhone"
        case .groq: "Fast multilingual Whisper transcription"
        }
    }
}

enum RewriteProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case apple
    case groq

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple On-Device"
        case .groq: "Groq Cloud"
        }
    }

    var subtitle: String {
        switch self {
        case .apple: "Foundation Models, with a local fallback"
        case .groq: "More consistent tone control across devices"
        }
    }
}

enum GroqSpeechModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case turbo = "whisper-large-v3-turbo"
    case accurate = "whisper-large-v3"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .turbo: "Whisper Large V3 Turbo"
        case .accurate: "Whisper Large V3"
        }
    }

    var subtitle: String {
        switch self {
        case .turbo: "Fastest · best price/performance"
        case .accurate: "Highest accuracy · supports translation"
        }
    }
}

enum GroqRewriteModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case fast = "openai/gpt-oss-20b"
    case quality = "openai/gpt-oss-120b"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: "GPT-OSS 20B"
        case .quality: "GPT-OSS 120B"
        }
    }

    var subtitle: String {
        switch self {
        case .fast: "Fast · recommended for everyday dictation"
        case .quality: "Best rewrite quality · slightly slower"
        }
    }
}

struct ProcessingConfiguration: Sendable {
    var transcriptionProvider: TranscriptionProvider
    var rewriteProvider: RewriteProvider
    var speechModel: GroqSpeechModel
    var rewriteModel: GroqRewriteModel
    var groqAPIKey: String
}

struct ProcessingResult: Sendable {
    var transcript: String
    var finalText: String
    var transcriptionLabel: String
    var rewriteLabel: String
}
