import CornettaCore
import Foundation

struct TranscriptionOutput {
    let segments: [Transcript.Segment]
    let engine: String
    let language: String
}

enum TranscriptionRunnerError: LocalizedError {
    case appleUnavailable
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .appleUnavailable:
            return "Apple Speech requires macOS 26 or later."
        case .notConfigured:
            return "The selected transcription provider is not configured."
        }
    }
}

/// Sceglie il motore in base al provider selezionato e tiene la chiave API fuori dai modelli.
enum TranscriptionRunner {
    static var selected: TranscriptionProvider {
        TranscriptionProviderCatalog.selected()
    }

    static var isAvailable: Bool {
        isAvailable(selected)
    }

    static func isAvailable(_ provider: TranscriptionProvider) -> Bool {
        provider.isHTTP ? provider.config.isConfigured : SpeechEngine.isAvailable
    }

    static func transcribe(url: URL, speaker: Transcript.Speaker,
                           provider: TranscriptionProvider,
                           progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> TranscriptionOutput {
        if provider.kind == .apple {
            guard #available(macOS 26.0, *) else { throw TranscriptionRunnerError.appleUnavailable }
            let locale = await SpeechEngine.locale()
            try await SpeechEngine.prepare(locale: locale)
            let segments = try await SpeechEngine.transcribe(url, speaker: speaker, locale: locale, progress: progress)
            return TranscriptionOutput(segments: segments, engine: SpeechEngine.engineName,
                                       language: locale.identifier)
        }
        guard provider.config.isConfigured else { throw TranscriptionRunnerError.notConfigured }
        let key = TranscriptionProviderCatalog.apiKey(for: provider)
        let segments = try await TranscriptionService.transcribe(url: url, speaker: speaker,
                                                                 config: provider.config, apiKey: key,
                                                                 progress: progress)
        return TranscriptionOutput(segments: segments, engine: TranscriptionService.engineName,
                                   language: provider.config.effectiveLanguage.isEmpty
                                       ? "auto" : provider.config.effectiveLanguage)
    }
}
