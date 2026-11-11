import CornettaCore
import SwiftUI

/// Meeting information plus per-run provider/model/prompt selection, followed by
/// an explicit Generate action. Nothing is sent before Generate.
struct SummarySheet: View {
    let recording: Library.Recording
    @ObservedObject var library: Library
    let onGenerated: (SummaryRecord) -> Void

    @State private var topic: String
    @State private var participants: String
    @State private var startDate: Date
    @State private var notes: String

    @State private var providers: [SummaryProvider]
    @State private var providerID: UUID?
    @State private var model: String
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var prompts: [SummaryPrompt]
    @State private var promptID: UUID?

    @State private var generating = false
    @State private var error: String?
    @State private var savedInfo = false

    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    init(recording: Library.Recording, library: Library,
         onGenerated: @escaping (SummaryRecord) -> Void) {
        self.recording = recording
        self.library = library
        self.onGenerated = onGenerated
        let info = library.meetingInfo(for: recording)
        _topic = State(initialValue: info.topic)
        _participants = State(initialValue: info.participants)
        _startDate = State(initialValue: info.startDate)
        _notes = State(initialValue: info.notes)

        let loadedProviders = SummaryProviderCatalog.all()
        let selectedProvider = SummaryProviderCatalog.defaultProvider() ?? loadedProviders.first
        _providers = State(initialValue: loadedProviders)
        _providerID = State(initialValue: selectedProvider?.id)
        _model = State(initialValue: selectedProvider?.model ?? "")

        let loadedPrompts = SummaryPromptCatalog.all()
        let selectedPrompt = SummaryPromptCatalog.defaultPrompt() ?? loadedPrompts.first
        _prompts = State(initialValue: loadedPrompts)
        _promptID = State(initialValue: selectedPrompt?.id)
    }

    private var provider: SummaryProvider? {
        providers.first(where: { $0.id == providerID })
    }

    private var prompt: SummaryPrompt? {
        prompts.first(where: { $0.id == promptID })
    }

    private var transcript: Transcript? { library.transcripts[recording.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text(.summarySheetTitle, language: language))
                .font(.title3.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.text(.summarySheetMeetingInfo, language: language))
                        .font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow(alignment: .top) {
                            Text(L10n.text(.summarySheetTopic, language: language))
                            TextField(L10n.text(.summarySheetTopicPlaceholder, language: language), text: $topic)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 500)
                        }
                        GridRow(alignment: .top) {
                            Text(L10n.text(.summarySheetParticipants, language: language))
                            MeetingTextEditor(
                                placeholder: L10n.text(.summarySheetParticipantsPlaceholder,
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
                            MeetingTextEditor(
                                placeholder: L10n.text(.summarySheetNotesPlaceholder,
                                                       language: language),
                                text: $notes, height: 132)
                                .frame(width: 500)
                        }
                    }

                    Divider()

                    Text(L10n.text(.summarySheetLlm, language: language))
                        .font(.headline)
                    if providers.isEmpty {
                        HStack {
                            Text(L10n.text(.summarySheetNoProviders, language: language))
                                .foregroundStyle(.secondary)
                            Button(L10n.text(.summarySheetOpenSettings, language: language)) {
                                SummarySettingsWindow.show()
                            }
                        }
                    } else {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text(L10n.text(.summarySheetProvider, language: language))
                                Picker(L10n.text(.summarySheetProvider, language: language),
                                       selection: $providerID) {
                                    ForEach(providers) { provider in
                                        Text(provider.name).tag(Optional(provider.id))
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 360)
                                .onChange(of: providerID) { _, newID in
                                    guard let newProvider = providers.first(where: { $0.id == newID }) else {
                                        return
                                    }
                                    model = newProvider.model
                                    models = []
                                    Task { await loadModels(for: newProvider) }
                                }
                            }
                            GridRow {
                                Text(L10n.text(.summarySheetModel, language: language))
                                modelControl
                            }
                            GridRow {
                                Text(L10n.text(.summarySheetPrompt, language: language))
                                Picker(L10n.text(.summarySheetPrompt, language: language),
                                       selection: $promptID) {
                                    ForEach(prompts) { prompt in
                                        Text(prompt.name).tag(Optional(prompt.id))
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 360)
                            }
                        }
                    }

                    if transcript == nil {
                        Text(L10n.text(.summarySheetNoTranscript, language: language))
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                    if savedInfo {
                        Text(L10n.text(.summarySheetSavedInfo, language: language))
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(L10n.text(.summarySheetPrivacy, language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxHeight: 570)

            HStack {
                Button(L10n.text(.summarySheetSaveInfo, language: language)) { saveInfo() }
                Spacer()
                Button(L10n.text(.commonCancel, language: language)) { dismiss() }
                    .disabled(generating)
                Button(generating ? L10n.text(.summarySheetGenerating, language: language)
                        : L10n.text(.summarySheetGenerate, language: language)) {
                    generate()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(generating || transcript == nil || provider == nil
                          || prompt == nil || model.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 700)
        .task { await loadModels(for: provider) }
    }

    private func loadModels(for provider: SummaryProvider?) async {
        guard let provider else { return }
        loadingModels = true
        let key = SummaryProviderCatalog.apiKey(for: provider)
        let available = await SummaryService.availableModels(provider: provider, apiKey: key)
        // A quick provider switch can finish an older request later. Never let
        // that response replace the list for the provider now selected.
        guard providerID == provider.id else { return }
        models = available ?? []
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model = models.first ?? provider.model
        }
        loadingModels = false
    }

    private var modelOptions: [String] {
        var options = models
        let current = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options
    }

    @ViewBuilder
    private var modelControl: some View {
        if loadingModels {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.text(.summarySheetLoadingModels, language: language))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 360, alignment: .leading)
        } else if modelOptions.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    TextField(L10n.text(.summarySettingsModelPlaceholder, language: language),
                              text: $model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 360)
                    Button {
                        Task { await loadModels(for: provider) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(L10n.text(.summarySheetReloadModels, language: language))
                }
                Text(L10n.text(.summarySheetModelsUnavailable, language: language))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else {
            HStack(spacing: 6) {
                Picker(L10n.text(.summarySheetModel, language: language), selection: $model) {
                    ForEach(modelOptions, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 360)
                Button {
                    Task { await loadModels(for: provider) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.text(.summarySheetReloadModels, language: language))
            }
        }
    }

    private func saveInfo() {
        do {
            try library.saveMeetingInfo(MeetingInfo(topic: topic, participants: participants,
                                                    startDate: startDate, notes: notes),
                                        for: recording)
            savedInfo = true
            error = nil
        } catch {
            self.error = L10n.text(.summarySheetError, language: language)
        }
    }

    private func generate() {
        guard let provider, let prompt else { return }
        generating = true
        savedInfo = false
        error = nil
        let info = MeetingInfo(topic: topic, participants: participants,
                               startDate: startDate, notes: notes)
        Task {
            do {
                try library.saveMeetingInfo(info, for: recording)
                let record = try await library.generateSummary(recording, meetingInfo: info,
                                                               provider: provider, model: model,
                                                               prompt: prompt)
                onGenerated(record)
                dismiss()
            } catch {
                Diagnostics.log("Riassunto non riuscito: \(error.localizedDescription)")
                self.error = L10n.text(.summarySheetError, language: language)
                generating = false
            }
        }
    }
}
