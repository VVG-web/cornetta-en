import CornettaCore
import Foundation

/// Esito della verifica del servizio: nessun audio viene inviato, solo una richiesta all'elenco modelli.
enum ProviderCheckResult: Equatable {
    case modelAvailable(String)
    case modelNotListed(String)
    case reachable
    case unauthorized(Int)
    case noModelList(Int)
    case http(Int)
    case invalidResponse
    case invalidConfiguration
    case network
}

enum ProviderCheck {
    static func run(config: TranscriptionConfig, apiKey: String) async -> ProviderCheckResult {
        guard config.isConfigured, let url = config.modelsURL else { return .invalidConfiguration }
        return await run(url: url, model: config.effectiveModel, apiKey: apiKey)
    }

    static func run(url: URL, model: String, apiKey: String) async -> ProviderCheckResult {
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
        do {
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let http = response as? HTTPURLResponse else { return .invalidResponse }
            if http.statusCode == 401 || http.statusCode == 403 { return .unauthorized(http.statusCode) }
            if http.statusCode == 404 || http.statusCode == 405 || http.statusCode == 501 {
                return .noModelList(http.statusCode)
            }
            guard (200..<300).contains(http.statusCode) else { return .http(http.statusCode) }
            guard let ids = TranscriptionModelList.ids(from: data) else { return .invalidResponse }
            if model.isEmpty { return .reachable }
            return ids.contains(model) ? .modelAvailable(model) : .modelNotListed(model)
        } catch {
            return .network
        }
    }
}
