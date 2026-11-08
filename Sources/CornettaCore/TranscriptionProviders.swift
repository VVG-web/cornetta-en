import Foundation

/// Un motore di trascrizione selezionabile. Le chiavi API non fanno parte di questo valore:
/// vivono nel Portachiavi, per provider.
public struct TranscriptionProvider: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case apple
        case http
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var baseURL: String
    public var model: String
    public var language: String
    /// Il provider migrato dalla configurazione singola usa ancora l'account Keychain storico.
    public var usesLegacyKey: Bool

    public init(id: UUID = UUID(), name: String, kind: Kind,
                baseURL: String = "", model: String = "", language: String = "",
                usesLegacyKey: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.language = language
        self.usesLegacyKey = usesLegacyKey
    }

    public var config: TranscriptionConfig {
        TranscriptionConfig(baseURL: baseURL, model: model, language: language)
    }

    public var isHTTP: Bool { kind == .http }

    public var credentialAccount: String {
        usesLegacyKey ? TranscriptionCredential.legacyAccount
            : TranscriptionCredential.account(for: id)
    }
}

/// Elenco dei provider HTTP salvati e provider Apple fisso.
public enum TranscriptionProviderCatalog {
    public static let appleID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    static let legacyID = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
    static let localID = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!

    static let providersKey = "transcriptionProviders.v1"
    public static let selectedKey = "transcriptionSelectedProviderID"

    public static var apple: TranscriptionProvider {
        TranscriptionProvider(id: appleID, name: "Apple Speech", kind: .apple)
    }

    public static func all(in defaults: UserDefaults = .standard) -> [TranscriptionProvider] {
        [apple] + custom(in: defaults)
    }

    public static func custom(in defaults: UserDefaults = .standard) -> [TranscriptionProvider] {
        migrateIfNeeded(in: defaults)
        guard let data = defaults.data(forKey: providersKey),
              let list = try? JSONDecoder().decode([TranscriptionProvider].self, from: data) else {
            return []
        }
        return list
    }

    public static func selected(in defaults: UserDefaults = .standard) -> TranscriptionProvider {
        let providers = all(in: defaults)
        if let raw = defaults.string(forKey: selectedKey), let id = UUID(uuidString: raw),
           let provider = providers.first(where: { $0.id == id }) {
            return provider
        }
        return providers.first ?? apple
    }

    public static func selectedID(in defaults: UserDefaults = .standard) -> UUID {
        selected(in: defaults).id
    }

    public static func select(_ id: UUID, in defaults: UserDefaults = .standard) {
        guard all(in: defaults).contains(where: { $0.id == id }) else { return }
        defaults.set(id.uuidString, forKey: selectedKey)
    }

    /// `apiKey == nil` conserva la chiave esistente: serve quando l'utente modifica
    /// solo nome o URL del provider e il Portachiavi non è stato riletto.
    public static func save(_ provider: TranscriptionProvider, apiKey: String?,
                            select: Bool, in defaults: UserDefaults = .standard) throws {
        var list = custom(in: defaults)
        if let index = list.firstIndex(where: { $0.id == provider.id }) {
            list[index] = provider
        } else if provider.kind == .http {
            list.append(provider)
        } else {
            return
        }
        if provider.kind == .http, let apiKey {
            try TranscriptionCredential.save(apiKey, account: provider.credentialAccount)
        }
        defaults.set(try JSONEncoder().encode(list), forKey: providersKey)
        if select { defaults.set(provider.id.uuidString, forKey: selectedKey) }
    }

    public static func delete(_ provider: TranscriptionProvider, in defaults: UserDefaults = .standard) {
        var list = custom(in: defaults)
        list.removeAll { $0.id == provider.id }
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: providersKey) }
        TranscriptionCredential.delete(account: provider.credentialAccount)
        if defaults.string(forKey: selectedKey) == provider.id.uuidString {
            let next = list.first?.id ?? appleID
            defaults.set(next.uuidString, forKey: selectedKey)
        }
    }

    public static func apiKey(for provider: TranscriptionProvider) -> String {
        provider.isHTTP ? TranscriptionCredential.load(account: provider.credentialAccount) : ""
    }

    /// Converte la vecchia configurazione singola in un provider HTTP salvato.
    public static func migrateIfNeeded(in defaults: UserDefaults = .standard) {
        if defaults.data(forKey: providersKey) != nil {
            if defaults.string(forKey: selectedKey) == nil,
               let data = defaults.data(forKey: providersKey),
               let list = try? JSONDecoder().decode([TranscriptionProvider].self, from: data) {
                defaults.set((list.first?.id ?? appleID).uuidString, forKey: selectedKey)
            }
            return
        }
        let configured = defaults.object(forKey: TranscriptionPreferences.baseURLKey) != nil
            || defaults.object(forKey: TranscriptionPreferences.schemeKey) != nil
        let config = configured ? TranscriptionConfig.stored(in: defaults)
            : TranscriptionConfig(baseURL: TranscriptionPreferences.defaultBaseURL)
        let provider = TranscriptionProvider(
            id: configured ? legacyID : localID,
            name: configured
                ? L10n.text(.transcriptionSettingsProviderNameDefault,
                            language: AppLanguage.initial())
                : "Local Whisper",
            kind: .http,
            baseURL: config.baseURL,
            model: config.model,
            language: config.language,
            usesLegacyKey: configured)
        if let data = try? JSONEncoder().encode([provider]) {
            defaults.set(data, forKey: providersKey)
            defaults.set(provider.id.uuidString, forKey: selectedKey)
        }
        for legacy in [TranscriptionPreferences.baseURLKey, TranscriptionPreferences.modelKey,
                       TranscriptionPreferences.languageKey, TranscriptionPreferences.schemeKey,
                       TranscriptionPreferences.hostKey, TranscriptionPreferences.portKey,
                       TranscriptionPreferences.pathKey] {
            defaults.removeObject(forKey: legacy)
        }
    }
}
