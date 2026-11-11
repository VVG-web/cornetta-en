import AppKit
import CornettaCore
import SwiftUI

/// Settings for OpenAI-compatible summary providers and prompt templates.
struct SummarySettingsView: View {
    @State private var tab = 0
    @State private var providers: [SummaryProvider]
    @State private var providerID: UUID?
    @State private var providerDraft: SummaryProvider
    @State private var apiKey: String
    @State private var apiKeyDirty = false
    @State private var checking = false
    @State private var checkResult: ProviderCheckResult?
    @State private var providerError: String?
    @State private var confirmDeleteProvider = false
    @State private var providerModels: [String] = []
    @State private var loadingProviderModels = false
    @State private var providerModelsLoaded = false
    @State private var modelLoadGeneration = 0

    @State private var prompts: [SummaryPrompt]
    @State private var promptID: UUID?
    @State private var promptDraft: SummaryPrompt
    @State private var promptError: String?
    @State private var confirmDeletePrompt = false

    @Environment(\.appLanguage) private var language

    init() {
        let loadedProviders = SummaryProviderCatalog.all()
        let selectedProvider = SummaryProviderCatalog.defaultProvider() ?? loadedProviders.first
        _providers = State(initialValue: loadedProviders)
        _providerID = State(initialValue: selectedProvider?.id)
        _providerDraft = State(initialValue: selectedProvider
            ?? SummaryProvider(name: L10n.text(.summarySettingsNamePlaceholder, language: .initial())))
        _apiKey = State(initialValue: selectedProvider.map(SummaryProviderCatalog.apiKey) ?? "")

        let loadedPrompts = SummaryPromptCatalog.all()
        let selectedPrompt = SummaryPromptCatalog.defaultPrompt() ?? loadedPrompts.first
        _prompts = State(initialValue: loadedPrompts)
        _promptID = State(initialValue: selectedPrompt?.id)
        _promptDraft = State(initialValue: selectedPrompt
            ?? SummaryPromptCatalog.builtin(language: .initial()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text(.summarySettingsTitle, language: language))
                .font(.title2.weight(.semibold))

            Picker(L10n.text(.summarySettingsTitle, language: language), selection: $tab) {
                Text(L10n.text(.summarySettingsProviders, language: language)).tag(0)
                Text(L10n.text(.summarySettingsPrompts, language: language)).tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                if tab == 0 {
                    providerSettings
                } else {
                    promptSettings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                Button(L10n.text(.commonClose, language: language)) {
                    NSApp.keyWindow?.close()
                }
                if tab == 0 {
                    Button(L10n.text(.commonSave, language: language)) { saveProvider() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(providerDraft.name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || !providerDraft.config.isConfigured)
                } else {
                    Button(L10n.text(.commonSave, language: language)) { savePrompt() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(promptDraft.name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || promptDraft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 650, alignment: .topLeading)
        .task { await loadProviderModels() }
        .onChange(of: providerID) { _, id in
            guard let provider = providers.first(where: { $0.id == id }) else { return }
            providerDraft = provider
            apiKey = SummaryProviderCatalog.apiKey(for: provider)
            apiKeyDirty = false
            checkResult = nil
            providerError = nil
            clearProviderModels()
            Task { await loadProviderModels() }
        }
        .onChange(of: providerDraft.baseURL) { _, _ in
            guard let saved = providers.first(where: { $0.id == providerDraft.id }),
                  providerDraft.baseURL != saved.baseURL else { return }
            clearProviderModels()
        }
        .onChange(of: promptID) { _, id in
            guard let prompt = prompts.first(where: { $0.id == id }) else { return }
            promptDraft = prompt
            promptError = nil
        }
        .confirmationDialog(L10n.text(.summarySettingsDeleteProviderTitle, language: language),
                            isPresented: $confirmDeleteProvider) {
            Button(L10n.text(.transcriptionSettingsDelete, language: language), role: .destructive) {
                deleteProvider()
            }
            Button(L10n.text(.commonCancel, language: language), role: .cancel) {}
        } message: {
            Text(L10n.text(.summarySettingsDeleteProviderMessage, language: language))
        }
        .confirmationDialog(L10n.text(.summarySettingsDeletePromptTitle, language: language),
                            isPresented: $confirmDeletePrompt) {
            Button(L10n.text(.transcriptionSettingsDelete, language: language), role: .destructive) {
                deletePrompt()
            }
            Button(L10n.text(.commonCancel, language: language), role: .cancel) {}
        } message: {
            Text(L10n.text(.summarySettingsDeletePromptMessage, language: language))
        }
    }

    private var providerSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text(.summarySettingsProvider, language: language))
                Picker(L10n.text(.summarySettingsProvider, language: language), selection: $providerID) {
                    ForEach(providers) { provider in
                        Text(provider.name).tag(Optional(provider.id))
                    }
                    if providers.isEmpty {
                        Text(L10n.text(.commonNone, language: language)).tag(nil as UUID?)
                    }
                }
                .labelsHidden()
                .frame(width: 320)
                Button {
                    addProvider()
                } label: {
                    Image(systemName: "plus")
                }
                .help(L10n.text(.summarySettingsAddProvider, language: language))
            }

            Toggle(L10n.text(.summarySettingsDefaultProvider, language: language),
                   isOn: defaultProviderBinding)

            Text(L10n.text(.summarySettingsProviderDescription, language: language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if providers.isEmpty {
                Text(L10n.text(.summarySettingsNoProviders, language: language))
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text(L10n.text(.summarySettingsName, language: language))
                        TextField(L10n.text(.summarySettingsNamePlaceholder, language: language),
                                  text: $providerDraft.name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                    }
                    GridRow {
                        Text(L10n.text(.summarySettingsBaseURL, language: language))
                        TextField(L10n.text(.summarySettingsBaseURLPlaceholder, language: language),
                                  text: $providerDraft.baseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 440)
                            .font(.system(.body, design: .monospaced))
                            .help(L10n.text(.summarySettingsBaseURLHelp, language: language))
                    }
                    GridRow {
                        Text(L10n.text(.summarySettingsDefaultModel, language: language))
                        providerModelControl
                    }
                    GridRow {
                        Text(L10n.text(.summarySettingsApiKey, language: language))
                        SecureField(L10n.text(.summarySettingsApiKeyPlaceholder, language: language),
                                    text: Binding(get: { apiKey },
                                                  set: { apiKey = $0; apiKeyDirty = true }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 440)
                            .help(L10n.text(.summarySettingsApiKeyHelp, language: language))
                    }
                }

                Text(providerDraft.config.endpointDescription)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(providerDraft.config.isConfigured ? Color.secondary : Color.red)
                    .textSelection(.enabled)

                HStack {
                    Button(checking ? L10n.text(.summarySettingsChecking, language: language)
                            : L10n.text(.summarySettingsCheck, language: language)) {
                        checkProvider()
                    }
                    .disabled(checking || !providerDraft.config.isConfigured)
                    .help(L10n.text(.summarySettingsCheckHelp, language: language))
                    if let checkResult {
                        Text(checkText(checkResult))
                            .font(.callout)
                            .foregroundStyle(checkColor(checkResult))
                    }
                }
                if !providerDraft.config.isConfigured {
                    Text(L10n.text(.summarySettingsInvalid, language: language))
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                if let providerError {
                    Text(providerError).font(.callout).foregroundStyle(.red)
                }
            }

            HStack {
                if !providers.isEmpty {
                    Button(L10n.text(.summarySettingsDeleteProvider, language: language), role: .destructive) {
                        confirmDeleteProvider = true
                    }
                }
                Spacer()
            }
        }
    }

    private var promptSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text(.summarySettingsPrompt, language: language))
                Picker(L10n.text(.summarySettingsPrompt, language: language), selection: $promptID) {
                    ForEach(prompts) { prompt in
                        Text(prompt.name).tag(Optional(prompt.id))
                    }
                    if prompts.isEmpty {
                        Text(L10n.text(.commonNone, language: language)).tag(nil as UUID?)
                    }
                }
                .labelsHidden()
                .frame(width: 320)
                Button {
                    addPrompt()
                } label: {
                    Image(systemName: "plus")
                }
                .help(L10n.text(.summarySettingsAddPrompt, language: language))
            }

            Text(L10n.text(.summarySettingsPromptDescription, language: language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if prompts.isEmpty {
                Text(L10n.text(.summarySettingsNoPrompts, language: language))
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text(L10n.text(.summarySettingsPromptName, language: language))
                        TextField(L10n.text(.summarySettingsPromptNamePlaceholder, language: language),
                                  text: $promptDraft.name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 360)
                    }
                    GridRow {
                        Text(L10n.text(.summarySettingsDefaultPrompt, language: language))
                        Toggle(L10n.text(.summarySettingsDefaultPrompt, language: language),
                               isOn: $promptDraft.isDefault)
                            .labelsHidden()
                    }
                }

                Text(L10n.text(.summarySettingsPromptBody, language: language))
                    .font(.callout.weight(.medium))
                TextEditor(text: $promptDraft.body)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 210, maxHeight: .infinity)
                    .layoutPriority(1)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.25)))
                Text(L10n.text(.summarySettingsPromptHelp, language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let promptError {
                    Text(promptError).font(.callout).foregroundStyle(.red)
                }
            }

            HStack {
                if !prompts.isEmpty {
                    Button(L10n.text(.summarySettingsDeletePrompt, language: language), role: .destructive) {
                        confirmDeletePrompt = true
                    }
                }
                Spacer()
            }
        }
    }

    private func addProvider() {
        let provider = SummaryProvider(name: L10n.text(.summarySettingsNamePlaceholder, language: language))
        do {
            try SummaryProviderCatalog.save(provider, apiKey: nil, makeDefault: providers.isEmpty)
            providers = SummaryProviderCatalog.all()
            providerID = provider.id
            providerDraft = provider
            apiKey = ""
            apiKeyDirty = false
            checkResult = nil
        } catch {
            providerError = L10n.text(.summarySettingsKeychainError, language: language)
        }
    }

    private var defaultProviderBinding: Binding<Bool> {
        Binding(
            get: { SummaryProviderCatalog.defaultProvider()?.id == providerID },
            set: { enabled in
                if enabled, let providerID {
                    SummaryProviderCatalog.setDefault(providerID)
                } else if let other = providers.first(where: { $0.id != providerID }) {
                    SummaryProviderCatalog.setDefault(other.id)
                }
            }
        )
    }

    private var providerModelOptions: [String] {
        var options = providerModels
        let current = providerDraft.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options
    }

    @ViewBuilder
    private var providerModelControl: some View {
        if loadingProviderModels {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.text(.summarySheetLoadingModels, language: language))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 360, alignment: .leading)
        } else if providerModels.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TextField(L10n.text(.summarySettingsModelPlaceholder, language: language),
                              text: $providerDraft.model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                    Button {
                        Task { await loadProviderModels() }
                    } label: {
                        Label(L10n.text(.summarySettingsLoadModels, language: language),
                              systemImage: "arrow.clockwise")
                    }
                    .disabled(!providerDraft.config.isConfigured)
                    .help(L10n.text(.summarySettingsLoadModelsHelp, language: language))
                }
                Text(L10n.text(providerModelsLoaded ? .summarySettingsModelsUnavailable
                                                    : .summarySettingsDefaultModelHelp,
                               language: language))
                    .font(.caption)
                    .foregroundStyle(providerModelsLoaded ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Picker(L10n.text(.summarySettingsDefaultModel, language: language),
                           selection: $providerDraft.model) {
                        ForEach(providerModelOptions, id: \.self) { item in
                            Text(item).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 320)
                    Button {
                        Task { await loadProviderModels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(L10n.text(.summarySettingsLoadModelsHelp, language: language))
                }
                Text(L10n.text(.summarySettingsDefaultModelHelp, language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func clearProviderModels() {
        modelLoadGeneration += 1
        providerModels = []
        providerModelsLoaded = false
        loadingProviderModels = false
    }

    private func loadProviderModels() async {
        guard providers.contains(where: { $0.id == providerDraft.id }),
              providerDraft.config.isConfigured else {
            clearProviderModels()
            return
        }
        modelLoadGeneration += 1
        let generation = modelLoadGeneration
        let id = providerDraft.id
        let baseURL = providerDraft.baseURL
        loadingProviderModels = true
        providerModelsLoaded = false
        let available = await SummaryService.availableModels(provider: providerDraft, apiKey: apiKey)
        guard generation == modelLoadGeneration, providerDraft.id == id,
              providerDraft.baseURL == baseURL else { return }
        providerModels = available ?? []
        providerModelsLoaded = true
        loadingProviderModels = false
        if providerModels.first != nil,
           providerDraft.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            providerDraft.model = providerModels[0]
        }
    }

    private func saveProvider() {
        do {
            try SummaryProviderCatalog.save(providerDraft,
                                             apiKey: apiKeyDirty ? apiKey : nil,
                                             makeDefault: providers.isEmpty)
            providers = SummaryProviderCatalog.all()
            providerID = providerDraft.id
            apiKeyDirty = false
            providerError = nil
            Task { await loadProviderModels() }
        } catch {
            providerError = L10n.text(.summarySettingsKeychainError, language: language)
        }
    }

    private func deleteProvider() {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return }
        SummaryProviderCatalog.delete(provider)
        providers = SummaryProviderCatalog.all()
        if let first = providers.first {
            providerID = first.id
            providerDraft = first
            apiKey = SummaryProviderCatalog.apiKey(for: first)
        } else {
            providerID = nil
            providerDraft = SummaryProvider(name: L10n.text(.summarySettingsNamePlaceholder, language: language))
            apiKey = ""
        }
        apiKeyDirty = false
    }

    private func checkProvider() {
        checking = true
        checkResult = nil
        let provider = providerDraft
        let key = apiKey
        Task {
            let result = await SummaryService.check(provider: provider, apiKey: key)
            await MainActor.run {
                checkResult = result
                checking = false
            }
        }
    }

    private func addPrompt() {
        let prompt = SummaryPromptCatalog.builtin(language: language)
        var newPrompt = prompt
        newPrompt.id = UUID()
        newPrompt.isDefault = false
        SummaryPromptCatalog.save(newPrompt)
        prompts = SummaryPromptCatalog.all(language: language)
        promptID = newPrompt.id
        promptDraft = prompts.first(where: { $0.id == newPrompt.id }) ?? newPrompt
    }

    private func savePrompt() {
        SummaryPromptCatalog.save(promptDraft)
        prompts = SummaryPromptCatalog.all(language: language)
        if let current = prompts.first(where: { $0.id == promptDraft.id }) {
            promptDraft = current
        }
        promptError = promptDraft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.text(.summarySettingsPromptEmpty, language: language) : nil
    }

    private func deletePrompt() {
        guard let prompt = prompts.first(where: { $0.id == promptID }) else { return }
        SummaryPromptCatalog.delete(prompt)
        prompts = SummaryPromptCatalog.all(language: language)
        if let first = prompts.first {
            promptID = first.id
            promptDraft = first
        } else {
            promptID = nil
            promptDraft = SummaryPromptCatalog.builtin(language: language)
        }
    }

    private func checkText(_ result: ProviderCheckResult) -> String {
        switch result {
        case .modelAvailable(let model):
            return L10n.format(.transcriptionSettingsCheckModelAvailable, language: language, model)
        case .modelNotListed(let model):
            return L10n.format(.summarySettingsCheckModelMissing, language: language, model)
        case .reachable:
            return L10n.text(.transcriptionSettingsCheckReachable, language: language)
        case .unauthorized(let code):
            return L10n.format(.transcriptionSettingsCheckUnauthorized, language: language, String(code))
        case .noModelList:
            return L10n.text(.summarySettingsCheckNoModels, language: language)
        case .http(let code):
            return L10n.format(.transcriptionSettingsCheckHttp, language: language, String(code))
        case .invalidResponse:
            return L10n.text(.transcriptionSettingsCheckInvalidResponse, language: language)
        case .invalidConfiguration:
            return L10n.text(.transcriptionSettingsCheckInvalidConfiguration, language: language)
        case .network:
            return L10n.text(.transcriptionSettingsCheckNetwork, language: language)
        }
    }

    private func checkColor(_ result: ProviderCheckResult) -> Color {
        switch result {
        case .modelAvailable, .reachable: return .green
        case .modelNotListed, .noModelList: return .orange
        default: return .red
        }
    }
}

@MainActor
enum SummarySettingsWindow {
    private static var window: NSWindow?
    private static var languageObserver: NSObjectProtocol?

    static func show() {
        if window == nil {
            let window = NSWindow(contentRect: .zero,
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = tr(.summarySettingsWindow)
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 700, height: 650)
            window.setFrameAutosaveName("CornettaSummarySettings")
            if !window.setFrameUsingName("CornettaSummarySettings") { window.center() }
            self.window = window
            if languageObserver == nil {
                languageObserver = NotificationCenter.default.addObserver(
                    forName: .cornettaLanguageChanged, object: nil, queue: .main
                ) { _ in
                    MainActor.assumeIsolated {
                        SummarySettingsWindow.window?.title = tr(.summarySettingsWindow)
                    }
                }
            }
        }
        guard let window else { return }
        if !window.isVisible {
            let hosting = NSHostingView(rootView: SummarySettingsView().localizedRoot())
            window.contentView = hosting
            window.setContentSize(hosting.fittingSize)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
