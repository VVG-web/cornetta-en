import AVFoundation
import CornettaCore
import Foundation

enum TranscriptionServiceError: LocalizedError {
    case notConfigured
    case http(status: Int, body: String)
    case invalidResponse
    case fileUnreadable(URL)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Il servizio di trascrizione non è configurato."
        case .http(let status, let body):
            return "Il servizio di trascrizione ha risposto HTTP \(status): \(body)"
        case .invalidResponse:
            return "Il servizio di trascrizione ha restituito una risposta non riconosciuta."
        case .fileUnreadable(let url):
            return "Non riesco a leggere l'audio da trascrivere: \(url.lastPathComponent)"
        }
    }
}

/// Client HTTP per servizi compatibili con l'API OpenAI Whisper:
/// `POST /v1/audio/transcriptions` con multipart/form-data.
enum TranscriptionService {
    static let engineName = "Whisper HTTP"

    static var config: TranscriptionConfig { TranscriptionConfig.stored() }
    static var isConfigured: Bool { config.isConfigured }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 900
        return URLSession(configuration: configuration)
    }()

    static func transcribe(url: URL, speaker: Transcript.Speaker, config: TranscriptionConfig,
                           progress: @escaping (Double) -> Void = { _ in }) async throws -> [Transcript.Segment] {
        guard let endpoint = config.endpointURL else { throw TranscriptionServiceError.notConfigured }
        let duration = audioDuration(url)
        let apiKey = TranscriptionCredential.load()
        progress(0.05)
        let data: Data
        do {
            data = try await upload(url: url, endpoint: endpoint, config: config, apiKey: apiKey,
                                    responseFormat: "verbose_json")
        } catch TranscriptionServiceError.http(let status, _) where [400, 415, 422].contains(status) {
            // Alcuni server Whisper accettano solo il formato JSON semplice.
            Diagnostics.log("Trascrizione: il servizio rifiuta verbose_json (\(status)), riprovo con json")
            data = try await upload(url: url, endpoint: endpoint, config: config, apiKey: apiKey,
                                    responseFormat: "json")
        }
        progress(0.95)
        let segments = parse(data, speaker: speaker, duration: duration)
        progress(1)
        return segments
    }

    private static func upload(url: URL, endpoint: URL, config: TranscriptionConfig, apiKey: String,
                               responseFormat: String) async throws -> Data {
        guard let audio = try? Data(contentsOf: url, options: .mappedIfSafe), !audio.isEmpty else {
            throw TranscriptionServiceError.fileUnreadable(url)
        }
        let boundary = "Cornetta-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n")
        let filename = safeFilename(url.lastPathComponent)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType(for: url))\r\n\r\n")
        body.append(audio)
        body.append("\r\n")
        if !config.effectiveModel.isEmpty {
            body.append(field("model", config.effectiveModel, boundary: boundary))
        }
        if !config.effectiveLanguage.isEmpty {
            body.append(field("language", config.effectiveLanguage, boundary: boundary))
        }
        body.append(field("response_format", responseFormat, boundary: boundary))
        body.append("--\(boundary)--\r\n")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Cornetta/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if let authorization = TranscriptionAuthorization.header(for: apiKey) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else { throw TranscriptionServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw TranscriptionServiceError.http(status: http.statusCode, body: body)
        }
        return data
    }

    private static func field(_ name: String, _ value: String, boundary: String) -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        data.append(value)
        data.append("\r\n")
        return data
    }

    private static func parse(_ data: Data, speaker: Transcript.Speaker, duration: Double) -> [Transcript.Segment] {
        if let response = try? JSONDecoder().decode(WhisperResponse.self, from: data) {
            if let rawSegments = response.segments, !rawSegments.isEmpty {
                let segments = rawSegments.compactMap { segment -> Transcript.Segment? in
                    let text = (segment.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    let start = max(0, segment.start ?? 0)
                    let end = max(start, segment.end ?? duration)
                    return Transcript.Segment(speaker: speaker, start: start, end: end, text: text)
                }
                if !segments.isEmpty { return segments }
            }
            let text = (response.text ?? response.result ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return [Transcript.Segment(speaker: speaker, start: 0, end: max(0, duration), text: text)]
            }
        }
        if let plain = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plain.isEmpty, !plain.hasPrefix("{") {
            return [Transcript.Segment(speaker: speaker, start: 0, end: max(0, duration), text: plain)]
        }
        return []
    }

    private static func audioDuration(_ url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "m4a", "mp4": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "caf": return "audio/x-caf"
        case "flac": return "audio/flac"
        case "ogg", "opus": return "audio/ogg"
        default: return "application/octet-stream"
        }
    }

    private static func safeFilename(_ name: String) -> String {
        name.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }

    private struct WhisperResponse: Decodable {
        let text: String?
        let result: String?
        let segments: [WhisperSegment]?
    }

    private struct WhisperSegment: Decodable {
        let start: Double?
        let end: Double?
        let text: String?
    }
}

extension Notification.Name {
    static let cornettaTranscriptionSettingsChanged = Notification.Name("CornettaTranscriptionSettingsChanged")
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
