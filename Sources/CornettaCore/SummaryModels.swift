import Foundation

/// OpenAI-compatible chat-completions endpoint for local or remote LLM providers.
public struct SummaryConfig: Equatable, Sendable {
    public var baseURL: String
    public var model: String

    public init(baseURL: String = SummaryPreferences.defaultBaseURL,
                model: String = SummaryPreferences.defaultModel) {
        self.baseURL = baseURL
        self.model = model
    }

    public var chatCompletionsURL: URL? {
        guard var components = baseComponents else { return nil }
        var path = components.path
        if path.hasSuffix("/chat/completions") {
            // Already a complete endpoint.
        } else {
            while path.hasSuffix("/") { path.removeLast() }
            path += "/chat/completions"
        }
        components.path = path
        return components.url
    }

    public var modelsURL: URL? {
        guard var components = baseComponents else { return nil }
        var path = components.path
        if path.hasSuffix("/chat/completions") {
            path.removeLast("/chat/completions".count)
        }
        while path.hasSuffix("/") { path.removeLast() }
        path += "/models"
        components.path = path
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

    public var isConfigured: Bool { chatCompletionsURL != nil }
    public var effectiveModel: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var endpointDescription: String { chatCompletionsURL?.absoluteString ?? baseURL }
}

public enum SummaryPreferences {
    public static let providersKey = "summaryProviders.v1"
    public static let defaultProviderKey = "summaryDefaultProviderID"
    public static let promptsKey = "summaryPrompts.v1"
    public static let defaultBaseURL = "http://127.0.0.1:8080/v1"
    public static let defaultModel = ""
    public static let defaultTimeout = 600
}

public struct SummaryProvider: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var baseURL: String
    public var model: String

    public init(id: UUID = UUID(), name: String, baseURL: String = SummaryPreferences.defaultBaseURL,
                model: String = SummaryPreferences.defaultModel) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
    }

    public var config: SummaryConfig { SummaryConfig(baseURL: baseURL, model: model) }
}

public enum SummaryProviderCatalog {
    public static func all(in defaults: UserDefaults = .standard) -> [SummaryProvider] {
        guard let data = defaults.data(forKey: SummaryPreferences.providersKey),
              let providers = try? JSONDecoder().decode([SummaryProvider].self, from: data) else {
            return []
        }
        return providers
    }

    public static func defaultProvider(in defaults: UserDefaults = .standard) -> SummaryProvider? {
        let providers = all(in: defaults)
        guard !providers.isEmpty else { return nil }
        if let raw = defaults.string(forKey: SummaryPreferences.defaultProviderKey),
           let id = UUID(uuidString: raw),
           let provider = providers.first(where: { $0.id == id }) {
            return provider
        }
        return providers.first
    }

    public static func save(_ provider: SummaryProvider, apiKey: String?,
                            makeDefault: Bool, in defaults: UserDefaults = .standard) throws {
        var providers = all(in: defaults)
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
        if provider.config.isConfigured, let apiKey {
            try SummaryCredential.save(apiKey, account: SummaryCredential.account(for: provider.id))
        }
        defaults.set(try JSONEncoder().encode(providers), forKey: SummaryPreferences.providersKey)
        if makeDefault || defaultProvider(in: defaults) == nil {
            defaults.set(provider.id.uuidString, forKey: SummaryPreferences.defaultProviderKey)
        }
        if let current = defaultProvider(in: defaults), !providers.contains(where: { $0.id == current.id }) {
            defaults.set(providers.first?.id.uuidString, forKey: SummaryPreferences.defaultProviderKey)
        }
    }

    public static func setDefault(_ id: UUID, in defaults: UserDefaults = .standard) {
        guard all(in: defaults).contains(where: { $0.id == id }) else { return }
        defaults.set(id.uuidString, forKey: SummaryPreferences.defaultProviderKey)
    }

    public static func delete(_ provider: SummaryProvider, in defaults: UserDefaults = .standard) {
        var providers = all(in: defaults)
        providers.removeAll { $0.id == provider.id }
        defaults.set(try? JSONEncoder().encode(providers), forKey: SummaryPreferences.providersKey)
        SummaryCredential.delete(account: SummaryCredential.account(for: provider.id))
        if defaults.string(forKey: SummaryPreferences.defaultProviderKey) == provider.id.uuidString {
            defaults.set(providers.first?.id.uuidString, forKey: SummaryPreferences.defaultProviderKey)
        }
    }

