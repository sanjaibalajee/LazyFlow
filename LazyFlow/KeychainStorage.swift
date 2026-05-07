import Foundation
import Security

enum Keychain {
    private static let service = "com.fanpit.LazyFlow"

    static func save(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        // Lookup query — no value, just the key identity
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        // Prefer update over delete+add: if update fails because the item doesn't exist yet,
        // fall back to add. This prevents credential loss if SecItemAdd were to fail.
        let updateStatus = SecItemUpdate(query as CFDictionary,
                                         [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                print("[LazyFlow] Keychain add failed for key '\(key)': OSStatus \(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            print("[LazyFlow] Keychain update failed for key '\(key)': OSStatus \(updateStatus)")
        }
    }

    static func load(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
