import Foundation

/// Configurazione del servizio HTTP di trascrizione, compatibile con l'API OpenAI Whisper.
/// `baseURL` è l'indirizzo base, per esempio `https://api.example.com/v1`: Cornetta aggiunge
/// `/audio/transcriptions` quando costruisce l'endpoint.
public struct TranscriptionConfig: Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public var language: String

    public init(baseURL: String = TranscriptionPreferences.defaultBaseURL,
                model: String = TranscriptionPreferences.defaultModel,
                language: String = TranscriptionPreferences.defaultLanguage) {
        self.baseURL = baseURL
        self.model = model
        self.language = language
    }

    public var endpointURL: URL? {
        guard var components = baseComponents else { return nil }
        var path = components.path
        if path.isEmpty || path == "/" {
            path = ""
        }
        if !path.hasSuffix("/audio/transcriptions") {
            path += "/audio/transcriptions"
        }
        components.path = path
        return components.url
    }

    /// Endpoint OpenAI-compatible per l'elenco dei modelli, se il servizio lo espone.
    public var modelsURL: URL? {
        guard var components = baseComponents else { return nil }
        var path = components.path
        if path.hasSuffix("/audio/transcriptions") {
            path.removeLast("/audio/transcriptions".count)
        }
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path + "/models"
        return components.url
    }

    private var baseComponents: URLComponents? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        if let port = components.port, !(1...65535).contains(port) { return nil }
        components.scheme = scheme
        return components
    }

    public var isConfigured: Bool { endpointURL != nil }

    public var endpointDescription: String {
        endpointURL?.absoluteString ?? baseURL
    }

    public var effectiveLanguage: String {
        language.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var effectiveModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func stored(in defaults: UserDefaults = .standard) -> TranscriptionConfig {
        if let baseURL = defaults.string(forKey: TranscriptionPreferences.baseURLKey) {
            return TranscriptionConfig(
                baseURL: baseURL,
                model: defaults.string(forKey: TranscriptionPreferences.modelKey)
                    ?? TranscriptionPreferences.defaultModel,
                language: defaults.string(forKey: TranscriptionPreferences.languageKey)
                    ?? TranscriptionPreferences.defaultLanguage)
        }
        return migrated(from: defaults)
    }

    /// Le versioni 0.8.0 e precedenti salvavano schema, host, porta e percorso separati.
    private static func migrated(from defaults: UserDefaults) -> TranscriptionConfig {
        let scheme = defaults.string(forKey: TranscriptionPreferences.schemeKey)
            ?? "http"
        let host = defaults.string(forKey: TranscriptionPreferences.hostKey)
            ?? "127.0.0.1"
        let port = defaults.string(forKey: TranscriptionPreferences.portKey)
            ?? "8080"
        var path = defaults.string(forKey: TranscriptionPreferences.pathKey)
            ?? "/v1/audio/transcriptions"
        if path.hasSuffix("/audio/transcriptions") {
            path.removeLast("/audio/transcriptions".count)
        }
        while path.hasSuffix("/") { path.removeLast() }
        let displayHost = host.contains(":") ? "[\(host)]" : host
        let portPart = port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : ":\(port)"
        let base = "\(scheme)://\(displayHost)\(portPart)\(path)"
        return TranscriptionConfig(
            baseURL: base,
            model: defaults.string(forKey: TranscriptionPreferences.modelKey)
                ?? TranscriptionPreferences.defaultModel,
            language: defaults.string(forKey: TranscriptionPreferences.languageKey)
                ?? TranscriptionPreferences.defaultLanguage)
    }

}

public enum TranscriptionPreferences {
    public static let baseURLKey = "transcriptionBaseURL"
    public static let modelKey = "transcriptionModel"
    public static let languageKey = "transcriptionLanguage"
    public static let autoTranscribeKey = "autoTranscribe"
    public static let migrationKey = "transcriptionHTTPMigrated"

    /// Chiavi separate usate fino alla 0.8.1: servono solo a migrare la configurazione.
    static let schemeKey = "transcriptionScheme"
    static let hostKey = "transcriptionHost"
    static let portKey = "transcriptionPort"
    static let pathKey = "transcriptionPath"

    public static let defaultBaseURL = "http://127.0.0.1:8080/v1"
    public static let defaultModel = "whisper-1"
    public static let defaultLanguage = ""

    /// La trascrizione automatica della versione Apple non è un consenso alla trascrizione via rete:
    /// dopo l'aggiornamento va riattivata esplicitamente. La migrazione avviene una volta sola.
    public static func migrateIfNeeded(in defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        defaults.set(false, forKey: autoTranscribeKey)
        defaults.set(true, forKey: migrationKey)
    }
}

/// Elenco dei modelli restituito da `GET <baseURL>/models`.
public enum TranscriptionModelList {
    public static func ids(from data: Data) -> [String]? {
        struct Response: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]?
            let models: [Model]?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return (response.data ?? response.models)?.map(\.id)
    }
}
