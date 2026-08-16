import SwiftUI

struct SettingsPlaceholderView: View {
    @StateObject private var launchAtLogin = LaunchAtLoginService()

    var body: some View {
        Form {
            LabeledContent("settings.project") {
                Text(AppMetadata.displayName)
            }
            LabeledContent("settings.minimumOS") {
                Text("macOS \(AppMetadata.minimumMacOSMajorVersion)+")
            }
            Toggle("로그인 시 실행", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { enabled in launchAtLogin.setEnabled(enabled) }
            ))
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460, height: 260)
    }
}
