import Charts
import SwiftUI

struct TrendsView: View {
    let snapshots: [ProviderSnapshot]
    let historyRevision: Int
    var onShowDataSources: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(QuotaPreferenceKey.theme) private var theme = QuotaVisualTheme.system
    @State private var range = TrendRange.day
    @State private var selectedProvider: ProviderID?
    @State private var selectedDate: Date?
    @State private var models: TrendModels

    init(
        snapshots: [ProviderSnapshot],
        historyRevision: Int = 0,
        onShowDataSources: @escaping () -> Void = {}
    ) {
        self.snapshots = snapshots
        self.historyRevision = historyRevision
        self.onShowDataSources = onShowDataSources
        let provider = TrendPresentation.suggestedProvider(snapshots: snapshots)
        _selectedProvider = State(initialValue: provider)
        _models = State(initialValue: Self.makeModels(snapshots: snapshots, range: .day, provider: provider))
    }

    private var palette: BeaconPalette {
        BeaconPalette.resolve(theme: theme, colorScheme: colorScheme)
    }

    private var chartModel: TrendChartModel {
        models.selected
    }

    private var allProviderModel: TrendChartModel {
        models.all
    }

    private var availableProviders: [ProviderID] {
        let providers = allProviderModel.providers
        return providers.isEmpty ? ProviderID.allCases : providers
    }

