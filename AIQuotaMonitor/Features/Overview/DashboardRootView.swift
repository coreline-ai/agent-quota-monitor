import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case connections
    case limits
    case trends
    case dataSources
    case settings

    var id: String { rawValue }
    var label: String {
        switch self {
        case .overview: "개요"
        case .connections: "연결"
        case .limits: "한도"
        case .trends: "추세"
        case .dataSources: "데이터 소스"
        case .settings: "설정"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .connections: "link.badge.plus"
        case .limits: "gauge.with.dots.needle.50percent"
        case .trends: "chart.xyaxis.line"
        case .dataSources: "externaldrive.connected.to.line.below"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct DashboardRootView: View {
    @ObservedObject var model: QuotaMonitorModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(QuotaPreferenceKey.theme) private var theme = QuotaVisualTheme.system
    @State private var selection = DashboardSection.overview

    private var palette: BeaconPalette {
        BeaconPalette.resolve(theme: theme, colorScheme: colorScheme)
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(DashboardSection.allCases, selection: $selection) { section in
                    Label(section.label, systemImage: section.symbol).tag(section)
                }

                Divider()

                VStack(spacing: 8) {
                    Button {
                        selection = .connections
                    } label: {
                        Label("Provider 연결", systemImage: "link.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .help("Codex, Claude, Grok, Gemini, GLM 연결 설정")
                    .accessibilityIdentifier("dashboard.openConnections")

                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("새로고침", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(model.isRefreshing)
                    .accessibilityIdentifier("dashboard.refresh")
                }
                .buttonStyle(.bordered)
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(selection.label)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 46)
                .foregroundStyle(palette.primaryText)
                .background(palette.canvas)
                .zIndex(1)

                Divider()

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        LinearGradient(
                            colors: [palette.canvas, palette.accent.opacity(0.065)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .clipped()
                    .zIndex(0)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .preferredColorScheme(theme.preferredColorScheme)
        .accessibilityIdentifier("dashboard.root")
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .overview: OverviewView(model: model)
        case .connections: ProviderConnectionsView(model: model)
        case .limits: LimitsView(snapshots: model.snapshots)
        case .trends:
            TrendsView(
                snapshots: model.history.isEmpty ? model.snapshots : model.history,
                onShowDataSources: { selection = .dataSources }
            )
        case .dataSources: DataSourcesView(snapshots: model.snapshots)
        case .settings: DashboardSettingsView(model: model)
        }
    }
}

struct OverviewView: View {
    @ObservedObject var model: QuotaMonitorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Signal Ledger").font(.caption.weight(.bold)).foregroundStyle(AppTheme.accentColor)
                    Text("AI quota 현황")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .accessibilityIdentifier("dashboard.overview.title")
                    Text("구독 한도와 로컬 사용량을 섞지 않고 출처별로 보여줍니다.")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    metric("연결됨", value: "\(model.connectedCount)", symbol: "link")
                    metric("가까운 리셋", value: nearestReset, symbol: "clock.arrow.circlepath")
                    metric("오류", value: "\(model.errorCount)", symbol: "exclamationmark.triangle")
                }

                SignalPanel(title: "Provider 신호") {
                    VStack(spacing: 0) {
                        ForEach(model.snapshots) { snapshot in
                            HStack(spacing: 12) {
                                Circle().fill(snapshot.state.tint).frame(width: 8, height: 8)
                                Text(snapshot.provider.displayName).fontWeight(.medium)
                                Spacer()
                                ProviderStateBadge(state: snapshot.state)
                            }
                            .padding(.vertical, 10)
                            if snapshot.provider != model.snapshots.last?.provider { Divider() }
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        SignalPanel(title: title) {
            HStack {
                Text(value).font(.system(size: 28, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: symbol).foregroundStyle(AppTheme.accentColor)
            }
        }
    }

    private var nearestReset: String {
        let date = model.snapshots.flatMap(\.windows).compactMap(\.resetsAt).filter { $0 > Date() }.min()
        return date?.formatted(date: .omitted, time: .shortened) ?? "—"
    }
}
