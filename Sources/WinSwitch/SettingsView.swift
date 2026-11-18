import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let openAccessibilitySettings: () -> Void

    var body: some View {
        Form {
            LabeledContent("Shortcut") {
                Button(settings.isRecording ? "Press shortcut…" : settings.shortcut.display) {
                    settings.note = nil
                    settings.isRecording.toggle()
                }
                .frame(minWidth: 110)
                .disabled(!settings.accessibilityGranted)
            }
            if let note = settings.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Only windows on current desktop", isOn: $settings.currentDesktopOnly)
            Toggle("Start at login", isOn: $settings.launchAtLogin)
            LabeledContent("Accessibility") {
                if settings.accessibilityGranted {
                    Text("Granted ✓").foregroundStyle(.secondary)
                } else {
                    Button("Open System Settings", action: openAccessibilitySettings)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
    }
}
