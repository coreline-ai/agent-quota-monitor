import Foundation

enum TrendRange: Int, CaseIterable, Identifiable, Sendable {
    case day = 1
    case week = 7
    case month = 30

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .day: "24시간"
        case .week: "7일"
        case .month: "30일"
        }
    }

    func start(relativeTo now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -rawValue, to: now)
            ?? now.addingTimeInterval(-Double(rawValue) * 86_400)
    }

    var bucketInterval: TimeInterval {
        switch self {
        case .day: 15 * 60
        case .week: 2 * 60 * 60
        case .month: 8 * 60 * 60
        }
    }

    var maximumContinuousGap: TimeInterval {
        switch self {
        case .day: 45 * 60
        case .week: 6 * 60 * 60
        case .month: 24 * 60 * 60
        }
    }

    var resetBandHalfWidth: TimeInterval {
        Double(rawValue) * 86_400 / 300
    }
}

enum TrendFreshnessStyle: String, Hashable, Sendable {
    case observed
    case cached

    init(_ freshness: DataFreshness) {
        switch freshness {
        case .live, .recent: self = .observed
        case .stale, .unknown: self = .cached
        }
    }
}

struct TrendWindowKey: Hashable, Identifiable, Sendable {
    let provider: ProviderID
    let kind: QuotaWindowKind

    var id: String { "\(provider.rawValue)|\(kind.trendToken)" }
    var label: String { kind.label }
}

struct TrendPoint: Hashable, Identifiable, Sendable {
    let key: TrendWindowKey
    let windowInstance: String
    let date: Date
    let remaining: Double
    let freshness: DataFreshness
    let source: UsageSource
    let contract: SourceContractKind
    let resetsAt: Date?

    var id: String {
        let observedMilliseconds = Int64((date.timeIntervalSince1970 * 1_000).rounded())
        return "\(key.id)|\(windowInstance)|\(observedMilliseconds)"
    }
}

struct TrendSegment: Identifiable, Sendable {
    let id: String
    let windowInstance: String
    let freshnessStyle: TrendFreshnessStyle
    let points: [TrendPoint]
}

struct TrendWindowSeries: Identifiable, Sendable {
    let key: TrendWindowKey
    let segments: [TrendSegment]
    let latest: TrendPoint
    let ratePerHour: Double?
    let paceEstimate: PaceEstimate?
    let paceSampleCount: Int

    var id: String { key.id }
    var currentReset: Date? { latest.resetsAt }
}

