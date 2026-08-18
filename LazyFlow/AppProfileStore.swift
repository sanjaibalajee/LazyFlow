import Foundation
import Observation

@Observable
final class AppProfileStore {
    private(set) var profiles: [String: AppProfile] = [:]

    private let storageKey = "lazyflow_app_profiles"

    init() { load() }

    // MARK: - Read

    func profile(for bundleIdentifier: String) -> AppProfile? {
        profiles[bundleIdentifier]
    }

    // Returns existing profile or creates a sensible default, saves it, and returns it
    func profileOrDefault(for bundleIdentifier: String, displayName: String) -> AppProfile {
        if let existing = profiles[bundleIdentifier] { return existing }
        let tone    = AppProfile.defaultTone(for: bundleIdentifier)
        let profile = AppProfile(bundleIdentifier: bundleIdentifier, displayName: displayName, tone: tone)
        upsert(profile)
        return profile
    }

    // MARK: - Write

    // Set when a brand-new profile is created so the UI can auto-select it
    private(set) var lastCreatedBundleIdentifier: String?

    func upsert(_ profile: AppProfile) {
        let isNew = profiles[profile.bundleIdentifier] == nil
        profiles[profile.bundleIdentifier] = profile
        if isNew { lastCreatedBundleIdentifier = profile.bundleIdentifier }
        save()
    }

    func delete(bundleIdentifier: String) {
        profiles.removeValue(forKey: bundleIdentifier)
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(profiles)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("[LazyFlow] AppProfileStore.save failed: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            profiles = try JSONDecoder().decode([String: AppProfile].self, from: data)
        } catch {
            print("[LazyFlow] AppProfileStore.load failed (schema changed?): \(error)")
        }
    }
}