    public static func apiKey(for provider: SummaryProvider) -> String {
        SummaryCredential.load(account: SummaryCredential.account(for: provider.id))
    }
}

public struct SummaryPrompt: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var body: String
    public var isDefault: Bool

    public init(id: UUID = UUID(), name: String, body: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.body = body
        self.isDefault = isDefault
    }
}

public extension SummaryPrompt {
    /// Replaces the documented variables and guarantees that the transcript is
    /// present even when a custom prompt forgot the placeholder.
    func rendered(meeting: MeetingInfo, transcript: String, language: AppLanguage) -> String {
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HH:mm"
        let languageName = language == .english ? "English" : "Italian"
        var rendered = body
            .replacingOccurrences(of: "{{topic}}", with: meeting.topic)
            .replacingOccurrences(of: "{{participants}}", with: meeting.participants)
            .replacingOccurrences(of: "{{date}}", with: date.string(from: meeting.startDate))
            .replacingOccurrences(of: "{{time}}", with: time.string(from: meeting.startDate))
            .replacingOccurrences(of: "{{notes}}", with: meeting.notes)
            .replacingOccurrences(of: "{{language}}", with: languageName)
            .replacingOccurrences(of: "{{transcript}}", with: transcript)
        if !body.contains("{{transcript}}") {
            rendered += "\n\n" + transcript
        }
        return rendered
    }
}

public enum SummaryPromptCatalog {
    public static func all(in defaults: UserDefaults = .standard,
                           language: AppLanguage = .initial()) -> [SummaryPrompt] {
        guard let data = defaults.data(forKey: SummaryPreferences.promptsKey),
              let prompts = try? JSONDecoder().decode([SummaryPrompt].self, from: data),
              !prompts.isEmpty else {
            let prompt = builtin(language: language)
            if let data = try? JSONEncoder().encode([prompt]) {
                defaults.set(data, forKey: SummaryPreferences.promptsKey)
            }
            return [prompt]
        }
        if let index = prompts.firstIndex(where: \.isDefault) {
            // A valid default already exists.
            return prompts.enumerated().map { offset, prompt in
                var prompt = prompt
                prompt.isDefault = offset == index
                return prompt
            }
        }
        var fixed = prompts
        fixed[0].isDefault = true
        if let data = try? JSONEncoder().encode(fixed) {
            defaults.set(data, forKey: SummaryPreferences.promptsKey)
        }
        return fixed
    }

    public static func defaultPrompt(in defaults: UserDefaults = .standard,
                                     language: AppLanguage = .initial()) -> SummaryPrompt? {
        let prompts = all(in: defaults, language: language)
        return prompts.first(where: \.isDefault) ?? prompts.first
    }

    public static func save(_ prompt: SummaryPrompt, in defaults: UserDefaults = .standard) {
        var prompts = all(in: defaults)
        if prompt.isDefault {
            for index in prompts.indices { prompts[index].isDefault = false }
        }
        if let index = prompts.firstIndex(where: { $0.id == prompt.id }) {
            prompts[index] = prompt
        } else {
            prompts.append(prompt)
        }
        if !prompts.contains(where: \.isDefault), !prompts.isEmpty {
            prompts[0].isDefault = true
        }
        defaults.set(try? JSONEncoder().encode(prompts), forKey: SummaryPreferences.promptsKey)
    }

    public static func delete(_ prompt: SummaryPrompt, in defaults: UserDefaults = .standard) {
        var prompts = all(in: defaults)
        prompts.removeAll { $0.id == prompt.id }
        if !prompts.isEmpty, !prompts.contains(where: \.isDefault) {
            prompts[0].isDefault = true
        }
        defaults.set(try? JSONEncoder().encode(prompts), forKey: SummaryPreferences.promptsKey)
    }

    public static func builtin(language: AppLanguage) -> SummaryPrompt {
        let english = language == .english
        return SummaryPrompt(
            name: english ? "Default summary" : "Riepilogo predefinito",
            body: english ? builtinEnglish : builtinItalian,
            isDefault: true)
    }