struct TrendCoverage: Equatable, Sendable {
    let start: Date
    let end: Date
    let samples: Int
    let liveSamples: Int

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct TrendChartModel: Sendable {
    let range: TrendRange
    let domainStart: Date
    let domainEnd: Date
    let series: [TrendWindowSeries]
    let coverage: TrendCoverage?
    let resetEvents: [Date]

    var providers: [ProviderID] {
        ProviderID.allCases.filter { provider in series.contains { $0.key.provider == provider } }
    }

    var primarySeries: TrendWindowSeries? {
        series.min { lhs, rhs in
            let left = lhs.key.kind.trendOrder
            let right = rhs.key.kind.trendOrder
            if left != right { return left < right }
            return lhs.latest.remaining < rhs.latest.remaining
        }
    }

    func series(for provider: ProviderID) -> [TrendWindowSeries] {
        series.filter { $0.key.provider == provider }
    }
}

enum TrendPresentation {
    static func makeModel(
        snapshots: [ProviderSnapshot],
        range: TrendRange,
        provider: ProviderID?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TrendChartModel {
        let domainStart = range.start(relativeTo: now, calendar: calendar)
        let rawSamples = snapshots.flatMap { snapshot in
            snapshot.windows.compactMap { window -> TrendSample? in
                guard provider == nil || snapshot.provider == provider,
                      window.provenance.observedAt >= domainStart,
                      window.provenance.observedAt <= now else { return nil }
                return TrendSample(provider: snapshot.provider, window: window)
            }
        }
        let samples = deduplicated(rawSamples)
        let grouped = Dictionary(grouping: samples, by: \.key)

        let series = grouped.map { key, values in
            makeSeries(key: key, samples: values, range: range)
        }
        .sorted(by: seriesSort)

        let points = samples.map(\.point)
        let coverage: TrendCoverage?
        if let first = points.min(by: { $0.date < $1.date }),
           let last = points.max(by: { $0.date < $1.date }) {
            coverage = TrendCoverage(
                start: first.date,
                end: last.date,
                samples: points.count,
                liveSamples: points.filter { $0.freshness == .live }.count
            )
        } else {
            coverage = nil
        }

        let resetEvents = Array(Set(samples.compactMap { sample -> Int64? in
            guard let reset = sample.window.resetsAt,
                  reset >= domainStart,
                  reset <= now else { return nil }
            return canonicalResetMinute(reset)
        }))
        .sorted()
        .map { Date(timeIntervalSince1970: TimeInterval($0 * 60)) }

        return TrendChartModel(
            range: range,
            domainStart: domainStart,
            domainEnd: now,
            series: series,
            coverage: coverage,
            resetEvents: resetEvents
        )
    }

    static func suggestedProvider(
        snapshots: [ProviderSnapshot],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProviderID? {
        let model = makeModel(
            snapshots: snapshots,
            range: .month,
            provider: nil,
            now: now,
            calendar: calendar
        )
        return model.series.min { lhs, rhs in
            if lhs.latest.remaining != rhs.latest.remaining {
                return lhs.latest.remaining < rhs.latest.remaining
            }
            return lhs.key.provider.rawValue < rhs.key.provider.rawValue
        }?.key.provider
    }

    static func percentPerHourText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "계산 대기" }
        let percent = value * 100
        let sign = percent > 0 ? "+" : ""
        return "\(sign)\(percent.formatted(.number.precision(.fractionLength(1))))%/시간"
    }

    static func coverageText(_ coverage: TrendCoverage?, range: TrendRange) -> String {
        guard let coverage else { return "\(range.label) 내 수집 표본 없음" }
        let totalMinutes = max(1, Int(coverage.duration / 60))
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        let duration: String
        if days > 0 {
            duration = hours > 0 ? "\(days)일 \(hours)시간" : "\(days)일"
        } else if hours > 0 {
            duration = minutes > 0 ? "\(hours)시간 \(minutes)분" : "\(hours)시간"
        } else {
            duration = "\(minutes)분"
        }
        return "수집 \(duration) · LIVE \(coverage.liveSamples) / 전체 \(coverage.samples)개 표본"
    }

    static func downsample(_ points: [TrendPoint], bucketInterval: TimeInterval) -> [TrendPoint] {
        guard points.count > 3, bucketInterval > 0 else { return points.sorted { $0.date < $1.date } }
        let grouped = Dictionary(grouping: points) { point in
            Int64(floor(point.date.timeIntervalSince1970 / bucketInterval))
        }
        return grouped.keys.sorted().flatMap { bucket -> [TrendPoint] in
            guard let values = grouped[bucket]?.sorted(by: { $0.date < $1.date }),
                  let first = values.first,
                  let last = values.last,
                  let minimum = values.min(by: { $0.remaining < $1.remaining }) else { return [] }
            var unique: [String: TrendPoint] = [:]
            for point in [first, minimum, last] { unique[point.id] = point }
            return unique.values.sorted { $0.date < $1.date }
        }
    }

