import Foundation
import PectoKit
import Security

/// API keys live in the login keychain, never in UserDefaults — one entry
/// per provider. The Anthropic account name predates providers, so existing
/// keys are found without migration.
enum KeychainService {
    private static let service = "Pecto"

    private static func account(for provider: ProviderID) -> String {
        "\(provider.rawValue)-api-key"
    }

    private static func baseQuery(for provider: ProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
        ]
    }

    static func loadAPIKey(for provider: ProviderID) -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    static func saveAPIKey(_ key: String, for provider: ProviderID) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteAPIKey(for: provider)
            return
        }
        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(
            baseQuery(for: provider) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var add = baseQuery(for: provider)
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func deleteAPIKey(for provider: ProviderID) {
        SecItemDelete(baseQuery(for: provider) as CFDictionary)
    }
}