    private var earliestPaceSeries: TrendWindowSeries? {
        allProviderModel.series
            .filter { $0.paceEstimate != nil }
            .min {
                ($0.paceEstimate?.exhaustionAt ?? .distantFuture)
                    < ($1.paceEstimate?.exhaustionAt ?? .distantFuture)
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                controls

                if selectedProvider == nil {
                    allProviderCharts
                } else if chartModel.series.isEmpty {
                    emptyQuotaState
                } else {
                    summaryStrip
                    detailedChart
                }

                localUsageState
            }
            .padding(20)
        }
        .background(palette.canvas)
        .accessibilityIdentifier("dashboard.trends")
        .onChange(of: range) { _, _ in
            selectedDate = nil
            rebuildModels()
        }
        .onChange(of: selectedProvider) { _, _ in
            selectedDate = nil
            rebuildModels()
        }
        .onChange(of: historyRevision) { _, _ in rebuildModels() }
        .onChange(of: availableProviders) { _, providers in
            if let selectedProvider, !providers.contains(selectedProvider) {
                self.selectedProvider = TrendPresentation.suggestedProvider(snapshots: snapshots)
            }
        }
    }

    private static func makeModels(
        snapshots: [ProviderSnapshot],
        range: TrendRange,
        provider: ProviderID?
    ) -> TrendModels {
        TrendModels(
            selected: TrendPresentation.makeModel(snapshots: snapshots, range: range, provider: provider),
            all: TrendPresentation.makeModel(snapshots: snapshots, range: range, provider: nil)
        )
    }

    private func rebuildModels() {
        models = Self.makeModels(snapshots: snapshots, range: range, provider: selectedProvider)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("RESET BANDS")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(palette.accent)
                Text("추세")
                    .font(.largeTitle.bold())
                    .foregroundStyle(palette.primaryText)
                    .accessibilityIdentifier("dashboard.trends.title")
                coverageLabel
            }
            Spacer(minLength: 8)
            Picker("기간", selection: $range) {
                ForEach(TrendRange.allCases) { item in Text(item.label).tag(item) }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            .accessibilityIdentifier("trends.range")
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Text("Provider")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 64, alignment: .leading)
                .accessibilityIdentifier("trends.provider.label")
            Picker("Provider", selection: $selectedProvider) {
                Text("전체").tag(Optional<ProviderID>.none)
                ForEach(availableProviders) { provider in
                    Text(provider.beaconShortName).tag(Optional(provider))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("추세 Provider")
            .accessibilityIdentifier("trends.provider")
            .frame(minWidth: 360, idealWidth: 420, maxWidth: 480)
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
    }

    private var coverageLabel: some View {
        Label(
            TrendPresentation.coverageText(chartModel.coverage, range: range),
            systemImage: chartModel.coverage == nil ? "clock.badge.questionmark" : "waveform.path.ecg"
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(palette.secondaryText)
        .accessibilityIdentifier("trends.coverage")
    }

    @ViewBuilder
    private var summaryStrip: some View {
        if let series = chartModel.primarySeries {
            BeaconSurface(palette: palette) {
                HStack(spacing: 0) {
                    summaryMetric(
                        title: "\(series.key.label) 현재",
                        value: QuotaPresentation.percentText(series.latest.remaining),
                        symbol: "gauge.with.dots.needle.50percent",
                        tint: trendColor(for: series.latest.remaining)
                    )
                    Divider().frame(height: 42)
                    summaryMetric(
                        title: "변화",
                        value: TrendPresentation.percentPerHourText(series.ratePerHour),
                        symbol: "arrow.down.right",
                        tint: series.ratePerHour == nil ? palette.secondaryText : AppTheme.warning
                    )
                    Divider().frame(height: 42)
                    summaryMetric(
                        title: "리셋",
                        value: QuotaPresentation.resetText(for: series.currentReset, style: .relative),
                        symbol: "clock.arrow.circlepath",
                        tint: palette.primaryText
                    )
                }
            }
            .accessibilityIdentifier("trends.summary")
        }
    }

    private var detailedChart: some View {
        BeaconSurface(palette: palette) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(selectedProvider?.beaconShortName ?? "Quota") 잔여 추세")
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                    Spacer()
                    Text("선은 관측 구간만 연결")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }

                seriesStatusStrip(chartModel.series)

                TrendLineChart(
                    series: chartModel.series,
                    resetEvents: chartModel.resetEvents,
                    range: range,
                    domainStart: chartModel.domainStart,
                    domainEnd: chartModel.domainEnd,
                    palette: palette,
                    compact: false,
                    selectedDate: $selectedDate
                )
                .frame(minHeight: 300)
                .accessibilityIdentifier("trends.chart")

                Divider().overlay(palette.border)

                HStack(spacing: 14) {
                    Label("실선 LIVE", systemImage: "line.diagonal")
                    Label("점선 캐시", systemImage: "ellipsis")
                    Spacer()
                    if let pace = chartModel.primarySeries?.paceEstimate {
                        Label(
                            "예상 소진 \(pace.exhaustionAt.formatted(date: .omitted, time: .shortened)) · \(pace.samples)개 표본",
                            systemImage: "speedometer"
                        )
                    } else if let primary = chartModel.primarySeries,
                              primary.paceSampleCount >= 3,
                              let rate = primary.ratePerHour,
                              rate < 0,
                              primary.currentReset != nil {
                        Label("현재 속도면 리셋 전 소진 없음", systemImage: "checkmark.circle")
                    } else if let primary = chartModel.primarySeries,
                              primary.paceSampleCount >= 3,
                              let rate = primary.ratePerHour,
                              rate >= 0 {
                        Label("잔여량 감소가 없어 예측하지 않음", systemImage: "equal.circle")
                    } else {
                        Label(
                            "소진 예측은 fresh 3개 표본부터 · 현재 \(chartModel.primarySeries?.paceSampleCount ?? 0)개",
                            systemImage: "speedometer"
                        )
                    }
                }
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private var allProviderCharts: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("전체 Provider 비교")
                    .font(.headline)
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Text("각 Provider는 독립 축으로 표시")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            if let earliest = earliestPaceSeries, let pace = earliest.paceEstimate {
                Label(
                    "가장 이른 예상 소진 · \(earliest.key.provider.beaconShortName) \(earliest.key.label) · \(pace.exhaustionAt.formatted(date: .omitted, time: .shortened))",
                    systemImage: "speedometer"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.warning)
                .accessibilityIdentifier("trends.all.earliestPace")
            }

            ForEach(availableProviders) { provider in
                let providerSeries = allProviderModel.series(for: provider)
                if !providerSeries.isEmpty {
                    BeaconSurface(palette: palette) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 9) {
                                ProviderMark(provider: provider, size: 27)
                                Text(provider.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(palette.primaryText)
                                Spacer()
                                if let urgent = providerSeries.min(by: { $0.latest.remaining < $1.latest.remaining }) {
                                    Text("최저 \(QuotaPresentation.percentText(urgent.latest.remaining))")
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(trendColor(for: urgent.latest.remaining))
                                }
                            }
                            seriesStatusStrip(providerSeries)
                            TrendLineChart(
                                series: providerSeries,
                                resetEvents: allProviderModel.resetEvents,
                                range: range,
                                domainStart: allProviderModel.domainStart,
                                domainEnd: allProviderModel.domainEnd,
                                palette: palette,
                                compact: true,
                                selectedDate: .constant(nil)
                            )
                            .frame(height: 150)
                            .accessibilityIdentifier("trends.mini.\(provider.rawValue)")
                        }
                    }
                }
            }

            if allProviderModel.series.isEmpty { emptyQuotaState }
        }
    }

    private var emptyQuotaState: some View {
        BeaconSurface(palette: palette) {
            ContentUnavailableView(
                "선으로 연결할 표본이 없습니다",
                systemImage: "chart.xyaxis.line",
                description: Text("새로고침 후 같은 quota window의 관측값이 2개 이상 쌓이면 방향이 표시됩니다.")
            )
            .frame(maxWidth: .infinity, minHeight: 170)
            .foregroundStyle(palette.secondaryText)
            .accessibilityIdentifier("trends.empty")
        }
    }

    private var localUsageState: some View {
        BeaconSurface(palette: palette) {
            HStack(spacing: 14) {
                Image(systemName: "externaldrive.badge.questionmark")
                    .font(.title2)
                    .foregroundStyle(palette.accent)
                    .frame(width: 36, height: 36)
                    .background(palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("로컬 token 추세는 아직 연결되지 않았습니다.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    Text("데이터를 만들지 않고, 지원되는 local usage source가 연결될 때 별도 그래프로 표시합니다.")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
                Button("데이터 소스 확인", action: onShowDataSources)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("trends.openDataSources")
            }
        }
    }

    private func summaryMetric(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func seriesStatusStrip(_ series: [TrendWindowSeries]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { statusItems(series) }
            VStack(alignment: .leading, spacing: 6) { statusItems(series) }
        }
    }

    @ViewBuilder
    private func statusItems(_ series: [TrendWindowSeries]) -> some View {
        ForEach(series) { item in
            HStack(spacing: 6) {
                Circle().fill(trendColor(for: item.latest.remaining)).frame(width: 7, height: 7)
                Text(item.key.label)
                Text(QuotaPresentation.percentText(item.latest.remaining))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .foregroundStyle(palette.secondaryText)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.key.label) 잔여량 \(QuotaPresentation.percentText(item.latest.remaining))")
        }
    }

    private func trendColor(for remaining: Double) -> Color {
        switch QuotaPresentation.urgency(forRemaining: remaining) {
        case .healthy: AppTheme.cyan
        case .warning: AppTheme.warning
        case .critical: AppTheme.danger
        }
    }
}

private struct TrendModels {
    let selected: TrendChartModel
    let all: TrendChartModel
}

private struct TrendLineChart: View {
    let series: [TrendWindowSeries]
    let resetEvents: [Date]
    let range: TrendRange
    let domainStart: Date
    let domainEnd: Date
    let palette: BeaconPalette
    let compact: Bool
    @Binding var selectedDate: Date?

    var body: some View {
        Chart {
            thresholdMarks
            resetMarks
            seriesMarks
            selectionMark
        }
        .chartXScale(domain: domainStart ... domainEnd)
        .chartXScale(range: .plotDimension(startPadding: compact ? 5 : 10, endPadding: compact ? 8 : 20))
        .chartYScale(domain: 0 ... 1)
        .chartLegend(.hidden)
        .chartXAxis { xAxis }
        .chartYAxis { yAxis }
        .chartXSelection(value: compact ? .constant(nil) : $selectedDate)
        .chartPlotStyle { plot in
            plot
                .background(palette.elevatedSurface.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityLabel("quota 잔여량 추세 그래프")
    }

    @ChartContentBuilder
    private var thresholdMarks: some ChartContent {
        RuleMark(y: .value("주의", 0.25))
            .foregroundStyle(AppTheme.warning.opacity(0.58))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .annotation(position: .top, alignment: .leading, spacing: 2) {
                if !compact {
                    Text("주의 25%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.warning)
                }
            }
        RuleMark(y: .value("위험", 0.10))
            .foregroundStyle(AppTheme.danger.opacity(0.62))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .annotation(position: .top, alignment: .leading, spacing: 2) {
                if !compact {
                    Text("위험 10%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.danger)
                }
            }
    }

    @ChartContentBuilder
    private var resetMarks: some ChartContent {
        ForEach(resetEvents, id: \.self) { reset in
            RectangleMark(
                xStart: .value("Reset 시작", reset.addingTimeInterval(-range.resetBandHalfWidth)),
                xEnd: .value("Reset 끝", reset.addingTimeInterval(range.resetBandHalfWidth)),
                yStart: .value("최소", 0),
                yEnd: .value("최대", 1)
            )
            .foregroundStyle(palette.secondaryText.opacity(0.08))
            RuleMark(x: .value("Reset", reset))
                .foregroundStyle(palette.secondaryText.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    if !compact, resetEvents.count <= 6 {
                        Text("리셋")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.secondaryText)
                    }
                }
        }
    }

    @ChartContentBuilder
    private var seriesMarks: some ChartContent {
        ForEach(series) { item in
            ForEach(item.segments) { segment in
                if item.id == series.first?.id, segment.id == item.segments.last?.id {
                    ForEach(segment.points) { point in
                        AreaMark(
                            x: .value("시각", point.date),
                            yStart: .value("기준", 0),
                            yEnd: .value("잔여량", point.remaining)
                        )
                        .foregroundStyle(color(for: item).opacity(compact ? 0.025 : 0.055))
                        .interpolationMethod(.linear)
                    }
                }

                ForEach(segment.points) { point in
                    LineMark(
                        x: .value("시각", point.date),
                        y: .value("잔여량", point.remaining),
                        series: .value("Series", segment.id)
                    )
                    .foregroundStyle(color(for: item))
                    .lineStyle(StrokeStyle(
                        lineWidth: compact ? 1.6 : 2.1,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: segment.freshnessStyle == .cached ? [5, 4] : []
                    ))
                    .interpolationMethod(.linear)
                    .opacity(segment.freshnessStyle == .cached ? 0.50 : 0.96)
                }
            }

            PointMark(
                x: .value("최근 시각", item.latest.date),
                y: .value("최근 잔여량", item.latest.remaining)
            )
            .foregroundStyle(color(for: item))
            .symbolSize(compact ? 22 : 48)
            .accessibilityLabel(
                "\(item.key.label), 잔여량 \(QuotaPresentation.percentText(item.latest.remaining)), \(item.latest.freshness.label)"
            )
        }
    }

    @ChartContentBuilder
    private var selectionMark: some ChartContent {
        if let selectedDate, !compact {
            RuleMark(x: .value("선택 시각", selectedDate))
                .foregroundStyle(palette.primaryText.opacity(0.50))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, alignment: .leading, spacing: 6) {
                    selectionCard(at: selectedDate)
                }
        }
    }

    private var xAxis: some AxisContent {
        AxisMarks(values: xAxisDates) { value in
            AxisGridLine().foregroundStyle(palette.border)
            AxisTick().foregroundStyle(palette.secondaryText.opacity(0.55))
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(axisText(date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
    }

    private var xAxisDates: [Date] {
        let count = compact ? 3 : 4
        let duration = domainEnd.timeIntervalSince(domainStart)
        guard duration > 0 else { return [] }
        // Keep labels away from the plot boundaries so localized time strings never
        // collapse to an ellipsis at the trailing edge.
        return (1 ... count).map { index in
            domainStart.addingTimeInterval(duration * Double(index) / Double(count + 1))
        }
    }

    private var yAxis: some AxisContent {
        AxisMarks(
            position: .leading,
            values: compact ? [0.0, 0.5, 1.0] : [0.0, 0.10, 0.25, 0.5, 0.75, 1.0]
        ) { value in
            AxisGridLine().foregroundStyle(palette.border)
            AxisValueLabel {
                if let ratio = value.as(Double.self) {
                    Text(QuotaPresentation.percentText(ratio))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
    }

    private func color(for item: TrendWindowSeries) -> Color {
        switch QuotaPresentation.urgency(forRemaining: item.latest.remaining) {
        case .healthy: AppTheme.cyan
        case .warning: AppTheme.warning
        case .critical: AppTheme.danger
        }
    }

    private func axisText(_ date: Date) -> String {
        switch range {
        case .day: date.formatted(.dateTime.hour().minute())
        case .week, .month: date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func nearestPoint(in item: TrendWindowSeries, to date: Date) -> TrendPoint? {
        item.segments.flatMap(\.points).min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func selectionCard(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2.monospacedDigit().weight(.semibold))
            ForEach(series) { item in
                if let point = nearestPoint(in: item, to: date) {
                    HStack(spacing: 6) {
                        Circle().fill(color(for: item)).frame(width: 6, height: 6)
                        Text(item.key.label)
                        Spacer(minLength: 8)
                        Text(QuotaPresentation.percentText(point.remaining)).monospacedDigit()
                    }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(palette.primaryText)
        .padding(8)
        .frame(minWidth: 126)
        .background(palette.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border) }
    }
}
