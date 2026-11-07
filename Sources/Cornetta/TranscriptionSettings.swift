import AppKit
import CornettaCore
import SwiftUI

/// Finestra per configurare il servizio HTTP di trascrizione. I valori restano in una bozza finché
/// non premi Salva: l'autocompletamento di macOS non può sovrascrivere la configurazione da solo.
struct TranscriptionSettingsView: View {
    @State private var baseURL: String
    @State private var model: String
    @State private var languageCode: String
    @State private var apiKey: String
    @State private var autoTranscribe: Bool
    @State private var saveError: String?
    @State private var checking = false
    @State private var checkResult: ProviderCheckResult?

    @Environment(\.appLanguage) private var language

    init() {
        let config = TranscriptionConfig.stored()
        _baseURL = State(initialValue: config.baseURL)
        _model = State(initialValue: config.model)
        _languageCode = State(initialValue: config.language)
        _apiKey = State(initialValue: TranscriptionCredential.load())
        _autoTranscribe = State(initialValue: UserDefaults.standard.bool(
            forKey: TranscriptionPreferences.autoTranscribeKey))
    }

    private var config: TranscriptionConfig {
        TranscriptionConfig(baseURL: baseURL, model: model, language: languageCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text(.transcriptionSettingsTitle, language: language))
                .font(.title2.weight(.semibold))
            Text(L10n.text(.transcriptionSettingsDescription, language: language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(L10n.text(.transcriptionSettingsAuto, language: language), isOn: $autoTranscribe)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(L10n.text(.transcriptionSettingsBaseURL, language: language))
                    TextField(L10n.text(.transcriptionSettingsBaseURLPlaceholder, language: language),
                              text: $baseURL)
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
                    TextField(L10n.text(.transcriptionSettingsModelPlaceholder, language: language), text: $model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                        .textContentType(nil)
                        .disableAutocorrection(true)
                        .accessibilityLabel(L10n.text(.transcriptionSettingsModel, language: language))
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsLanguage, language: language))
                    TextField(L10n.text(.transcriptionSettingsLanguagePlaceholder, language: language),
                              text: $languageCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .textContentType(nil)
                        .disableAutocorrection(true)
                        .accessibilityLabel(L10n.text(.transcriptionSettingsLanguage, language: language))
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsApiKey, language: language))
                    SecureField(L10n.text(.transcriptionSettingsApiKeyPlaceholder, language: language),
                                text: $apiKey)
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

            Text(config.endpointDescription)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(config.isConfigured ? Color.secondary : Color.red)
                .textSelection(.enabled)

            if !config.isConfigured {
                Text(L10n.text(.transcriptionSettingsInvalid, language: language))
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if let saveError {
                Text(saveError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Text(L10n.text(.transcriptionSettingsPrivacy, language: language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let checkResult {
                Text(checkText(checkResult))
                    .font(.callout)
                    .foregroundStyle(checkColor(checkResult))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(L10n.text(.transcriptionSettingsReset, language: language)) {
                    baseURL = TranscriptionPreferences.defaultBaseURL
                    model = TranscriptionPreferences.defaultModel
                    languageCode = TranscriptionPreferences.defaultLanguage
                    apiKey = ""
                    autoTranscribe = false
                    saveError = nil
                    checkResult = nil
                }
                Button(checking ? L10n.text(.transcriptionSettingsChecking, language: language)
                        : L10n.text(.transcriptionSettingsCheck, language: language)) {
                    check()
                }
                .disabled(checking || !config.isConfigured)
                .help(L10n.text(.transcriptionSettingsCheckHelp, language: language))
                Spacer()
                Button(L10n.text(.commonClose, language: language)) {
                    NSApp.keyWindow?.close()
                }
                Button(L10n.text(.commonSave, language: language)) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!config.isConfigured)
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    private func save() {
        guard config.isConfigured else { return }
        do {
            try TranscriptionCredential.save(apiKey)
            TranscriptionConfig.save(config, autoTranscribe: autoTranscribe)
            NotificationCenter.default.post(name: .cornettaTranscriptionSettingsChanged, object: nil)
            NSApp.keyWindow?.close()
        } catch {
            saveError = L10n.text(.transcriptionSettingsKeychainError, language: language)
        }
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

@MainActor
enum TranscriptionSettingsWindow {
    private static var window: NSWindow?
    private static var languageObserver: NSObjectProtocol?

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
    }
}
