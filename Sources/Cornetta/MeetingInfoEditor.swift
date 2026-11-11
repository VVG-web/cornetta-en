import AppKit
import CornettaCore
import SwiftUI

/// Multi-line meeting field. TextEditor scrolls internally, so participants and
/// notes can hold long text without making the window grow without limits.
struct MeetingTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var height: CGFloat = 110

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(4)
                .accessibilityLabel(placeholder)
        }
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
    }
}

/// Independent editor for meeting properties. It never sends or generates
/// anything and can be opened before deciding whether to create a summary.
struct MeetingInfoEditor: View {
    let recording: Library.Recording
    @ObservedObject var library: Library

    @State private var topic: String
    @State private var participants: String
    @State private var startDate: Date
    @State private var notes: String
    @State private var error: String?
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    init(recording: Library.Recording, library: Library) {
        self.recording = recording
        self.library = library
        let info = library.meetingInfo(for: recording)
        _topic = State(initialValue: info.topic)
        _participants = State(initialValue: info.participants)
        _startDate = State(initialValue: info.startDate)
        _notes = State(initialValue: info.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text(.summaryInfoTitle, language: language))
                .font(.title3.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow(alignment: .top) {
                    Text(L10n.text(.summarySheetTopic, language: language))
                    TextField(L10n.text(.summarySheetTopicPlaceholder, language: language), text: $topic)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 500)
                }
                GridRow(alignment: .top) {
                    Text(L10n.text(.summarySheetParticipants, language: language))
                    MeetingTextEditor(placeholder: L10n.text(.summarySheetParticipantsPlaceholder,
                                                              language: language),
                                      text: $participants, height: 112)
                        .frame(width: 500)
                }
                GridRow {
                    Text(L10n.text(.summarySheetStart, language: language))
                    DatePicker(L10n.text(.summarySheetStart, language: language),
                               selection: $startDate,
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                GridRow(alignment: .top) {
                    Text(L10n.text(.summarySheetNotes, language: language))
                    MeetingTextEditor(placeholder: L10n.text(.summarySheetNotesPlaceholder,
                                                              language: language),
                                      text: $notes, height: 132)
                        .frame(width: 500)
                }
            }

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(L10n.text(.commonCancel, language: language)) { dismiss() }
                Button(L10n.text(.commonSave, language: language)) { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 640)
    }

    private func save() {
        do {
            try library.saveMeetingInfo(MeetingInfo(topic: topic, participants: participants,
                                                    startDate: startDate, notes: notes),
                                        for: recording)
            dismiss()
        } catch {
            self.error = L10n.text(.summaryInfoSaveError, language: language)
        }
    }
}
