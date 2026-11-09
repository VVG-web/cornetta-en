import CornettaCore
import SwiftUI

/// Per-provider server diarization options. The microphone track never uses
/// these labels: only the system-audio track is sent with diarization enabled.
struct DiarizationSettingsView: View {
    let onSave: (DiarizationSettings) -> Void

    @State private var enabled: Bool
    @State private var timeoutSeconds: Int
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    init(settings: DiarizationSettings, onSave: @escaping (DiarizationSettings) -> Void) {
        self.onSave = onSave
        let settings = settings.normalized
        _enabled = State(initialValue: settings.enabled)
        _timeoutSeconds = State(initialValue: settings.timeoutSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text(.transcriptionSettingsDiarizationTitle, language: language))
                .font(.title3.weight(.semibold))

            Toggle(L10n.text(.transcriptionSettingsDiarizationEnabled, language: language),
                   isOn: $enabled)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(L10n.text(.transcriptionSettingsDiarizationTimeout, language: language))
                    HStack(spacing: 8) {
                        TextField(L10n.text(.transcriptionSettingsDiarizationTimeoutPlaceholder,
                                            language: language),
                                  value: $timeoutSeconds, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Stepper("", value: $timeoutSeconds, in: 60...3_600)
                            .labelsHidden()
                    }
                    .disabled(!enabled)
                }
            }

            Text(L10n.text(.transcriptionSettingsDiarizationTimeoutHelp, language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.text(.transcriptionSettingsDiarizationNote, language: language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(L10n.text(.commonCancel, language: language)) { dismiss() }
                Button(L10n.text(.commonSave, language: language)) {
                    onSave(DiarizationSettings(enabled: enabled,
                                               timeoutSeconds: timeoutSeconds).normalized)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}
