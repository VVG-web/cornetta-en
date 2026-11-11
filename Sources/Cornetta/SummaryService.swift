import CornettaCore
import Foundation

enum SummaryServiceError: LocalizedError {
    case notConfigured
    case noModel
    case noTranscript
    case http(status: Int, body: String)
    case invalidResponse
    case emptySummary

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Il provider di riassunto non è configurato."
        case .noModel:
            return "Scegli un modello per il riassunto."
        case .noTranscript:
            return "La registrazione non ha ancora una trascrizione."
        case .http(let status, let body):
            return "Il provider ha risposto HTTP \(status): \(body)"
        case .invalidResponse:
            return "Il provider ha restituito una risposta non riconosciuta."
        case .emptySummary:
            return "Il provider ha restituito un riassunto vuoto."
        }
    }
}

/// OpenAI-compatible chat-completions client. It only runs when the user presses
/// Generate, and it sends the transcript plus meeting metadata to one provider.
enum SummaryService {
    static func summarize(provider: SummaryProvider, model: String,
                          prompt: SummaryPrompt, meeting: MeetingInfo,
                          transcript: Transcript, language: AppLanguage,
                          apiKey: String) async throws -> String {
        let config = provider.config
        guard config.isConfigured else { throw SummaryServiceError.notConfigured }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw SummaryServiceError.noModel }
        guard !transcript.segments.isEmpty else { throw SummaryServiceError.noTranscript }
        guard let url = config.chatCompletionsURL else { throw SummaryServiceError.notConfigured }

        let body = ChatRequest(
            model: model,
            messages: [Message(role: "user",
                               content: prompt.rendered(meeting: meeting,
                                                        transcript: transcript.plainText(language: language),
                                                        language: language))],
            temperature: 0.2)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Cornetta/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if let authorization = TranscriptionAuthorization.header(for: apiKey) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 900
        configuration.timeoutIntervalForResource = 960
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SummaryServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw SummaryServiceError.http(status: http.statusCode, body: body)
        }
        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let text = decoded.choices.first?.message.content?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw SummaryServiceError.emptySummary
        }
        return text
    }

    static func availableModels(provider: SummaryProvider, apiKey: String) async -> [String]? {
        guard let url = provider.config.modelsURL else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Cornetta/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if let authorization = TranscriptionAuthorization.header(for: apiKey) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        guard let (data, response) = try? await URLSession(configuration: configuration).data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        return TranscriptionModelList.ids(from: data)
    }

    static func check(provider: SummaryProvider, apiKey: String) async -> ProviderCheckResult {
        let config = TranscriptionConfig(baseURL: provider.baseURL, model: provider.model)
        return await ProviderCheck.run(config: config, apiKey: apiKey)
    }

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: ResponseMessage
        }

        struct ResponseMessage: Decodable {
            let content: String?
        }
    }
}
