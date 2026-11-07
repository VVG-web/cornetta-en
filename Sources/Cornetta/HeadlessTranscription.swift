import CornettaCore
import Foundation

/// `Cornetta --transcribe <file.m4a> [--tracks <cartella con tu.m4a e altri.m4a>]`:
/// trascrive senza interfaccia usando il servizio HTTP configurato e stampa il Markdown.
enum HeadlessTranscription {
    static func run(file: String, tracks: String?) {
        let config = TranscriptionService.config
        guard config.isConfigured else {
            print("Il servizio di trascrizione non è configurato. Usa Impostazioni trascrizione.")
            exit(2)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var code: Int32 = 0
        Task.detached {
            do {
                let url = URL(fileURLWithPath: file)
                let segments: [Transcript.Segment]
                if let tracks {
                    let dir = URL(fileURLWithPath: tracks, isDirectory: true)
                    let theirs = try await TranscriptionService.transcribe(
                        url: dir.appendingPathComponent(RecordingFinalizer.othersTrack),
                        speaker: .others, config: config)
                    let mine = try await TranscriptionService.transcribe(
                        url: dir.appendingPathComponent(RecordingFinalizer.meTrack),
                        speaker: .me, config: config)
                    print("frasi Tu: \(mine.count), frasi Altri: \(theirs.count)")
                    segments = TranscriptMerger.merge(me: mine, others: theirs)
                } else {
                    segments = try await TranscriptionService.transcribe(url: url, speaker: .mixed, config: config)
                }
                let transcript = Transcript(
                    recording: url.lastPathComponent, engine: TranscriptionService.engineName,
                    language: config.effectiveLanguage.isEmpty ? "auto" : config.effectiveLanguage,
                    segments: segments)
                print(TranscriptFormatter.markdown(
                    transcript, title: url.deletingPathExtension().lastPathComponent, duration: nil))
            } catch {
                print("Errore: \(error.localizedDescription)")
                code = 1
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(code)
    }
}
