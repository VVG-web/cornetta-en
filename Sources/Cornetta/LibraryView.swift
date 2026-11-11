import AppKit
import AVFoundation
import CornettaCore
import SwiftUI

/// Finestra «Registrazioni»: elenco delle chiamate e trascrizione divisa per voce.
@MainActor
enum LibraryWindow {
    private static var window: NSWindow?
    private static var delegate: WindowDelegate?
    private static var spaceMonitor: Any?
    private static var languageObserver: NSObjectProtocol?

    static func show(select id: String? = nil) {
        Library.shared.reload()
        if let id { LibrarySelection.shared.selected = id }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = tr(.libraryWindow)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: LibraryView(library: .shared, selection: .shared)
                .localizedRoot())
            window.setFrameAutosaveName("CornettaLibrary")
            if window.frame.width < 700 { window.center() }
            let delegate = WindowDelegate()
            window.delegate = delegate
            self.delegate = delegate
            self.window = window
            if languageObserver == nil {
                languageObserver = NotificationCenter.default.addObserver(
                    forName: .cornettaLanguageChanged, object: nil, queue: .main
                ) { _ in
                    MainActor.assumeIsolated { LibraryWindow.window?.title = tr(.libraryWindow) }
                }
            }
            spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                playPause(on: event) ? nil : event
            }
        }
        // Finché la finestra è aperta Cornetta compare nel Dock e in ⌘-Tab, come un'app normale.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Spazio = ascolta o pausa, ma solo se non si sta scrivendo: una scorciatoia sul pulsante
    /// passerebbe prima del campo di ricerca e ruberebbe lo spazio fra le parole.
    private static func playPause(on event: NSEvent) -> Bool {
        guard event.keyCode == 49, !event.isARepeat,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              let window, event.window === window, !(window.firstResponder is NSText),
              let id = LibrarySelection.shared.selected,
              let recording = Library.shared.recordings.first(where: { $0.id == id }) else { return false }
        AudioPlayer.shared.toggle(recording)
        return true
    }

    final class WindowDelegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            MainActor.assumeIsolated {
                AudioPlayer.shared.stop()
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

@MainActor
final class LibrarySelection: ObservableObject {
    static let shared = LibrarySelection()
    @Published var selected: String?
}

/// Riproduce una registrazione e dice a che punto è, per evidenziare la battuta in corso.
@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()
    @Published private(set) var playingID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func play(_ recording: Library.Recording, from time: Double? = nil) {
        if playingID != recording.id {
            stop()
            player = try? AVAudioPlayer(contentsOf: recording.url)
            playingID = recording.id
        }
        guard let player else { return }
        if let time { player.currentTime = time }
        player.play()
        isPlaying = true
        currentTime = player.currentTime
        timer?.invalidate()
        // Gira solo mentre suona: in pausa o a fine file la finestra non si ridisegna più.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                if abs(player.currentTime - self.currentTime) >= 0.1 { self.currentTime = player.currentTime }
                if !player.isPlaying { self.pause() }
            }
        }
    }

    func toggle(_ recording: Library.Recording) {
        if isPlaying, playingID == recording.id { pause() } else { play(recording) }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        isPlaying = false
        playingID = nil
        currentTime = 0
    }
}

struct LibraryView: View {
    @ObservedObject var library: Library
    @ObservedObject var selection: LibrarySelection
    @State private var search = ""
    @Environment(\.appLanguage) private var language