    private static let builtinEnglish = """
    You are a precise meeting summarizer. Use only the meeting information and the transcript.
    Meeting topic: {{topic}}
    Participants: {{participants}}
    Start: {{date}} {{time}}
    User notes: {{notes}}
    Transcript:
    {{transcript}}

    Write the summary in {{language}}. Include, when present:
    1. Overview
    2. Decisions
    3. Action items with owners and dates
    4. Open questions
    Do not invent facts or people.
    """

    private static let builtinItalian = """
    Sei un sintetizzatore preciso di riunioni. Usa solo le informazioni della riunione e la trascrizione.
    Tema: {{topic}}
    Partecipanti: {{participants}}
    Inizio: {{date}} {{time}}
    Note dell'utente: {{notes}}
    Trascrizione:
    {{transcript}}

    Scrivi il riepilogo in {{language}}. Includi, quando presenti:
    1. Panoramica
    2. Decisioni
    3. Azioni con responsabili e date
    4. Domande aperte
    Non inventare fatti o persone.
    """
}

public struct MeetingInfo: Codable, Equatable, Sendable {
    public var topic: String
    public var participants: String
    public var startDate: Date
    public var notes: String

    public init(topic: String = "", participants: String = "",
                startDate: Date = Date(), notes: String = "") {
        self.topic = topic
        self.participants = participants
        self.startDate = startDate
        self.notes = notes
    }
}

public struct SummaryRecord: Codable, Equatable, Sendable {
    public var recording: String
    public var title: String
    public var text: String
    public var providerID: UUID
    public var providerName: String
    public var model: String
    public var promptID: UUID
    public var promptName: String
    public var createdAt: Date
    public var language: String

    public init(recording: String, title: String, text: String,
                providerID: UUID, providerName: String, model: String,
                promptID: UUID, promptName: String, createdAt: Date = Date(),
                language: String) {
        self.recording = recording
        self.title = title
        self.text = text
        self.providerID = providerID
        self.providerName = providerName
        self.model = model
        self.promptID = promptID
        self.promptName = promptName
        self.createdAt = createdAt
        self.language = language
    }
}

public enum SummaryStore {
    public static let meetingsFolder = "Incontri"
    public static let summariesFolder = "Riassunti"

    public static func meetingURL(for recording: URL, support: URL) -> URL {
        support.appendingPathComponent(meetingsFolder, isDirectory: true)
            .appendingPathComponent(recording.deletingPathExtension().lastPathComponent + ".json")
    }

    public static func summaryURL(for recording: URL, support: URL) -> URL {
        support.appendingPathComponent(summariesFolder, isDirectory: true)
            .appendingPathComponent(recording.deletingPathExtension().lastPathComponent + ".json")
    }

    public static func summaryMarkdownURL(for recording: URL, support: URL) -> URL {
        summaryURL(for: recording, support: support).deletingPathExtension().appendingPathExtension("md")
    }

    public static func loadMeeting(for recording: URL, support: URL) -> MeetingInfo? {
        guard let data = try? Data(contentsOf: meetingURL(for: recording, support: support)) else { return nil }
        return try? decoder.decode(MeetingInfo.self, from: data)
    }

    public static func saveMeeting(_ info: MeetingInfo, for recording: URL, support: URL) throws {
        let url = meetingURL(for: recording, support: support)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try encoder.encode(info).write(to: url, options: .atomic)
    }

    public static func loadSummary(for recording: URL, support: URL) -> SummaryRecord? {
        guard let data = try? Data(contentsOf: summaryURL(for: recording, support: support)) else { return nil }
        return try? decoder.decode(SummaryRecord.self, from: data)
    }

    public static func saveSummary(_ record: SummaryRecord, for recording: URL, support: URL,
                                   markdown: String) throws {
        let url = summaryURL(for: recording, support: support)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try encoder.encode(record).write(to: url, options: .atomic)
        try markdown.write(to: summaryMarkdownURL(for: recording, support: support),
                           atomically: true, encoding: .utf8)
    }

    public static func delete(for recording: URL, support: URL) {
        try? FileManager.default.removeItem(at: meetingURL(for: recording, support: support))
        try? FileManager.default.removeItem(at: summaryURL(for: recording, support: support))
        try? FileManager.default.removeItem(at: summaryMarkdownURL(for: recording, support: support))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
