import Foundation
import Security

/// 把 API 金鑰存在 Keychain，不要放在 UserDefaults
enum KeychainStore {
    private static let service = "com.example.voicenote"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

enum SettingsKey {
    static let claudeAPIKey = "claudeAPIKey"        // Keychain
    static let claudeModel = "claudeModel"
    static let summaryInstruction = "summaryInstruction"
    static let defaultLanguage = "defaultLanguage"
    static let autoProcess = "autoProcess"
    static let taiwaneseModelURL = "taiwaneseModelURL"
    static let summaryEngine = "summaryEngine"
}
