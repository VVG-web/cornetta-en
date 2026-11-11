import Foundation
import Security

/// API keys for summary providers. Stored separately from transcription keys,
/// one generic-password item per provider UUID.
public enum SummaryCredential {
    private static let service = "com.stellakamikaze.cornetta.summary"

    public static func account(for id: UUID) -> String {
        "api-key.\(id.uuidString)"
    }

    public static func load(account: String) -> String {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query(account: account, returningData: true) as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return "" }
        return key
    }

    public static func save(_ key: String, account: String) throws {
        let data = Data(key.utf8)
        guard !data.isEmpty else {
            delete(account: account)
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query(account: account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account: account)
            attributes.forEach { item[$0.key] = $0.value }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else {
                throw TranscriptionCredential.KeychainError(status: added)
            }
        } else if status != errSecSuccess {
            throw TranscriptionCredential.KeychainError(status: status)
        }
    }

    public static func delete(account: String) {
        SecItemDelete(query(account: account) as CFDictionary)
    }

    private static func query(account: String, returningData: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if returningData { query[kSecReturnData as String] = true }
        return query
    }
}
