import CornettaCore
import SwiftUI

/// Sheet for the five standard audio tags. The values are written into the .m4a;
/// the title also becomes the recording title in the library.
struct RecordingTagsEditor: View {
    let recording: Library.Recording
    let onSave: (RecordingTags) async throws -> Void

    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var date: String
    @State private var comment: String
    @State private var saving = false
    @State private var error: String?
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(recording: Library.Recording, tags: RecordingTags,
         onSave: @escaping (RecordingTags) async throws -> Void) {
        self.recording = recording
        self.onSave = onSave
        _title = State(initialValue: tags.title)
        _artist = State(initialValue: tags.artist)
        _album = State(initialValue: tags.album)
        _date = State(initialValue: tags.date.isEmpty
            ? Self.dateFormatter.string(from: recording.date) : tags.date)
        _comment = State(initialValue: tags.comment)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text(.libraryTagsEditorTitle, language: language))
                .font(.title3.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                field(.libraryTagsTitle, text: $title, width: 420)
                field(.libraryTagsArtist, text: $artist, width: 420)
                field(.libraryTagsAlbum, text: $album, width: 420)
                GridRow {
                    Text(L10n.text(.libraryTagsDate, language: language))
                    TextField(L10n.text(.libraryTagsDatePlaceholder, language: language), text: $date)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .font(.system(.body, design: .monospaced))
                        .textContentType(nil)
                        .disableAutocorrection(true)
                        .accessibilityLabel(L10n.text(.libraryTagsDate, language: language))
                }
                GridRow(alignment: .top) {
                    Text(L10n.text(.libraryTagsComment, language: language))
                    TextField(L10n.text(.libraryTagsComment, language: language),
                              text: $comment, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 420)
                        .frame(minHeight: 58, alignment: .topLeading)
                        .lineLimit(3...5)
                        .textContentType(nil)
                        .disableAutocorrection(true)
                        .accessibilityLabel(L10n.text(.libraryTagsComment, language: language))
                }
            }

            Text(L10n.text(.libraryTagsHelp, language: language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(L10n.text(.commonCancel, language: language)) { dismiss() }
                    .disabled(saving)
                Button(L10n.text(.commonSave, language: language)) { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(saving)
                if saving {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(24)
        .frame(width: 580)
    }

    @ViewBuilder
    private func field(_ key: L10nKey, text: Binding<String>, width: CGFloat) -> some View {
        GridRow {
            Text(L10n.text(key, language: language))
            TextField(L10n.text(key, language: language), text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
                .textContentType(nil)
                .disableAutocorrection(true)
                .accessibilityLabel(L10n.text(key, language: language))
        }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            do {
                try await onSave(RecordingTags(title: title, artist: artist, album: album,
                                               date: date, comment: comment))
                dismiss()
            } catch {
                self.error = L10n.text(.libraryTagsSaveError, language: language)
                saving = false
            }
        }
    }
}
