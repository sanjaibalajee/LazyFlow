import Foundation

enum LLMProvider: String, CaseIterable, Codable, Identifiable, Hashable {
    case groq
    case openai
    case google
    case anthropic
    case custom

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .groq:      "Groq"
        case .openai:    "OpenAI"
        case .google:    "Google AI Studio"
        case .anthropic: "Anthropic"
        case .custom:    "Custom"
        }
    }

    nonisolated var icon: String {
        switch self {
        case .groq:      "bolt.fill"
        case .openai:    "brain"
        case .google:    "sparkles"
        case .anthropic: "cpu"
        case .custom:    "server.rack"
        }
    }

    nonisolated var defaultBaseURL: String {
        switch self {
        case .groq:      "https://api.groq.com/openai/v1"
        case .openai:    "https://api.openai.com/v1"
        case .google:    "https://generativelanguage.googleapis.com/v1beta/openai"
        case .anthropic: "https://api.anthropic.com/v1"
        case .custom:    ""
        }
    }

    nonisolated var keychainKey: String { "lf_apikey_\(rawValue)" }

    nonisolated var presetModels: [LLMModel] {
        switch self {
        case .groq:
            [
                LLMModel(id: "openai/gpt-oss-20b", name: "GPT-OSS 20B", badge: "Fastest"),
                LLMModel(id: "qwen/qwen3.6-27b", name: "Qwen 3.6 27B", badge: "Balanced"),
                LLMModel(id: "openai/gpt-oss-120b", name: "GPT-OSS 120B", badge: "Best"),
            ]
        case .openai:
            [
                LLMModel(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", badge: "Recommended"),
                LLMModel(id: "gpt-5.4-mini", name: "GPT-5.4 mini", badge: "Balanced"),
                LLMModel(id: "gpt-5.4-nano", name: "GPT-5.4 nano", badge: "Cheapest"),
                LLMModel(id: "gpt-4.1", name: "GPT-4.1", badge: "Best"),
                LLMModel(id: "gpt-4.1-mini", name: "GPT-4.1 mini", badge: "Fast"),
                LLMModel(id: "gpt-4o", name: "GPT-4o", badge: "Stable"),
                LLMModel(id: "gpt-4o-mini", name: "GPT-4o mini", badge: "Cheap"),
                LLMModel(id: "o3", name: "o3", badge: "Powerful"),
            ]
        case .google:
            [
                LLMModel(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", badge: "Best"),
                LLMModel(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", badge: "Fast"),
                LLMModel(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", badge: "Stable"),
                LLMModel(id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", badge: "Cheap"),
            ]
        case .anthropic:
            [
                LLMModel(id: "claude-opus-4-8", name: "Claude Opus 4.8", badge: "Best"),
                LLMModel(id: "claude-sonnet-5", name: "Claude Sonnet 5", badge: "Smart"),
                LLMModel(id: "claude-haiku-4-5", name: "Claude Haiku 4.5", badge: "Fast"),
            ]
        case .custom:
            []
        }
    }

    nonisolated var defaultModel: String {
        switch self {
        case .groq:      "openai/gpt-oss-20b"
        case .openai:    "gpt-5.6-luna"
        case .google:    "gemini-2.5-flash"
        case .anthropic: "claude-haiku-4-5"
        case .custom:    ""
        }
    }
}

struct LLMModel: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var badge: String?
}

struct LLMConfig {
    let provider: LLMProvider
    let baseURL: String
    let apiKey: String
    let model: String

    nonisolated var isAnthropic: Bool { provider == .anthropic }
}
