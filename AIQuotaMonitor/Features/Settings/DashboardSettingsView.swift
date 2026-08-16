import SwiftUI

struct DashboardSettingsView: View {
    @ObservedObject var model: QuotaMonitorModel
    @StateObject private var launchAtLogin = LaunchAtLoginService()
    @AppStorage("refresh.minutes") private var refreshMinutes = 5
    @AppStorage("notifications.enabled") private var notificationsEnabled = true
    @AppStorage("quietHours.enabled") private var quietHoursEnabled = false
    @State private var zaiKey = ""
    @State private var keyStatus = "저장 안 됨"
    @State private var notificationStatus = "권한 미확인"
    @State private var historyStatus = ""
    private let keychain = KeychainStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("설정").font(.largeTitle.bold()).accessibilityIdentifier("dashboard.settings.title")
                SignalPanel(title: "일반") {
                    Toggle("로그인 시 실행", isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { enabled in launchAtLogin.setEnabled(enabled) }
                    ))
                    Picker("기본 새로고침", selection: $refreshMinutes) {
                        Text("1분").tag(1); Text("5분").tag(5); Text("15분").tag(15)
                    }
                    Toggle("알림", isOn: $notificationsEnabled)
                    Toggle("조용한 시간", isOn: $quietHoursEnabled)
                    HStack {
                        Button("알림 권한 요청") {
                            Task {
                                notificationStatus = await model.requestNotificationPermission() ? "허용됨" : "허용되지 않음"
                            }
                        }
                        Text(notificationStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = launchAtLogin.lastError {
                        Text(error).font(.caption).foregroundStyle(AppTheme.danger)
                    }
                }

                SignalPanel(title: "Provider 연결") {
                    Label("왼쪽 사이드바의 ‘연결’에서 Codex·Claude·Grok을 관리합니다.", systemImage: "link.badge.plus")
                        .foregroundStyle(.secondary)
                }

                SignalPanel(title: "Z.ai 수동 키") {
                    Text("Keychain에만 저장됩니다. Quota 조회 계약이 확정되기 전에는 네트워크 요청에 사용하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField("키 입력", text: $zaiKey)
                    HStack {
                        Button("추가 또는 교체") { replaceKey() }.disabled(zaiKey.isEmpty)
                        Button("삭제", role: .destructive) { deleteKey() }
                        Text(keyStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }

                SignalPanel(title: "데이터 관리") {
                    Button("지금 새로고침") { Task { await model.refresh() } }
                    Button("History 삭제", role: .destructive) {
                        Task { historyStatus = await model.deleteHistory() ? "삭제됨" : "삭제 실패" }
                    }
                    if !historyStatus.isEmpty { Text(historyStatus).font(.caption).foregroundStyle(.secondary) }
                    Text("History는 90일 또는 25 MiB 중 먼저 도달한 기준으로 정리됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .accessibilityIdentifier("dashboard.settings")
    }

    private func replaceKey() {
        let data = Data(zaiKey.utf8)
        zaiKey = ""
        Task {
            do {
                try await keychain.replace(data, account: "zai.manual")
                keyStatus = "Keychain 저장됨"
            } catch {
                keyStatus = "저장 실패"
            }
        }
    }

    private func deleteKey() {
        Task {
            do {
                try await keychain.delete(account: "zai.manual")
                keyStatus = "삭제됨"
            } catch {
                keyStatus = "삭제 실패"
            }
        }
    }
}
