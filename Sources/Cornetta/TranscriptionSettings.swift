import AppKit
import CornettaCore
import SwiftUI

/// Finestra per configurare il servizio HTTP di trascrizione. I valori sono salvati in UserDefaults;
/// l'audio viene inviato solo quando parte una trascrizione.
struct TranscriptionSettingsView: View {
    @AppStorage(TranscriptionPreferences.schemeKey) private var scheme = TranscriptionPreferences.defaultScheme
    @AppStorage(TranscriptionPreferences.hostKey) private var host = TranscriptionPreferences.defaultHost
    @AppStorage(TranscriptionPreferences.portKey) private var port = TranscriptionPreferences.defaultPort
    @AppStorage(TranscriptionPreferences.pathKey) private var path = TranscriptionPreferences.defaultPath
    @AppStorage(TranscriptionPreferences.modelKey) private var model = TranscriptionPreferences.defaultModel
    @AppStorage(TranscriptionPreferences.languageKey)
    private var languageCode = TranscriptionPreferences.defaultLanguage
    @AppStorage(TranscriptionPreferences.autoTranscribeKey) private var autoTranscribe = false

    @Environment(\.appLanguage) private var language

    private var config: TranscriptionConfig {
        TranscriptionConfig(scheme: scheme, host: host, port: port, path: path,
                            model: model, language: languageCode)
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
                    Text(L10n.text(.transcriptionSettingsScheme, language: language))
                    Picker(L10n.text(.transcriptionSettingsScheme, language: language), selection: $scheme) {
                        Text(L10n.text(.transcriptionSettingsHttp, language: language)).tag("http")
                        Text(L10n.text(.transcriptionSettingsHttps, language: language)).tag("https")
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsHost, language: language))
                    TextField(L10n.text(.transcriptionSettingsHostPlaceholder, language: language), text: $host)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                        .accessibilityLabel(L10n.text(.transcriptionSettingsHost, language: language))
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsPort, language: language))
                    TextField(L10n.text(.transcriptionSettingsPortPlaceholder, language: language), text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .help(L10n.text(.transcriptionSettingsPortHelp, language: language))
                        .accessibilityLabel(L10n.text(.transcriptionSettingsPort, language: language))
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsPath, language: language))
                    TextField(L10n.text(.transcriptionSettingsPathPlaceholder, language: language), text: $path)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 360)
                        .font(.system(.body, design: .monospaced))
                        .help(L10n.text(.transcriptionSettingsPathHelp, language: language))
                        .accessibilityLabel(L10n.text(.transcriptionSettingsPath, language: language))
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsModel, language: language))
                    TextField(L10n.text(.transcriptionSettingsModelPlaceholder, language: language), text: $model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                        .accessibilityLabel(L10n.text(.transcriptionSettingsModel, language: language))
                }
                GridRow {
                    Text(L10n.text(.transcriptionSettingsLanguage, language: language))
                    TextField(L10n.text(.transcriptionSettingsLanguagePlaceholder, language: language),
                              text: $languageCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .accessibilityLabel(L10n.text(.transcriptionSettingsLanguage, language: language))
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

            Text(L10n.text(.transcriptionSettingsPrivacy, language: language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(L10n.text(.transcriptionSettingsReset, language: language)) {
                    scheme = TranscriptionPreferences.defaultScheme
                    host = TranscriptionPreferences.defaultHost
                    port = TranscriptionPreferences.defaultPort
                    path = TranscriptionPreferences.defaultPath
                    model = TranscriptionPreferences.defaultModel
                    languageCode = TranscriptionPreferences.defaultLanguage
                }
                Spacer()
                Button(L10n.text(.commonClose, language: language)) {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 580)
        .onChange(of: config) { _, _ in
            NotificationCenter.default.post(name: .cornettaTranscriptionSettingsChanged, object: nil)
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
            let hosting = NSHostingView(rootView: TranscriptionSettingsView().localizedRoot())
            window.contentView = hosting
            window.setContentSize(hosting.fittingSize)
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
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
