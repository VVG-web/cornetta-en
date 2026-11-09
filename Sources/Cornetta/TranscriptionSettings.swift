import AppKit
import CornettaCore
import SwiftUI

/// Finestra per scegliere il motore di trascrizione e gestire più provider HTTP.
struct TranscriptionSettingsView: View {
    @State private var providers: [TranscriptionProvider]
    @State private var selectedID: UUID
    @State private var draft: TranscriptionProvider
    @State private var apiKey: String
    @State private var apiKeyDirty = false
    @AppStorage(TranscriptionPreferences.autoTranscribeKey) private var autoTranscribe = false
    @State private var saveError: String?
    @State private var checking = false
    @State private var checkResult: ProviderCheckResult?
    @State private var addingProvider = false
    @State private var confirmDelete = false
    @State private var showingDiarizationSettings = false

    @Environment(\.appLanguage) private var language

    init() {
        let all = TranscriptionProviderCatalog.all()
        let selected = TranscriptionProviderCatalog.selected()
        _providers = State(initialValue: all)
        _selectedID = State(initialValue: selected.id)
        _draft = State(initialValue: selected)
        _apiKey = State(initialValue: TranscriptionProviderCatalog.apiKey(for: selected))
    }

    private var isApple: Bool { draft.kind == .apple }
    private var config: TranscriptionConfig { draft.config }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text(.transcriptionSettingsTitle, language: language))
                .font(.title2.weight(.semibold))

            HStack {
                Text(L10n.text(.transcriptionSettingsProvider, language: language))
                Picker(L10n.text(.transcriptionSettingsProvider, language: language), selection: $selectedID) {
                    ForEach(providers) { provider in
                        Text(providerName(provider)).tag(provider.id)
                    }
                }
                .labelsHidden()
                .frame(width: 300)
                Button {
                    addingProvider = true
                } label: {
                    Image(systemName: "plus")
                }
                .help(L10n.text(.transcriptionSettingsAddProvider, language: language))
            }

            Toggle(L10n.text(.transcriptionSettingsAuto, language: language), isOn: $autoTranscribe)

            if isApple {
                appleSettings
            } else {
                customProviderSettings
            }

            if let saveError {
                Text(saveError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                if !isApple {
                    Button(L10n.text(.transcriptionSettingsDeleteProvider, language: language),
                           role: .destructive) {
                        confirmDelete = true
                    }
                }
                Spacer()
                Button(L10n.text(.commonClose, language: language)) {
                    NSApp.keyWindow?.close()
                }
                if !isApple {
                    Button(L10n.text(.commonSave, language: language)) {
                        save()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!config.isConfigured || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 640)
        .onChange(of: selectedID) { _, id in
            TranscriptionProviderCatalog.select(id)
            NotificationCenter.default.post(name: .cornettaTranscriptionSettingsChanged, object: nil)
            guard let provider = providers.first(where: { $0.id == id }) else { return }
            draft = provider
            apiKey = TranscriptionProviderCatalog.apiKey(for: provider)
            apiKeyDirty = false
            checkResult = nil
            saveError = nil
        }
        .sheet(isPresented: $addingProvider) {
            AddProviderView { provider in
                refreshProviders(select: provider.id)
            }
            .localizedRoot()
        }
        .sheet(isPresented: $showingDiarizationSettings) {
            DiarizationSettingsView(settings: draft.diarization ?? DiarizationSettings()) { settings in
                draft.diarization = settings
            }
            .localizedRoot()
        }
        .confirmationDialog(L10n.text(.transcriptionSettingsDeleteProviderTitle, language: language),
                            isPresented: $confirmDelete) {
            Button(L10n.text(.transcriptionSettingsDelete, language: language), role: .destructive) {
                deleteProvider()
            }
            Button(L10n.text(.commonCancel, language: language), role: .cancel) {}
        } message: {
            Text(L10n.text(.transcriptionSettingsDeleteProviderMessage, language: language))
        }
    }

    private var appleSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(.transcriptionSettingsAppleDescription, language: language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !SpeechEngine.isAvailable {
                Text(L10n.text(.transcriptionSettingsAppleUnavailable, language: language))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var customProviderSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text(.transcriptionSettingsDescription, language: language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(L10n.text(.transcriptionSettingsProviderName, language: language))
                    TextField(L10n.text(.transcriptionSettingsProviderNamePlaceholder, language: language),
                              text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                        .textContentType(nil)
                        .disableAutocorrection(true)
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsBaseURL, language: language))
                    TextField(L10n.text(.transcriptionSettingsBaseURLPlaceholder, language: language),
                              text: $draft.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 420)
                        .font(.system(.body, design: .monospaced))
                        .textContentType(nil)
                        .disableAutocorrection(true)
                        .help(L10n.text(.transcriptionSettingsBaseURLHelp, language: language))
                        .accessibilityLabel(L10n.text(.transcriptionSettingsBaseURL, language: language))
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsModel, language: language))
                    TextField(L10n.text(.transcriptionSettingsModelPlaceholder, language: language),
                              text: $draft.model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                        .textContentType(nil)
                        .disableAutocorrection(true)
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsLanguage, language: language))
                    TextField(L10n.text(.transcriptionSettingsLanguagePlaceholder, language: language),
                              text: $draft.language)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .textContentType(nil)
                        .disableAutocorrection(true)
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsApiKey, language: language))
                    SecureField(L10n.text(.transcriptionSettingsApiKeyPlaceholder, language: language),
                                text: Binding(get: { apiKey },
                                              set: { apiKey = $0; apiKeyDirty = true }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 420)
                        .textContentType(nil)
                        .disableAutocorrection(true)
                        .help(L10n.text(.transcriptionSettingsApiKeyHelp, language: language))
                        .accessibilityLabel(L10n.text(.transcriptionSettingsApiKey, language: language))
                }
            }

            Text(L10n.text(.transcriptionSettingsTransport, language: language))
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Toggle(L10n.text(.transcriptionSettingsDiarization, language: language),
                       isOn: diarizationEnabled)
                    .help(L10n.text(.transcriptionSettingsDiarizationHelp, language: language))
                if draft.diarization?.enabled == true {
                    Button(L10n.text(.transcriptionSettingsDiarizationSettings, language: language)) {
                        showingDiarizationSettings = true
                    }
                    .controlSize(.small)
                }
            }

            Text(config.endpointDescription)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(config.isConfigured ? Color.secondary : Color.red)
                .textSelection(.enabled)

            if !config.isConfigured {
                Text(L10n.text(.transcriptionSettingsInvalid, language: language))
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(checking ? L10n.text(.transcriptionSettingsChecking, language: language)
                        : L10n.text(.transcriptionSettingsCheck, language: language)) {
                    check()
                }
                .disabled(checking || !config.isConfigured)
                .help(L10n.text(.transcriptionSettingsCheckHelp, language: language))
                if let checkResult {
                    Text(checkText(checkResult))
                        .font(.callout)
                        .foregroundStyle(checkColor(checkResult))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(L10n.text(.transcriptionSettingsPrivacy, language: language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func providerName(_ provider: TranscriptionProvider) -> String {
        provider.kind == .apple
            ? L10n.text(.transcriptionSettingsAppleName, language: language)
            : provider.name
    }

    private var diarizationEnabled: Binding<Bool> {
        Binding(
            get: { draft.diarization?.enabled == true },
            set: { enabled in
                var settings = draft.diarization ?? DiarizationSettings()
                settings.enabled = enabled
                draft.diarization = settings.normalized
                if enabled { showingDiarizationSettings = true }
            }
        )
    }

    private func refreshProviders(select id: UUID?) {
        providers = TranscriptionProviderCatalog.all()
        if let id { selectedID = id }
        if let provider = providers.first(where: { $0.id == selectedID }) {
            draft = provider
            apiKey = TranscriptionProviderCatalog.apiKey(for: provider)
            apiKeyDirty = false
        }
        checkResult = nil
        saveError = nil
        NotificationCenter.default.post(name: .cornettaTranscriptionSettingsChanged, object: nil)
    }

    private func save() {
        guard config.isConfigured, !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            try TranscriptionProviderCatalog.save(draft, apiKey: apiKeyDirty ? apiKey : nil,
                                                   select: true)
            refreshProviders(select: draft.id)
            NSApp.keyWindow?.close()
        } catch {
            saveError = L10n.text(.transcriptionSettingsKeychainError, language: language)
        }
    }

    private func deleteProvider() {
        TranscriptionProviderCatalog.delete(draft)
        let next = TranscriptionProviderCatalog.selected()
        refreshProviders(select: next.id)
    }

    private func check() {
        checking = true
        checkResult = nil
        let config = config
        let key = apiKey
        Task {
            let result = await ProviderCheck.run(config: config, apiKey: key)
            await MainActor.run {
                checkResult = result
                checking = false
            }
        }
    }

    private func checkText(_ result: ProviderCheckResult) -> String {
        switch result {
        case .modelAvailable(let model):
            return L10n.format(.transcriptionSettingsCheckModelAvailable, language: language, model)
        case .modelNotListed(let model):
            return L10n.format(.transcriptionSettingsCheckModelMissing, language: language, model)
        case .reachable:
            return L10n.text(.transcriptionSettingsCheckReachable, language: language)
        case .unauthorized(let code):
            return L10n.format(.transcriptionSettingsCheckUnauthorized, language: language, String(code))
        case .noModelList(let code):
            return L10n.format(.transcriptionSettingsCheckNoModels, language: language, String(code))
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

struct AddProviderView: View {
    @State private var name = ""
    @State private var baseURL = TranscriptionPreferences.defaultBaseURL
    @State private var model = TranscriptionPreferences.defaultModel
    @State private var languageCode = TranscriptionPreferences.defaultLanguage
    @State private var apiKey = ""
    @State private var error: String?
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    let onSaved: (TranscriptionProvider) -> Void

    private var config: TranscriptionConfig {
        TranscriptionConfig(baseURL: baseURL, model: model, language: languageCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text(.transcriptionSettingsNewProvider, language: language))
                .font(.title3.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(L10n.text(.transcriptionSettingsProviderName, language: language))
                    TextField(L10n.text(.transcriptionSettingsProviderNamePlaceholder, language: language),
                              text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                        .textContentType(nil)
                        .disableAutocorrection(true)
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsBaseURL, language: language))
                    TextField(L10n.text(.transcriptionSettingsBaseURLPlaceholder, language: language),
                              text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 420)
                        .font(.system(.body, design: .monospaced))
                        .textContentType(nil)
                        .disableAutocorrection(true)
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsModel, language: language))
                    TextField(L10n.text(.transcriptionSettingsModelPlaceholder, language: language),
                              text: $model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                        .textContentType(nil)
                        .disableAutocorrection(true)
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsLanguage, language: language))
                    TextField(L10n.text(.transcriptionSettingsLanguagePlaceholder, language: language),
                              text: $languageCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .textContentType(nil)
                        .disableAutocorrection(true)
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsApiKey, language: language))
                    SecureField(L10n.text(.transcriptionSettingsApiKeyPlaceholder, language: language),
                                text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 420)
                        .textContentType(nil)
                        .disableAutocorrection(true)
                }
            }
            Text(config.endpointDescription)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(config.isConfigured ? Color.secondary : Color.red)
            if !config.isConfigured {
                Text(L10n.text(.transcriptionSettingsInvalid, language: language))
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(L10n.text(.commonCancel, language: language)) { dismiss() }
                Button(L10n.text(.commonSave, language: language)) { add() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!config.isConfigured || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func add() {
        let provider = TranscriptionProvider(name: name, kind: .http, baseURL: baseURL,
                                             model: model, language: languageCode)
        do {
            try TranscriptionProviderCatalog.save(provider, apiKey: apiKey, select: true)
            onSaved(provider)
            dismiss()
        } catch {
            self.error = L10n.text(.transcriptionSettingsKeychainError, language: language)
        }
    }
}

@MainActor
enum TranscriptionSettingsWindow {
    private static var window: NSWindow?
    private static var languageObserver: NSObjectProtocol?
    private static var fitTimer: Timer?

    static func show() {
        if window == nil {
            let window = NSWindow(contentRect: .zero,
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = tr(.transcriptionSettingsWindow)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("CornettaTranscriptionSettings")
            if !window.setFrameUsingName("CornettaTranscriptionSettings") { window.center() }
            self.window = window
            if languageObserver == nil {
                languageObserver = NotificationCenter.default.addObserver(
                    forName: .cornettaLanguageChanged, object: nil, queue: .main
                ) { _ in
                    MainActor.assumeIsolated {
                        TranscriptionSettingsWindow.window?.title = tr(.transcriptionSettingsWindow)
                    }
                }
            }
        }
        guard let window else { return }
        if !window.isVisible {
            let hosting = NSHostingView(rootView: TranscriptionSettingsView().localizedRoot())
            window.contentView = hosting
            window.setContentSize(hosting.fittingSize)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        startFitTimer()
    }

    /// The provider view grows when diarization is enabled and shrinks for
    /// Apple Speech. Keep the window fitted instead of relying on an old
    /// autosaved frame.
    private static func startFitTimer() {
        fitTimer?.invalidate()
        fitTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in
                guard let window, window.isVisible, let content = window.contentView else {
                    fitTimer?.invalidate()
                    fitTimer = nil
                    return
                }
                content.layoutSubtreeIfNeeded()
                let fitted = content.fittingSize
                guard fitted.width > 1, fitted.height > 1 else { return }
                if abs(window.frame.width - fitted.width) > 0.5
                    || abs(window.frame.height - fitted.height) > 0.5 {
                    window.setContentSize(fitted)
                }
            }
        }
    }
}
