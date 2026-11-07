import Foundation

/// Configurazione del servizio HTTP di trascrizione, compatibile con l'API OpenAI Whisper
/// (`POST /v1/audio/transcriptions` con multipart/form-data).
public struct TranscriptionConfig: Equatable, Sendable {
    public var scheme: String
    public var host: String
    public var port: String
    public var path: String
    public var model: String
    public var language: String

    public init(scheme: String = TranscriptionPreferences.defaultScheme,
                host: String = TranscriptionPreferences.defaultHost,
                port: String = TranscriptionPreferences.defaultPort,
                path: String = TranscriptionPreferences.defaultPath,
                model: String = TranscriptionPreferences.defaultModel,
                language: String = TranscriptionPreferences.defaultLanguage) {
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path
        self.model = model
        self.language = language
    }

    public var endpointURL: URL? {
        let scheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        var host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        guard !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !host.contains(where: { "/?#@".contains($0) }) else { return nil }
        guard let portNumber = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65535).contains(portNumber) else { return nil }
        var path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty { path = TranscriptionPreferences.defaultPath }
        if !path.hasPrefix("/") { path = "/" + path }
        guard path.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !path.contains(where: { "?#".contains($0) }) else { return nil }
        let displayHost = host.contains(":") ? "[\(host)]" : host
        return URL(string: "\(scheme)://\(displayHost):\(portNumber)\(path)")
    }

    public var isConfigured: Bool { endpointURL != nil }

    public var endpointDescription: String {
        endpointURL?.absoluteString ?? "\(scheme)://\(host):\(port)\(path)"
    }

    public var effectiveLanguage: String {
        language.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var effectiveModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func stored(in defaults: UserDefaults = .standard) -> TranscriptionConfig {
        TranscriptionConfig(
            scheme: defaults.string(forKey: TranscriptionPreferences.schemeKey)
                ?? TranscriptionPreferences.defaultScheme,
            host: defaults.string(forKey: TranscriptionPreferences.hostKey) ?? TranscriptionPreferences.defaultHost,
            port: defaults.string(forKey: TranscriptionPreferences.portKey) ?? TranscriptionPreferences.defaultPort,
            path: defaults.string(forKey: TranscriptionPreferences.pathKey) ?? TranscriptionPreferences.defaultPath,
            model: defaults.string(forKey: TranscriptionPreferences.modelKey) ?? TranscriptionPreferences.defaultModel,
            language: defaults.string(forKey: TranscriptionPreferences.languageKey)
                ?? TranscriptionPreferences.defaultLanguage
        )
    }
}

public enum TranscriptionPreferences {
    public static let schemeKey = "transcriptionScheme"
    public static let hostKey = "transcriptionHost"
    public static let portKey = "transcriptionPort"
    public static let pathKey = "transcriptionPath"
    public static let modelKey = "transcriptionModel"
    public static let languageKey = "transcriptionLanguage"
    public static let autoTranscribeKey = "autoTranscribe"
    public static let migrationKey = "transcriptionHTTPMigrated"

    public static let defaultScheme = "http"
    public static let defaultHost = "127.0.0.1"
    public static let defaultPort = "8080"
    public static let defaultPath = "/v1/audio/transcriptions"
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
