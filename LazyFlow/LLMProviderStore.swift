import Foundation

@Observable
final class LLMProviderStore {
    static let shared = LLMProviderStore()

    // MARK: - Persisted dictation-cleanup selection

    var dictationProvider: LLMProvider = {
        LLMProvider(rawValue: UserDefaults.standard.string(forKey: "lf_dict_provider") ?? "") ?? .groq
    }() {
        didSet { UserDefaults.standard.set(dictationProvider.rawValue, forKey: "lf_dict_provider") }
    }

    var dictationModel: String = {
        let provider = LLMProvider(
            rawValue: UserDefaults.standard.string(forKey: "lf_dict_provider") ?? ""
        ) ?? .groq
        let stored = UserDefaults.standard.string(forKey: "lf_dict_model") ?? ""
        return provider.presetModels.contains(where: { $0.id == stored })
            ? stored
            : provider.defaultModel
    }() {
        didSet { UserDefaults.standard.set(dictationModel, forKey: "lf_dict_model") }
    }

    var customBaseURL: String = UserDefaults.standard.string(forKey: "lf_custom_url") ?? "" {
        didSet { UserDefaults.standard.set(customBaseURL, forKey: "lf_custom_url") }
    }

    // MARK: - API keys (Keychain, per provider)

    /// Bumped on every key mutation. Keys live in the Keychain, which `@Observable` cannot
    /// track, so views that care about key presence observe this counter instead — without
    /// it, saving a key never invalidated any view that wasn't already redrawing.
    private(set) var keyRevision = 0

    /// Keychain reads are syscalls and `apiKey(for:)` is called from view bodies, so results
    /// are memoised. Ignored by observation: the cache is filled during body evaluation and
    /// must not itself count as a change. `keyRevision` is what invalidates it.
    @ObservationIgnored private var keyCache: [LLMProvider: String] = [:]

    func apiKey(for provider: LLMProvider) -> String {
        if let cached = keyCache[provider] { return cached }
        let resolved = loadKey(for: provider)
        keyCache[provider] = resolved
        return resolved
    }

    /// Observation-friendly presence check for use in view bodies.
    func hasKey(for provider: LLMProvider) -> Bool {
        _ = keyRevision            // establishes the dependency for @Observable
        return !apiKey(for: provider).isEmpty
    }

    private func loadKey(for provider: LLMProvider) -> String {
        if let key = Keychain.load(forKey: provider.keychainKey), !key.isEmpty {
            return key
        }

        // Groq also checks the legacy single-key entry and promotes it on first read.
        if provider == .groq,
           let legacy = Keychain.load(forKey: "groq_api_key"),
           !legacy.isEmpty {
            Keychain.save(legacy, forKey: provider.keychainKey)
            return legacy
        }
        return ""
    }

    func setApiKey(_ key: String, for provider: LLMProvider) {
        if key.isEmpty {
            Keychain.delete(forKey: provider.keychainKey)
        } else {
            Keychain.save(key, forKey: provider.keychainKey)
        }
        keyCache[provider] = key
        keyRevision += 1
    }

    /// Removes a stored key. Also clears the legacy Groq entry, which would otherwise be
    /// promoted straight back on the next read.
    func clearApiKey(for provider: LLMProvider) {
        Keychain.delete(forKey: provider.keychainKey)
        if provider == .groq { Keychain.delete(forKey: "groq_api_key") }
        keyCache[provider] = ""
        keyRevision += 1
    }

    // MARK: - Resolved config

    var dictationConfig: LLMConfig {
        let baseURL = dictationProvider == .custom
            ? customBaseURL
            : dictationProvider.defaultBaseURL
        return LLMConfig(
            provider: dictationProvider,
            baseURL: baseURL,
            apiKey: apiKey(for: dictationProvider),
            model: dictationModel
        )
    }

    // MARK: - Migration: import legacy Groq key

    func migrateGroqKey(_ key: String) {
        guard !key.isEmpty, apiKey(for: .groq).isEmpty else { return }
        setApiKey(key, for: .groq)
    }
}
