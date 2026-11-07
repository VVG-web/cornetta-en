import Foundation

/// Languages supported by the Cornetta interface.
public enum AppLanguage: String, CaseIterable, Sendable {
    case italian = "it"
    case english = "en"

    public static let storageKey = "appLanguage"

    public var locale: Locale { Locale(identifier: rawValue) }

    public var nameKey: L10nKey {
        switch self {
        case .italian: return .menuLanguageItalian
        case .english: return .menuLanguageEnglish
        }
    }

    /// Reads the saved choice. Without one, English is the default for every installation;
    /// the result is saved immediately so a later system change does not alter it.
    public static func initial(defaults: UserDefaults = .standard) -> AppLanguage {
        if let raw = defaults.string(forKey: storageKey), let saved = AppLanguage(rawValue: raw) {
            return saved
        }
        defaults.set(AppLanguage.english.rawValue, forKey: storageKey)
        return .english
    }
}