    private static func makeSeries(
        key: TrendWindowKey,
        samples: [TrendSample],
        range: TrendRange
    ) -> TrendWindowSeries {
        let sorted = samples.sorted { $0.point.date < $1.point.date }
        var rawSegments: [[TrendSample]] = []
        for sample in sorted {
            guard let previous = rawSegments.last?.last else {
                rawSegments.append([sample])
                continue
            }
            let gap = sample.point.date.timeIntervalSince(previous.point.date)
            let shouldSplit = sample.point.windowInstance != previous.point.windowInstance
                || TrendFreshnessStyle(sample.point.freshness) != TrendFreshnessStyle(previous.point.freshness)
                || gap > range.maximumContinuousGap
            if shouldSplit {
                rawSegments.append([sample])
            } else {
                rawSegments[rawSegments.count - 1].append(sample)
            }
        }

        let segments = rawSegments.enumerated().map { index, values in
            let points = downsample(values.map(\.point), bucketInterval: range.bucketInterval)
            let first = values[0].point
            return TrendSegment(
                id: "\(key.id)|\(first.windowInstance)|\(first.freshness.rawValue)|\(index)",
                windowInstance: first.windowInstance,
                freshnessStyle: TrendFreshnessStyle(first.freshness),
                points: points
            )
        }

        let latestSample = sorted[sorted.count - 1]
        let currentSamples = sorted.filter {
            $0.point.windowInstance == latestSample.point.windowInstance
                && TrendFreshnessStyle($0.point.freshness) == .observed
        }
        let ratePerHour = ratePerHour(from: currentSamples.map(\.point))
        let pace = QuotaAnalytics.estimateExhaustion(from: currentSamples.map(\.window))
        return TrendWindowSeries(
            key: key,
            segments: segments,
            latest: latestSample.point,
            ratePerHour: ratePerHour,
            paceEstimate: pace,
            paceSampleCount: currentSamples.count
        )
    }

    private static func ratePerHour(from points: [TrendPoint]) -> Double? {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        let hours = last.date.timeIntervalSince(first.date) / 3_600
        guard hours > 0 else { return nil }
        return (last.remaining - first.remaining) / hours
    }

    private static func deduplicated(_ samples: [TrendSample]) -> [TrendSample] {
        var values: [String: TrendSample] = [:]
        for sample in samples {
            let id = sample.point.id
            guard let existing = values[id] else {
                values[id] = sample
                continue
            }
            if sample.point.freshness.trendRank > existing.point.freshness.trendRank {
                values[id] = sample
            }
        }
        return Array(values.values)
    }

    private static func seriesSort(_ lhs: TrendWindowSeries, _ rhs: TrendWindowSeries) -> Bool {
        let leftProvider = ProviderID.allCases.firstIndex(of: lhs.key.provider) ?? .max
        let rightProvider = ProviderID.allCases.firstIndex(of: rhs.key.provider) ?? .max
        if leftProvider != rightProvider { return leftProvider < rightProvider }
        if lhs.key.kind.trendOrder != rhs.key.kind.trendOrder {
            return lhs.key.kind.trendOrder < rhs.key.kind.trendOrder
        }
        return lhs.key.label < rhs.key.label
    }

    fileprivate static func windowInstance(for window: QuotaWindow) -> String {
        guard let reset = window.resetsAt else { return "\(window.kind.trendToken)@open" }
        return "\(window.kind.trendToken)@\(canonicalResetMinute(reset))"
    }

    private static func canonicalResetMinute(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 / 60).rounded())
    }
}

private struct TrendSample: Sendable {
    let provider: ProviderID
    let window: QuotaWindow

    var key: TrendWindowKey { TrendWindowKey(provider: provider, kind: window.kind) }
    var point: TrendPoint {
        TrendPoint(
            key: key,
            // Some provider CLIs expose reset countdowns with sub-second jitter. Using the
            // raw timestamp would turn every refresh into a one-point segment, so trend
            // identity intentionally follows the reset minute instead.
            windowInstance: TrendPresentation.windowInstance(for: window),
            date: window.provenance.observedAt,
            remaining: window.remainingRatio,
            freshness: window.provenance.freshness,
            source: window.provenance.source,
            contract: window.provenance.contract,
            resetsAt: window.resetsAt
        )
    }
}

private extension QuotaWindowKind {
    var trendToken: String {
        switch self {
        case .fiveHour: "five-hour"
        case .sevenDay: "seven-day"
        case .primary: "primary"
        case .secondary: "secondary"
        case .sharedWeekly: "shared-weekly"
        case .session: "session"
        case let .custom(value): "custom-\(value)"
        }
    }

    var trendOrder: Int {
        switch self {
        case .fiveHour: 0
        case .session: 1
        case .primary: 2
        case .sevenDay: 3
        case .sharedWeekly: 4
        case .secondary: 5
        case .custom: 6
        }
    }
}

private extension DataFreshness {
    var trendRank: Int {
        switch self {
        case .live: 3
        case .recent: 2
        case .stale: 1
        case .unknown: 0
        }
    }
}
