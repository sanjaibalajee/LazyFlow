import Foundation
import Security

enum MobileKeychainError: LocalizedError {
    case missingEntitlement
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingEntitlement:
            "This build is missing Keychain access. Re-sign LazyFlow with the Keychain Sharing capability enabled."
        case .unexpectedStatus(let status):
            "Keychain could not save this key (\(status))."
        }
    }
}

enum MobileKeychain {
    private static let service = "com.fanpit.LazyFlowMobile"
    static let groqKey = "groq_api_key"

    static func save(_ value: String, for key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: Data(value.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addQuery = query.merging(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess {
                removeSimulatorFallbackIfPresent(for: key)
                return
            }
            if try saveToSimulatorFallbackIfNeeded(value, for: key, status: addStatus) {
                return
            }
            throw error(for: addStatus)
        }
        if status == errSecSuccess {
            removeSimulatorFallbackIfPresent(for: key)
            return
        }
        if try saveToSimulatorFallbackIfNeeded(value, for: key, status: status) {
            return
        }
        throw error(for: status)
    }

    static func load(for key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return loadFromSimulatorFallbackIfPresent(for: key)
    }

    static func delete(for key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        try removeSimulatorFallback(for: key)
        guard status == errSecSuccess
                || status == errSecItemNotFound
                || isSimulatorMissingEntitlement(status) else {
            throw error(for: status)
        }
    }

    private static func error(for status: OSStatus) -> MobileKeychainError {
        status == errSecMissingEntitlement
            ? .missingEntitlement
            : .unexpectedStatus(status)
    }

    private static func isSimulatorMissingEntitlement(_ status: OSStatus) -> Bool {
#if targetEnvironment(simulator)
        status == errSecMissingEntitlement
#else
        false
#endif
    }

    private static func saveToSimulatorFallbackIfNeeded(
        _ value: String,
        for key: String,
        status: OSStatus
    ) throws -> Bool {
#if targetEnvironment(simulator)
        guard status == errSecMissingEntitlement else { return false }
        let fileURL = simulatorFallbackURL(for: key)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(
            to: fileURL,
            options: [.atomic, .completeFileProtection]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = fileURL
        try? mutableURL.setResourceValues(values)
        return true
#else
        return false
#endif
    }

    private static func loadFromSimulatorFallbackIfPresent(for key: String) -> String? {
#if targetEnvironment(simulator)
        guard let data = try? Data(contentsOf: simulatorFallbackURL(for: key)) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
#else
        return nil
#endif
    }

    private static func removeSimulatorFallbackIfPresent(for key: String) {
        try? removeSimulatorFallback(for: key)
    }

    private static func removeSimulatorFallback(for key: String) throws {
#if targetEnvironment(simulator)
        let fileURL = simulatorFallbackURL(for: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
#endif
    }

#if targetEnvironment(simulator)
    private static func simulatorFallbackURL(for key: String) -> URL {
        let filename = Data(key.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("LazyFlowMobile", isDirectory: true)
            .appendingPathComponent("SimulatorKeychain", isDirectory: true)
        return directory.appendingPathComponent(filename)
    }
#endif
}
