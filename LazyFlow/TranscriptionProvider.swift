import Foundation

enum TranscriptionProvider: String, CaseIterable, Codable, Identifiable, Hashable {
    case groq
    case openAI = "openai"
    case elevenLabs = "elevenlabs"

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .groq:       "Groq"
        case .openAI:     "OpenAI"
        case .elevenLabs: "ElevenLabs"
        }
    }

    nonisolated var icon: String {
        switch self {
        case .groq:       "bolt.fill"
        case .openAI:     "brain"
        case .elevenLabs: "waveform"
        }
    }

    nonisolated var endpoint: URL {
        switch self {
        case .groq:
            URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        case .openAI:
            URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        case .elevenLabs:
            URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
        }
    }

    nonisolated var defaultModel: String { models[0].id }

    nonisolated var models: [TranscriptionModel] {
        switch self {
        case .groq:
            [
                TranscriptionModel(
                    id: "whisper-large-v3",
                    name: "Whisper Large v3",
                    badge: "Accurate",
                    detail: "Highest Groq accuracy across supported languages."
                ),
                TranscriptionModel(
                    id: "whisper-large-v3-turbo",
                    name: "Whisper Large Turbo",
                    badge: "Fast",
                    detail: "Lower latency with strong everyday accuracy."
                ),
            ]
        case .openAI:
            [
                TranscriptionModel(
                    id: "gpt-transcribe",
                    name: "GPT Transcribe",
                    badge: "Accurate",
                    detail: "OpenAI's high-accuracy file transcription model."
                ),
            ]
        case .elevenLabs:
            [
                TranscriptionModel(
                    id: "scribe_v2",
                    name: "Scribe v2",
                    badge: "Multilingual",
                    detail: "ElevenLabs transcription with profile keyterm prompting."
                ),
            ]
        }
    }

    nonisolated var credentialProvider: LLMProvider? {
        switch self {
        case .groq:       .groq
        case .openAI:     .openai
        case .elevenLabs: nil
        }
    }

    nonisolated var keychainKey: String {
        credentialProvider?.keychainKey ?? "lf_apikey_elevenlabs"
    }
}

struct TranscriptionModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let badge: String
    let detail: String
}

struct TranscriptionConfig {
    let provider: TranscriptionProvider
    let apiKey: String
    let model: String
}
