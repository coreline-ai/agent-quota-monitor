import SwiftUI

struct LimitsView: View {
    let snapshots: [ProviderSnapshot]

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(QuotaPreferenceKey.metricMode) private var metricMode = QuotaMetricMode.remaining
    @AppStorage(QuotaPreferenceKey.resetStyle) private var resetStyle = QuotaResetStyle.relative
    @AppStorage(QuotaPreferenceKey.theme) private var theme = QuotaVisualTheme.system

    private var palette: BeaconPalette {
        BeaconPalette.resolve(theme: theme, colorScheme: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("BEACON LEDGER")
                            .font(.caption2.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(palette.accent)
                        Text("한도 원장")
                            .font(.largeTitle.bold())
                            .foregroundStyle(palette.primaryText)
                            .accessibilityIdentifier("dashboard.limits.title")
                        Text("잔여 위험도, reset, 계약 등급과 관측 시각을 한 흐름으로 확인합니다.")
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    BeaconLegend(palette: palette)
                }

                ForEach(snapshots) { snapshot in
                    ProviderLimitPanel(
                        snapshot: snapshot,
                        metricMode: metricMode,
                        resetStyle: resetStyle,
                        palette: palette
                    )
                }
            }
            .padding(28)
        }
        .background(palette.canvas)
        .accessibilityIdentifier("dashboard.limits")
    }
}

private struct ProviderLimitPanel: View {
    let snapshot: ProviderSnapshot
    let metricMode: QuotaMetricMode
    let resetStyle: QuotaResetStyle
    let palette: BeaconPalette

    var body: some View {
        BeaconSurface(palette: palette) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 11) {
                    Capsule()
                        .fill(snapshot.provider.beaconTint)
                        .frame(width: 3, height: 30)
                        .shadow(color: snapshot.provider.beaconTint.opacity(0.35), radius: 4)
                    ProviderMark(provider: snapshot.provider, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.provider.displayName)
                            .font(.headline)
                            .foregroundStyle(palette.primaryText)
                        Text(lastSuccessText)
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    ProviderStateBadge(state: snapshot.state)
                }

                if snapshot.windows.isEmpty {
                    ContentUnavailableView(
                        "확정된 quota 없음",
                        systemImage: "gauge.with.dots.needle.0percent",
                        description: Text(emptyDescription)
                    )
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .foregroundStyle(palette.secondaryText)
                } else {
                    Divider().overlay(palette.border)
                    ForEach(snapshot.windows) { window in
                        BeaconQuotaBar(
                            window: window,
                            metricMode: metricMode,
                            resetStyle: resetStyle,
                            palette: palette,
                            showProvenance: true
                        )
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .accessibilityIdentifier("limits.provider.\(snapshot.provider.rawValue)")
    }

    private var lastSuccessText: String {
        guard let date = snapshot.lastSuccessAt else { return "정상 수집 기록 없음" }
        return "마지막 정상 수집 \(date.formatted(date: .omitted, time: .shortened))"
    }

    private var emptyDescription: String {
        switch snapshot.state {
        case .notConfigured: "연결 화면에서 읽기 전용 수집을 승인하면 표시됩니다."
        case .unsupportedContract: "안전한 독립 machine contract가 확정되지 않았습니다."
        default: "현재 출처가 확인된 quota window가 없습니다."
        }
    }
}
