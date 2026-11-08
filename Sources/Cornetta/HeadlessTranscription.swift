import CornettaCore
import Foundation

/// `Cornetta --transcribe <file.m4a> [--tracks <cartella con tu.m4a e altri.m4a>]`:
/// trascrive senza interfaccia usando il provider selezionato e stampa il Markdown.
enum HeadlessTranscription {
    static func run(file: String, tracks: String?) {
        let provider = TranscriptionRunner.selected
        guard TranscriptionRunner.isAvailable(provider) else {
            print("Il provider di trascrizione selezionato non è disponibile.")
            exit(2)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var code: Int32 = 0
        Task.detached {
            do {
                let url = URL(fileURLWithPath: file)
                let output: TranscriptionOutput
                if let tracks {
                    let dir = URL(fileURLWithPath: tracks, isDirectory: true)
                    let theirs = try await TranscriptionRunner.transcribe(
                        url: dir.appendingPathComponent(RecordingFinalizer.othersTrack),
                        speaker: .others, provider: provider)
                    let mine = try await TranscriptionRunner.transcribe(
                        url: dir.appendingPathComponent(RecordingFinalizer.meTrack),
                        speaker: .me, provider: provider)
                    print("frasi Tu: \(mine.segments.count), frasi Altri: \(theirs.segments.count)")
                    output = TranscriptionOutput(
                        segments: TranscriptMerger.merge(me: mine.segments, others: theirs.segments),
                        engine: mine.engine, language: mine.language)
                } else {
                    output = try await TranscriptionRunner.transcribe(
                        url: url, speaker: .mixed, provider: provider)
                }
                let transcript = Transcript(recording: url.lastPathComponent,
                                            engine: output.engine, language: output.language,
                                            segments: output.segments)
                print(TranscriptFormatter.markdown(
                    transcript, title: url.deletingPathExtension().lastPathComponent, duration: nil,
                    language: AppLanguage.initial()))
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
