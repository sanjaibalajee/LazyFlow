import Foundation

// MARK: - Provider enum (mirrors Tachikoma's Provider design)

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

    // OpenAI-compatible base URL (Google uses OpenAI-compat via their REST endpoint)
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

    // Whether this provider needs an API key
    nonisolated var requiresKey: Bool { self != .custom || true }

    // Preset model catalog for this provider
    nonisolated var presetModels: [LLMModel] {
        switch self {
        case .groq:
            return [
                LLMModel(id: "llama-3.3-70b-versatile",                      name: "Llama 3.3 70B",        vision: false, tools: true,  badge: "Fast"),
                LLMModel(id: "meta-llama/llama-4-scout-17b-16e-instruct",     name: "Llama 4 Scout",        vision: true,  tools: true,  badge: "Vision"),
                LLMModel(id: "meta-llama/llama-4-maverick-17b-128e-instruct", name: "Llama 4 Maverick",     vision: true,  tools: true,  badge: "Best"),
                LLMModel(id: "llama-3.1-8b-instant",                         name: "Llama 3.1 8B",         vision: false, tools: true,  badge: "Fastest"),
                LLMModel(id: "moonshotai/kimi-k2-instruct",                   name: "Kimi K2",              vision: false, tools: true,  badge: "Coding"),
            ]
        case .openai:
            return [
                LLMModel(id: "gpt-4.1",      name: "GPT-4.1",      vision: true,  tools: true,  badge: "Best"),
                LLMModel(id: "gpt-4.1-mini", name: "GPT-4.1 mini", vision: true,  tools: true,  badge: "Fast"),
                LLMModel(id: "gpt-4o",       name: "GPT-4o",       vision: true,  tools: true,  badge: "Stable"),
                LLMModel(id: "gpt-4o-mini",  name: "GPT-4o mini",  vision: true,  tools: true,  badge: "Cheap"),
                LLMModel(id: "o4-mini",      name: "o4 mini",      vision: true,  tools: true,  badge: "Reasoning"),
                LLMModel(id: "o3",           name: "o3",            vision: true,  tools: true,  badge: "Powerful"),
            ]
        case .google:
            return [
                LLMModel(id: "gemini-2.5-pro",   name: "Gemini 2.5 Pro",        vision: true, tools: true, badge: "Best"),
                LLMModel(id: "gemini-2.5-flash",  name: "Gemini 2.5 Flash",      vision: true, tools: true, badge: "Fast"),
                LLMModel(id: "gemini-2.0-flash",  name: "Gemini 2.0 Flash",      vision: true, tools: true, badge: "Stable"),
                LLMModel(id: "gemini-1.5-flash",  name: "Gemini 1.5 Flash",      vision: true, tools: true, badge: "Cheap"),
            ]
        case .anthropic:
            return [
                LLMModel(id: "claude-opus-4-7",           name: "Claude Opus 4",      vision: true, tools: true,  badge: "Best"),
                LLMModel(id: "claude-sonnet-4-6",         name: "Claude Sonnet 4",    vision: true, tools: true,  badge: "Smart"),
                LLMModel(id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5",   vision: true, tools: true,  badge: "Fast"),
            ]
        case .custom:
            return []
        }
    }

    // Sensible default model for each use-case
    nonisolated func defaultModel(for usage: LLMUsage) -> String {
        switch (self, usage) {
        case (.groq, .dictation):    "llama-3.3-70b-versatile"
        case (.groq, .agent):        "meta-llama/llama-4-scout-17b-16e-instruct"
        case (.openai, .dictation):  "gpt-4.1-mini"
        case (.openai, .agent):      "gpt-4.1"
        case (.google, .dictation):  "gemini-2.5-flash"
        case (.google, .agent):      "gemini-2.5-pro"
        case (.anthropic, .dictation): "claude-haiku-4-5-20251001"
        case (.anthropic, .agent):     "claude-opus-4-7"
        case (.custom, _):             ""
        }
    }
}

// MARK: - Model descriptor

struct LLMModel: Codable, Identifiable, Hashable {
    var id:     String
    var name:   String
    var vision: Bool
    var tools:  Bool
    var badge:  String?
}

// MARK: - Usage context

enum LLMUsage {
    case dictation   // transcript cleanup
    case agent       // computer use loop (needs vision + tools)
}

// MARK: - Resolved config passed to services

struct LLMConfig {
    let provider:  LLMProvider
    let baseURL:   String       // may differ from provider.defaultBaseURL for custom
    let apiKey:    String
    let model:     String
    let modelSpec: LLMModel?

    nonisolated var supportsVision: Bool { modelSpec?.vision ?? false }
    nonisolated var supportsTools:  Bool { modelSpec?.tools  ?? false }

    // Anthropic uses a different message format — flag it for callers
    nonisolated var isAnthropic: Bool { provider == .anthropic }
}
