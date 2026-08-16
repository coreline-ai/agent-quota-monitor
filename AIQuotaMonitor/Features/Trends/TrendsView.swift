import Charts
import SwiftUI

struct TrendsView: View {
    let snapshots: [ProviderSnapshot]
    @State private var range = 7
    @State private var selectedProvider: ProviderID?

    private var points: [QuotaPoint] {
        snapshots
            .filter { selectedProvider == nil || $0.provider == selectedProvider }
            .flatMap { snapshot in
                snapshot.windows.map {
                    QuotaPoint(
                        provider: snapshot.provider,
                        window: $0.kind.label,
                        date: $0.provenance.observedAt,
                        remaining: $0.remainingRatio,
                        freshness: $0.provenance.freshness
                    )
                }
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("추세").font(.largeTitle.bold()).accessibilityIdentifier("dashboard.trends.title")
                        Text("Quota와 로컬 token/예상 비용은 별도 축으로 유지됩니다.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("기간", selection: $range) {
                        Text("7일").tag(7); Text("14일").tag(14); Text("30일").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }

                Picker("Provider", selection: $selectedProvider) {
                    Text("전체").tag(Optional<ProviderID>.none)
                    ForEach(ProviderID.allCases) { Text($0.displayName).tag(Optional($0)) }
                }
                .frame(maxWidth: 260)

                SignalPanel(title: "Quota 잔여율 · \(range)일") {
                    if points.isEmpty {
                        emptyChart("Quota 표본이 아직 없습니다.")
                    } else {
                        Chart(points) { point in
                            PointMark(x: .value("시각", point.date), y: .value("잔여율", point.remaining))
                                .foregroundStyle(by: .value("Provider", point.provider.displayName))
                                .symbol(by: .value("Window", point.window))
                        }
                        .chartYScale(domain: 0 ... 1)
                        .chartYAxis { AxisMarks(format: Decimal.FormatStyle.Percent.percent.scale(100)) }
                        .frame(minHeight: 230)
                    }
                    Text("같은 reset window의 fresh 표본이 3개 미만이면 예상 소진을 계산하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let estimate = paceEstimate {
                        Label(
                            "현재 속도 기준 예상 소진 \(estimate.exhaustionAt.formatted()) · \(estimate.samples)개 표본",
                            systemImage: "speedometer"
                        )
                        .font(.caption.weight(.semibold))
                    }
                }

                SignalPanel(title: "로컬 token · API 정가 예상") {
                    emptyChart("지원되는 로컬 기록을 연결하면 token 추세가 표시됩니다.")
                    Text("API 정가 기준 예상 / 실제 구독 결제액 아님")
                        .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.warning)
                }
            }
            .padding(28)
        }
        .accessibilityIdentifier("dashboard.trends")
    }

    private func emptyChart(_ message: String) -> some View {
        ContentUnavailableView("데이터 없음", systemImage: "chart.xyaxis.line", description: Text(message))
            .frame(maxWidth: .infinity, minHeight: 190)
    }

    private var paceEstimate: PaceEstimate? {
        let windows = snapshots
            .filter { selectedProvider == nil || $0.provider == selectedProvider }
            .flatMap(\.windows)
        let grouped = Dictionary(grouping: windows, by: { "\($0.kind.label)-\($0.resetsAt?.timeIntervalSince1970 ?? 0)" })
        return grouped.values.compactMap { QuotaAnalytics.estimateExhaustion(from: $0) }
            .min { $0.exhaustionAt < $1.exhaustionAt }
    }

    private struct QuotaPoint: Identifiable {
        let id = UUID()
        let provider: ProviderID
        let window: String
        let date: Date
        let remaining: Double
        let freshness: DataFreshness
    }
}