    private var filtered: [Library.Recording] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return library.recordings }
        return library.recordings.filter { library.matches($0, query: query) }
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: $selection.selected) { recording in
                RecordingRow(recording: recording, library: library, query: search)
                    .tag(recording.id)
            }
            .searchable(text: $search, placement: .sidebar,
                        prompt: L10n.text(.librarySearch, language: language))
            .overlay {
                if library.recordings.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.text(.libraryEmptyTitle, language: language), systemImage: "phone")
                    } description: {
                        Text(L10n.text(.libraryEmptyMessage, language: language))
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.text(.libraryNoResultsTitle, language: language), systemImage: "magnifyingglass")
                    } description: {
                        Text(L10n.format(.libraryNoResultsMessage, language: language, search))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 380)
        } detail: {
            if let id = selection.selected, let recording = library.recordings.first(where: { $0.id == id }) {
                RecordingDetail(recording: recording, library: library, player: .shared)
                    .id(recording.id)
            } else {
                ContentUnavailableView {
                    Label(L10n.text(.librarySelectTitle, language: language), systemImage: "waveform")
                } description: {
                    Text(L10n.text(.librarySelectMessage, language: language))
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear {
            if selection.selected == nil { selection.selected = library.recordings.first?.id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cornettaTranscriptionSettingsChanged)) { _ in
            library.objectWillChange.send()
        }
    }
}

struct RecordingRow: View {
    let recording: Library.Recording
    @ObservedObject var library: Library
    let query: String
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Self.capitalizedFirst(primaryTitle))
                .font(.body.weight(.semibold))
                .lineLimit(1)
            if let secondaryDate {
                Text(Self.capitalizedFirst(secondaryDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(TranscriptFormatter.timestamp(recording.duration)).monospacedDigit()
                Text("·")
                StatusLabel(status: library.status(recording))
                if !recording.tags.isEmpty {
                    Image(systemName: "tag")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let snippet {
                Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else if !recording.tags.summary.isEmpty {
                Text(recording.tags.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM HHmm")
        return formatter.string(from: recording.date)
    }

    private var customTitle: String {
        recording.tags.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var primaryTitle: String {
        customTitle.isEmpty ? formattedDate : customTitle
    }

    private var secondaryDate: String? {
        customTitle.isEmpty ? nil : formattedDate
    }

    /// Con una ricerca attiva mostra la frase che contiene la parola cercata.
    private var snippet: String? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty, let transcript = library.transcripts[recording.id] else { return nil }
        return transcript.segments.first { $0.text.lowercased().contains(q) }.map {
            "\($0.displayLabel(language: language)): \($0.text)"
        }
    }
}

struct StatusLabel: View {
    let status: Library.Status
    @Environment(\.appLanguage) private var language

    var body: some View {
        switch status {
        case .done: Label(L10n.text(.libraryStatusTranscribed, language: language), systemImage: "text.bubble")
            .labelStyle(.titleOnly)
        case .queued: Text(L10n.text(.libraryQueuedTitle, language: language))
        case .transcribing(let p, _):
            Text(L10n.format(.libraryStatusTranscribing, language: language,
                             String(Int(p * 100)))).monospacedDigit()
        case .failed: Text(L10n.text(.libraryStatusFailed, language: language)).foregroundStyle(.red)
        case .notTranscribed:
            Text(L10n.text(TranscriptionRunner.isAvailable ? .libraryStatusNotTranscribed : .libraryStatusAudioOnly,
                           language: language))
        }
    }
}

struct RecordingDetail: View {
    private enum DetailMode: Hashable {
        case transcript
        case summary
    }

    private enum SummaryDisplayMode: Hashable {
        case reading
        case code
    }

    private struct TagEditorRequest: Identifiable {
        let id = UUID()
        let recording: Library.Recording
        let tags: RecordingTags
    }

    let recording: Library.Recording
    @ObservedObject var library: Library
    @ObservedObject var player: AudioPlayer
    @State private var confirmDelete = false
    @State private var tagEditor: TagEditorRequest?
    @State private var tagLoadFailed = false
    @State private var copied = false
    @State private var summaryCopied = false
    @State private var mode: DetailMode = .transcript
    @State private var summaryDisplay: SummaryDisplayMode = .reading
    @State private var showingSummarySheet = false
    @State private var showingMeetingEditor = false
    @Environment(\.appLanguage) private var language

    private var transcript: Transcript? { library.transcripts[recording.id] }
    private var summary: SummaryRecord? { library.summaries[recording.id] }
    private var meetingInfo: MeetingInfo { library.meetingInfo(for: recording) }
    private var playingThis: Bool { player.playingID == recording.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Picker(L10n.text(.summaryViewTranscript, language: language), selection: $mode) {
                Text(L10n.text(.summaryViewTranscript, language: language)).tag(DetailMode.transcript)
                Text(L10n.text(.summaryViewSummary, language: language)).tag(DetailMode.summary)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .confirmationDialog(L10n.text(.libraryDeleteTitle, language: language), isPresented: $confirmDelete) {
            Button(L10n.text(.libraryDeleteButton, language: language), role: .destructive) {
                library.delete(recording)
            }
            Button(L10n.text(.libraryDeleteCancel, language: language), role: .cancel) {}
        } message: {
            Text(L10n.text(.libraryDeleteMessage, language: language))
        }
        .sheet(item: $tagEditor) { request in
            RecordingTagsEditor(recording: request.recording, tags: request.tags) { tags in
                try await library.updateTags(request.recording, tags: tags)
            }
            .localizedRoot()
        }
        .sheet(isPresented: $showingSummarySheet) {
            SummarySheet(recording: recording, library: library) { _ in
                mode = .summary
            }
            .localizedRoot()
        }
        .sheet(isPresented: $showingMeetingEditor) {
            MeetingInfoEditor(recording: recording, library: library)
                .localizedRoot()
        }
        .alert(L10n.text(.libraryTagsLoadError, language: language), isPresented: $tagLoadFailed) {
            Button(L10n.text(.commonClose, language: language)) {}
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                player.toggle(recording)
            } label: {
                Image(systemName: playingThis && player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.text(playingThis && player.isPlaying ? .libraryPause : .libraryPlay, language: language))

            VStack(alignment: .leading, spacing: 2) {
                Text(library.title(for: recording)).font(.title3.weight(.semibold))
                Text(meta).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                if !recording.tags.summary.isEmpty {
                    Text(recording.tags.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if currentMarkdown != nil {
                Button(L10n.text(copied ? .libraryCopied : .libraryCopy, language: language)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(currentMarkdown ?? "", forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                Button(L10n.text(.libraryExport, language: language)) { export() }
            }
            Button {
                openTagEditor()
            } label: {
                Image(systemName: "tag")
            }
            .help(L10n.text(.libraryTagsEdit, language: language))
            Menu {
                Button(L10n.text(.commonShowInFinder, language: language)) {
                    NSWorkspace.shared.activateFileViewerSelecting([recording.url])
                }
                Button(L10n.text(.libraryTagsEdit, language: language)) { openTagEditor() }
                Button(L10n.text(.summaryViewEditInfo, language: language)) {
                    showingMeetingEditor = true
                }
                if transcript != nil {
                    Button(L10n.text(.summaryViewGenerate, language: language)) {
                        showingSummarySheet = true
                    }
                }
                if transcript != nil, TranscriptionRunner.isAvailable, !inProgress {
                    Button(L10n.text(.libraryTranscribeAgain, language: language)) { library.enqueue(recording.url) }
                }
                Divider()
                Button(L10n.text(.libraryDelete, language: language), role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    /// In coda o in trascrizione: «Trascrivi di nuovo» rifarebbe lo stesso lavoro.
    private var inProgress: Bool {
        switch library.status(recording) {
        case .queued, .transcribing: return true
        default: return false
        }
    }

    private var meta: String {
        var parts: [String] = []
        if !recording.tags.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(library.dateText(for: recording))
        }
        parts.append(L10n.format(.libraryDuration, language: language,
                                 TranscriptFormatter.timestamp(recording.duration)))
        if playingThis { parts.insert(TranscriptFormatter.timestamp(player.currentTime), at: 0) }
        if transcript != nil {
            parts.append(L10n.text(recording.hasTracks ? .libraryTracksSeparated : .libraryTracksMixed,
                                   language: language))
        }
        return parts.joined(separator: " · ")
    }

    private func openTagEditor() {
        Task {
            do {
                let tags = try await library.tags(for: recording)
                let current = library.recordings.first(where: { $0.id == recording.id }) ?? recording
                tagEditor = TagEditorRequest(recording: current, tags: tags)
            } catch {
                tagLoadFailed = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .transcript:
            transcriptContent
        case .summary:
            summaryContent
        }
    }

    @ViewBuilder
    private var transcriptContent: some View {
        switch library.status(recording) {
        case .done:
            if let transcript, !transcript.segments.isEmpty {
                TranscriptView(turns: library.turns(for: recording), recording: recording, player: player)
            } else {
                ContentUnavailableView {
                    Label(L10n.text(.libraryNoSpeechTitle, language: language), systemImage: "waveform.slash")
                } description: {
                    Text(L10n.text(.libraryNoSpeechMessage, language: language))
                }
            }
        case .transcribing(let progress, let message):
            VStack(spacing: 12) {
                ProgressView(value: progress).frame(maxWidth: 280)
                Text(message).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .queued:
            ContentUnavailableView {
                Label(L10n.text(.libraryQueuedTitle, language: language), systemImage: "clock")
            } description: {
                Text(L10n.text(.libraryQueuedMessage, language: language))
            }
        case .failed:
            let shown = L10n.text(.libraryTranscriptionFailed, language: language)
            ContentUnavailableView {
                Label(L10n.text(.libraryFailedTitle, language: language), systemImage: "exclamationmark.triangle")
            } description: {
                Text(shown)
            } actions: {
                HStack {
                    Button(L10n.text(.commonRetry, language: language)) { library.enqueue(recording.url) }
                    Button(L10n.text(.libraryTranscriptionSettings, language: language)) {
                        TranscriptionSettingsWindow.show()
                    }
                }
            }
        case .notTranscribed:
            if TranscriptionRunner.isAvailable {
                ContentUnavailableView {
                    Label(L10n.text(.libraryStatusNotYet, language: language), systemImage: "text.bubble")
                } description: {
                    Text(L10n.text(recording.hasTracks ? .libraryNotTranscribedAvailable
                                                       : .libraryNotTranscribedOld,
                                   language: language))
                } actions: {
                    Button(L10n.text(.libraryTranscribe, language: language)) { library.enqueue(recording.url) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView {
                    Label(L10n.text(.libraryUnavailableTitle, language: language), systemImage: "text.bubble")
                } description: {
                    Text(L10n.text(.libraryUnavailableMessage, language: language))
                } actions: {
                    Button(L10n.text(.libraryTranscriptionSettings, language: language)) {
                        TranscriptionSettingsWindow.show()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var summaryContent: some View {
        if let summary {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(meetingInfo.topic.isEmpty ? summary.title : meetingInfo.topic)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        Spacer()
                        Button(L10n.text(.summaryViewEditInfo, language: language)) {
                            showingMeetingEditor = true
                        }
                    }
                    if !meetingInfo.participants.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(L10n.format(.summaryViewParticipants, language: language,
                                         meetingInfo.participants))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(L10n.format(.summaryViewStart, language: language,
                                     summaryStartDate))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !meetingInfo.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(L10n.format(.summaryViewNotes, language: language,
                                         meetingInfo.notes))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    HStack(spacing: 10) {
                        Picker(L10n.text(.summaryViewRead, language: language),
                               selection: $summaryDisplay) {
                            Text(L10n.text(.summaryViewRead, language: language))
                                .tag(SummaryDisplayMode.reading)
                            Text(L10n.text(.summaryViewCode, language: language))
                                .tag(SummaryDisplayMode.code)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 190)
                        Spacer()
                        Button {
                            copySummary(summary)
                        } label: {
                            Label(L10n.text(summaryCopied ? .libraryCopied : .summaryViewCopy,
                                            language: language),
                                  systemImage: summaryCopied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                    switch summaryDisplay {
                    case .reading:
                        SummaryMarkdownView(markdown: summary.text)
                    case .code:
                        Text(summary.text)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .textBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.secondary.opacity(0.22)))
                    }
                    Text(L10n.format(.summaryViewGeneratedWith, language: language,
                                     summary.model, summary.promptName, summary.providerName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(L10n.text(.summaryViewRegenerate, language: language)) {
                            showingSummarySheet = true
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: 820, alignment: .leading)
            }
        } else if transcript != nil {
            ContentUnavailableView {
                Label(L10n.text(.summaryViewEmptyTitle, language: language), systemImage: "sparkles")
            } description: {
                Text(L10n.text(.summaryViewEmptyMessage, language: language))
            } actions: {
                HStack {
                    Button(L10n.text(.summaryViewEditInfo, language: language)) {
                        showingMeetingEditor = true
                    }
                    Button(L10n.text(.summaryViewGenerate, language: language)) {
                        showingSummarySheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            ContentUnavailableView {
                Label(L10n.text(.summaryViewNoTranscriptTitle, language: language), systemImage: "text.bubble")
            } description: {
                Text(L10n.text(.summaryViewNoTranscriptMessage, language: language))
            }
        }
    }

    private var currentMarkdown: String? {
        switch mode {
        case .transcript: return library.markdown(for: recording)
        case .summary: return library.summaryMarkdown(for: recording)
        }
    }

    private func copySummary(_ summary: SummaryRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary.text, forType: .string)
        summaryCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { summaryCopied = false }
    }

    private var summaryStartDate: String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: meetingInfo.startDate)
    }

    private func export() {
        let panel = NSSavePanel()
        let suffix = mode == .summary
            ? " " + L10n.text(.summaryViewExportSuffix, language: language) : ""
        panel.nameFieldStringValue = recording.url.deletingPathExtension().lastPathComponent
            + suffix + ".md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText, .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? currentMarkdown?.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct TranscriptView: View {
    let turns: [Transcript.Segment]
    let recording: Library.Recording
    @ObservedObject var player: AudioPlayer

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                        TurnRow(turn: turn, active: isActive(index)) {
                            player.play(recording, from: turn.start)
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: 820, alignment: .leading)
            }
            .onChange(of: activeIndex) { _, index in
                if let index { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .center) } }
            }
        }
    }

    private var activeIndex: Int? {
        guard player.playingID == recording.id, player.isPlaying else { return nil }
        return turns.lastIndex { $0.start <= player.currentTime + 0.2 }
    }

    private func isActive(_ index: Int) -> Bool { activeIndex == index }
}

struct TurnRow: View {
    let turn: Transcript.Segment
    let active: Bool
    let onPlay: () -> Void
    @Environment(\.appLanguage) private var language

    private var color: Color {
        switch turn.speaker {
        case .me: return SpeakerColors.me
        case .others: return SpeakerColors.others
        case .mixed: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Button(action: onPlay) {
                Text(TranscriptFormatter.timestamp(turn.start))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .help(L10n.text(.libraryListenFrom, language: language))
            .accessibilityLabel(L10n.format(.libraryListenFromAccessibility, language: language,
                                            TranscriptFormatter.timestamp(turn.start)))
            VStack(alignment: .leading, spacing: 3) {
                Text(turn.displayLabel(language: language))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                Text(turn.text)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Voce e testo in una lettura sola. La battuta in ascolto si vede solo dallo sfondo:
            // VoiceOver la dice «selezionata».
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(active ? .isSelected : [])
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(active ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Colori delle voci leggibili sul bianco e sul tema scuro (contrasto ≥ 4,5:1 per il testo piccolo).
enum SpeakerColors {
    static let me = dynamic(light: NSColor(srgbRed: 0.10, green: 0.36, blue: 0.82, alpha: 1),
                            dark: NSColor(srgbRed: 0.45, green: 0.66, blue: 1.0, alpha: 1))
    static let others = dynamic(light: NSColor(srgbRed: 0.09, green: 0.45, blue: 0.20, alpha: 1),
                                dark: NSColor(srgbRed: 0.40, green: 0.82, blue: 0.50, alpha: 1))

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
