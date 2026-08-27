import SwiftUI

@MainActor
final class DashboardChromeModel: ObservableObject {
    @Published var isSidebarVisible = true
    @Published var selection = DashboardSection.overview

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }
}

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
    @ObservedObject var chrome: DashboardChromeModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(QuotaPreferenceKey.theme) private var theme = QuotaVisualTheme.system

    private var palette: BeaconPalette {
        BeaconPalette.resolve(theme: theme, colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            if chrome.isSidebarVisible {
                sidebar
                    .frame(width: 210)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            detailColumn
        }
        .animation(.easeInOut(duration: 0.18), value: chrome.isSidebarVisible)
        .frame(minWidth: 760, minHeight: 520)
        .preferredColorScheme(theme.preferredColorScheme)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(DashboardSection.allCases, selection: $chrome.selection) { section in
                DashboardSidebarLabel(title: section.label, symbol: section.symbol)
                    .tag(section)
            }

            Divider()

            VStack(spacing: 8) {
                Button {
                    chrome.selection = .connections
                } label: {
                    DashboardSidebarLabel(title: "Provider 연결", symbol: "link.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .help("Codex, Claude, Grok, Gemini, GLM 연결 설정")
                .accessibilityIdentifier("dashboard.openConnections")

                Button {
                    Task { await model.refreshManually() }
                } label: {
                    DashboardSidebarLabel(title: "새로고침", symbol: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(model.isRefreshing)
                .accessibilityIdentifier("dashboard.refresh")
            }
            .buttonStyle(.bordered)
            .padding(12)
        }
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(chrome.selection.label)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detail: some View {
        switch chrome.selection {
        case .overview: OverviewView(model: model)
        case .connections: ProviderConnectionsView(model: model)
        case .limits: LimitsView(snapshots: model.snapshots)
        case .trends:
            TrendsView(
                snapshots: model.history.isEmpty ? model.snapshots : model.history,
                onShowDataSources: { chrome.selection = .dataSources }
            )
        case .dataSources: DataSourcesView(snapshots: model.snapshots)
        case .settings: DashboardSettingsView(model: model)
        }
    }
}

private struct DashboardSidebarLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.monochrome)
                .frame(width: 17, height: 17, alignment: .center)
                .frame(width: 22, height: 22, alignment: .center)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
        }
        .frame(minHeight: 22)
    }
}

struct OverviewView: View {
    @ObservedObject var model: QuotaMonitorModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(QuotaPreferenceKey.metricMode) private var metricMode = QuotaMetricMode.remaining
    @AppStorage(QuotaPreferenceKey.resetStyle) private var resetStyle = QuotaResetStyle.relative
    @AppStorage(QuotaPreferenceKey.theme) private var theme = QuotaVisualTheme.system

    private var palette: BeaconPalette {
        BeaconPalette.resolve(theme: theme, colorScheme: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signal Ledger").font(.caption.weight(.bold)).foregroundStyle(AppTheme.accentColor)
                    Text("AI quota 현황")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .accessibilityIdentifier("dashboard.overview.title")
                    Text("구독 한도와 로컬 사용량을 섞지 않고 출처별로 보여줍니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    metric("연결됨", value: "\(model.connectedCount)", symbol: "link")
                    metric("가까운 리셋", value: nearestReset, symbol: "clock.arrow.circlepath")
                    metric("오류", value: "\(model.errorCount)", symbol: "exclamationmark.triangle")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("모든 Provider")
                        .font(.headline)
                        .accessibilityIdentifier("overview.provider.grid.title")
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                        spacing: 12
                    ) {
                        ForEach(model.snapshots) { snapshot in
                            OverviewProviderCard(
                                snapshot: snapshot,
                                metricMode: metricMode,
                                resetStyle: resetStyle,
                                palette: palette
                            )
                        }
                    }
                }
                .accessibilityIdentifier("overview.provider.grid")
            }
            .padding(18)
        }
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                Text(value)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.accent)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(palette.elevatedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.border)
        }
    }

    private var nearestReset: String {
        let date = model.snapshots.flatMap(\.windows).compactMap(\.resetsAt).filter { $0 > Date() }.min()
        return date?.formatted(date: .omitted, time: .shortened) ?? "—"
    }
}
