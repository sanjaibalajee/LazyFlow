import Foundation
import Observation

// MARK: - Store

@Observable
final class LLMProviderStore {
    static let shared = LLMProviderStore()

    /// Keychain access may require user approval on macOS. Keep decrypted values in
    /// memory for this process so SwiftUI rendering and config reads never trigger
    /// another Keychain lookup.
    @ObservationIgnored private var cachedAPIKeys: [LLMProvider: String] = [:]
    @ObservationIgnored private var loadedAPIKeys: Set<LLMProvider> = []
    @ObservationIgnored private var cachedElevenLabsKey = ""
    @ObservationIgnored private var loadedElevenLabsKey = false

    // MARK: - Persisted selections

    var dictationProvider: LLMProvider = LLMProvider(rawValue: UserDefaults.standard.string(forKey: "lf_dict_provider") ?? "") ?? .groq {
        didSet { UserDefaults.standard.set(dictationProvider.rawValue, forKey: "lf_dict_provider") }
    }
    var dictationModel: String = UserDefaults.standard.string(forKey: "lf_dict_model") ?? LLMProvider.groq.defaultModel(for: .dictation) {
        didSet { UserDefaults.standard.set(dictationModel, forKey: "lf_dict_model") }
    }

    var transcriptionProvider: TranscriptionProvider = {
        let raw = UserDefaults.standard.string(forKey: "lf_stt_provider") ?? ""
        return TranscriptionProvider(rawValue: raw) ?? .groq
    }() {
        didSet { UserDefaults.standard.set(transcriptionProvider.rawValue, forKey: "lf_stt_provider") }
    }

    var transcriptionModel: String = {
        let raw = UserDefaults.standard.string(forKey: "lf_stt_provider") ?? ""
        let provider = TranscriptionProvider(rawValue: raw) ?? .groq
        let stored = UserDefaults.standard.string(forKey: "lf_stt_model")
            ?? UserDefaults.standard.string(forKey: "lazyflow_stt_model")
            ?? ""
        return provider.models.contains(where: { $0.id == stored }) ? stored : provider.defaultModel
    }() {
        didSet { UserDefaults.standard.set(transcriptionModel, forKey: "lf_stt_model") }
    }

    var agentProvider: LLMProvider = LLMProvider(rawValue: UserDefaults.standard.string(forKey: "lf_agent_provider") ?? "") ?? .groq {
        didSet { UserDefaults.standard.set(agentProvider.rawValue, forKey: "lf_agent_provider") }
    }
    var agentModel: String = {
        let provider = LLMProvider(rawValue: UserDefaults.standard.string(forKey: "lf_agent_provider") ?? "") ?? .groq
        let stored   = UserDefaults.standard.string(forKey: "lf_agent_model") ?? ""
        // Reset to default if stored model is not in this provider's preset list
        if !stored.isEmpty && provider.presetModels.contains(where: { $0.id == stored }) {
            return stored
        }
        let def = provider.defaultModel(for: .agent)
        UserDefaults.standard.set(def, forKey: "lf_agent_model")
        return def
    }() {
        didSet { UserDefaults.standard.set(agentModel, forKey: "lf_agent_model") }
    }

    // Custom provider overrides (base URL for when provider == .custom)
    var customBaseURL: String = UserDefaults.standard.string(forKey: "lf_custom_url") ?? "" {
        didSet { UserDefaults.standard.set(customBaseURL, forKey: "lf_custom_url") }
    }

    // MARK: - API keys (Keychain, per provider)

    func apiKey(for provider: LLMProvider) -> String {
        if loadedAPIKeys.contains(provider) {
            return cachedAPIKeys[provider] ?? ""
        }

        // Check new per-provider key first
        if let key = Keychain.load(forKey: provider.keychainKey), !key.isEmpty {
            loadedAPIKeys.insert(provider)
            cachedAPIKeys[provider] = key
            return key
        }
        // Groq: also check the legacy "groq_api_key" set by the old single-key system
        if provider == .groq, let legacy = Keychain.load(forKey: "groq_api_key"), !legacy.isEmpty {
            // Promote to new key on first read
            Keychain.save(legacy, forKey: provider.keychainKey)
            loadedAPIKeys.insert(provider)
            cachedAPIKeys[provider] = legacy
            return legacy
        }

        loadedAPIKeys.insert(provider)
        cachedAPIKeys[provider] = ""
        return ""
    }

    func setApiKey(_ key: String, for provider: LLMProvider) {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        loadedAPIKeys.insert(provider)
        cachedAPIKeys[provider] = normalized

        if normalized.isEmpty { Keychain.delete(forKey: provider.keychainKey) }
        else                  { Keychain.save(normalized, forKey: provider.keychainKey) }
    }

    func apiKey(for provider: TranscriptionProvider) -> String {
        if let credentialProvider = provider.credentialProvider {
            return apiKey(for: credentialProvider)
        }
        if loadedElevenLabsKey { return cachedElevenLabsKey }

        loadedElevenLabsKey = true
        cachedElevenLabsKey = Keychain.load(forKey: provider.keychainKey) ?? ""
        return cachedElevenLabsKey
    }

    func setApiKey(_ key: String, for provider: TranscriptionProvider) {
        if let credentialProvider = provider.credentialProvider {
            setApiKey(key, for: credentialProvider)
            return
        }

        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        loadedElevenLabsKey = true
        cachedElevenLabsKey = normalized
        if normalized.isEmpty { Keychain.delete(forKey: provider.keychainKey) }
        else                  { Keychain.save(normalized, forKey: provider.keychainKey) }
    }

    // MARK: - Resolved configs

    func config(for usage: LLMUsage) -> LLMConfig {
        let provider = usage == .dictation ? dictationProvider : agentProvider
        let modelId  = usage == .dictation ? dictationModel    : agentModel
        let key      = apiKey(for: provider)
        let baseURL  = provider == .custom ? customBaseURL : provider.defaultBaseURL
        let spec     = provider.presetModels.first { $0.id == modelId }
        return LLMConfig(provider: provider, baseURL: baseURL, apiKey: key, model: modelId, modelSpec: spec)
    }

    var transcriptionConfig: TranscriptionConfig {
        TranscriptionConfig(
            provider: transcriptionProvider,
            apiKey: apiKey(for: transcriptionProvider),
            model: transcriptionModel
        )
    }

    // MARK: - Migration: import legacy Groq key

    func migrateGroqKey(_ key: String) {
        guard !key.isEmpty, apiKey(for: LLMProvider.groq).isEmpty else { return }
        setApiKey(key, for: LLMProvider.groq)
    }

    // MARK: - Convenience

    var hasValidDictationConfig: Bool {
        let c = config(for: .dictation)
        return !c.apiKey.isEmpty && !c.model.isEmpty && !c.baseURL.isEmpty
    }

    var hasValidAgentConfig: Bool {
        let c = config(for: .agent)
        return !c.apiKey.isEmpty && !c.model.isEmpty && !c.baseURL.isEmpty
    }
}
