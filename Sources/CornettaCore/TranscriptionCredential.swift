import Foundation
import Security

/// Chiave API facoltativa per il servizio di trascrizione. Non finisce in UserDefaults:
/// vive nel Portachiavi e viene letta solo quando parte una richiesta.
public enum TranscriptionCredential {
    private static let service = "com.stellakamikaze.cornetta.transcription"
    public static let legacyAccount = "api-key"

    public static func account(for id: UUID) -> String {
        "api-key.\(id.uuidString)"
    }

    public static func load(account: String = legacyAccount) -> String {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query(account: account, returningData: true) as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return "" }
        return key
    }

    public static func save(_ key: String, account: String = legacyAccount) throws {
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
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public static func delete(account: String = legacyAccount) {
        SecItemDelete(query(account: account) as CFDictionary)
    }

    private static func query(account: String, returningData: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }

    public struct KeychainError: LocalizedError {
        public let status: OSStatus

        public var errorDescription: String? {
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        }
    }
}

/// Intestazione HTTP per un servizio che richiede una chiave. Vuota significa nessuna chiave.
public enum TranscriptionAuthorization {
    public static func header(for key: String) -> String? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : "Bearer \(key)"
    }
}
