import SwiftUI

struct DashboardSettingsView: View {
    @ObservedObject var model: QuotaMonitorModel
    @StateObject private var launchAtLogin = LaunchAtLoginService()
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("refresh.minutes") private var refreshMinutes = 5
    @AppStorage("notifications.enabled") private var notificationsEnabled = true
    @AppStorage("quietHours.enabled") private var quietHoursEnabled = false
    @AppStorage(QuotaPreferenceKey.density) private var density = QuotaDensity.balanced
    @AppStorage(QuotaPreferenceKey.metricMode) private var metricMode = QuotaMetricMode.remaining
    @AppStorage(QuotaPreferenceKey.resetStyle) private var resetStyle = QuotaResetStyle.relative
    @AppStorage(QuotaPreferenceKey.theme) private var theme = QuotaVisualTheme.system
    @AppStorage(QuotaPreferenceKey.inspectorMode) private var inspectorMode = QuotaInspectorMode.expanded
    @AppStorage(QuotaPreferenceKey.providerVisible(.claude)) private var showClaude = true
    @AppStorage(QuotaPreferenceKey.providerVisible(.codex)) private var showCodex = true
    @AppStorage(QuotaPreferenceKey.providerVisible(.grok)) private var showGrok = true
    @AppStorage(QuotaPreferenceKey.providerVisible(.zai)) private var showZAI = true
    @State private var notificationStatus = "권한 미확인"
    @State private var historyStatus = ""
    @State private var legacyZAIKeyStatus = ""
    private let keychain = KeychainStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("설정").font(.largeTitle.bold()).accessibilityIdentifier("dashboard.settings.title")
                appearancePanel
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
                    Label("왼쪽 사이드바의 ‘연결’에서 Codex·Claude·Grok·GLM을 관리합니다.", systemImage: "link.badge.plus")
                        .foregroundStyle(.secondary)
                }

                SignalPanel(title: "Z.ai 공식 연결") {
                    Label("수동 키 입력 대신 기존 claude-glm 프로필과 공식 glm-plan-usage 플러그인을 사용합니다.", systemImage: "checkmark.shield")
                        .foregroundStyle(.secondary)
                    Text("연결 승인과 탐지 상태는 왼쪽 사이드바의 ‘연결’에서 확인할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("기존 미사용 수동 키 삭제", role: .destructive) {
                            Task { await deleteLegacyZAIKey() }
                        }
                        if !legacyZAIKeyStatus.isEmpty {
                            Text(legacyZAIKeyStatus).font(.caption).foregroundStyle(.secondary)
                        }
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

    private var appearancePanel: some View {
        let palette = BeaconPalette.resolve(theme: theme, colorScheme: colorScheme)
        return SignalPanel(title: "표시와 밀도") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("화면 밀도").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("화면 밀도", selection: $density) {
                        ForEach(QuotaDensity.allCases) { item in Text(item.label).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("화면 밀도")
                    .accessibilityIdentifier("settings.appearance.density")
                }

                HStack(alignment: .top, spacing: 16) {
                    pickerColumn("수치 기준", selection: $metricMode, items: QuotaMetricMode.allCases)
                        .accessibilityIdentifier("settings.appearance.metric")
                    pickerColumn("리셋 표기", selection: $resetStyle, items: QuotaResetStyle.allCases)
                        .accessibilityIdentifier("settings.appearance.reset")
                    pickerColumn("Inspector", selection: $inspectorMode, items: QuotaInspectorMode.allCases)
                        .accessibilityIdentifier("settings.appearance.inspector")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("색상 테마").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("색상 테마", selection: $theme) {
                        ForEach(QuotaVisualTheme.allCases) { item in Text(item.label).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("색상 테마")
                    .accessibilityIdentifier("settings.appearance.theme")
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("메뉴 막대에 표시").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 18) {
                        providerToggle(.claude, isOn: $showClaude)
                        providerToggle(.codex, isOn: $showCodex)
                        providerToggle(.grok, isOn: $showGrok)
                        providerToggle(.zai, isOn: $showZAI)
                    }
                }

                BeaconSurface(palette: palette) {
                    HStack(spacing: 12) {
                        ProviderMark(provider: .codex, size: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Beacon Ledger")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.primaryText)
                            Text("상태색은 Provider 색과 분리해 잔여 위험도를 나타냅니다.")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                        }
                        Spacer()
                        BeaconLegend(palette: palette)
                    }
                }
            }
        }
    }

    private func pickerColumn<Item: Hashable & Identifiable & RawRepresentable>(
        _ title: String,
        selection: Binding<Item>,
        items: [Item]
    ) -> some View where Item.RawValue == String {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(items) { item in
                    Text(pickerLabel(item)).tag(item)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pickerLabel<Item: RawRepresentable>(_ item: Item) -> String where Item.RawValue == String {
        switch item {
        case let item as QuotaMetricMode: item.label
        case let item as QuotaResetStyle: item.label
        case let item as QuotaInspectorMode: item.label
        default: item.rawValue
        }
    }

    private func providerToggle(_ provider: ProviderID, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                ProviderMark(provider: provider, size: 22)
                Text(provider.beaconShortName)
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("settings.appearance.provider.\(provider.rawValue)")
    }

    private func deleteLegacyZAIKey() async {
        do {
            try await keychain.delete(account: "zai.manual")
            legacyZAIKeyStatus = "삭제됨"
        } catch {
            legacyZAIKeyStatus = "삭제 실패"
        }
    }

}
