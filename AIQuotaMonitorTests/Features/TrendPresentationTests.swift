import XCTest
@testable import AIQuotaMonitor

final class TrendPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testDayRangeFiltersOldSamplesAndKeepsFixedDomain() throws {
        let snapshots = try [
            snapshot(provider: .claude, kind: .fiveHour, remaining: 0.8, observed: now.addingTimeInterval(-25 * 3_600)),
            snapshot(provider: .claude, kind: .fiveHour, remaining: 0.7, observed: now.addingTimeInterval(-3_600))
        ]

        let model = TrendPresentation.makeModel(
            snapshots: snapshots,
            range: .day,
            provider: .claude,
            now: now,
            calendar: fixedCalendar
        )

        XCTAssertEqual(model.coverage?.samples, 1)
        XCTAssertEqual(try XCTUnwrap(model.series.first).latest.remaining, 0.7, accuracy: 0.0001)
        XCTAssertEqual(model.domainEnd, now)
        XCTAssertEqual(model.domainStart.timeIntervalSince(now), -86_400, accuracy: 0.001)
    }

    func testProviderWindowAndResetInstanceStaySeparated() throws {
        let firstReset = now.addingTimeInterval(-1_800)
        let secondReset = now.addingTimeInterval(3_600)
        let snapshots = try [
            snapshot(provider: .claude, kind: .fiveHour, remaining: 0.2, observed: now.addingTimeInterval(-7_200), reset: firstReset),
            snapshot(provider: .claude, kind: .fiveHour, remaining: 0.95, observed: now.addingTimeInterval(-1_200), reset: secondReset),
            snapshot(provider: .codex, kind: .primary, remaining: 0.6, observed: now.addingTimeInterval(-900), reset: secondReset)
        ]

        let model = TrendPresentation.makeModel(snapshots: snapshots, range: .day, provider: nil, now: now)
        let claude = try XCTUnwrap(model.series.first { $0.key.provider == .claude })

        XCTAssertEqual(model.series.count, 2)
        XCTAssertEqual(claude.segments.count, 2)
        XCTAssertNotEqual(claude.segments[0].windowInstance, claude.segments[1].windowInstance)
        XCTAssertEqual(
            model.resetEvents,
            [Date(timeIntervalSince1970: (firstReset.timeIntervalSince1970 / 60).rounded() * 60)]
        )
    }

    func testFreshnessAndLargeGapCreateNewSegments() throws {
        let reset = now.addingTimeInterval(3_600)
        let snapshots = try [
            snapshot(provider: .grok, kind: .sharedWeekly, remaining: 0.8, observed: now.addingTimeInterval(-10_000), reset: reset),
            snapshot(provider: .grok, kind: .sharedWeekly, remaining: 0.7, observed: now.addingTimeInterval(-9_700), reset: reset),
            snapshot(provider: .grok, kind: .sharedWeekly, remaining: 0.7, observed: now.addingTimeInterval(-9_400), reset: reset, freshness: .stale),
            snapshot(provider: .grok, kind: .sharedWeekly, remaining: 0.6, observed: now.addingTimeInterval(-1_000), reset: reset)
        ]

        let model = TrendPresentation.makeModel(snapshots: snapshots, range: .day, provider: .grok, now: now)
        let segments = try XCTUnwrap(model.series.first).segments

        XCTAssertEqual(segments.map(\.freshnessStyle), [.observed, .cached, .observed])
    }

    func testDuplicateObservationPrefersLiveOverStale() throws {
        let observed = now.addingTimeInterval(-600)
        let reset = now.addingTimeInterval(3_600)
        let snapshots = try [
            snapshot(provider: .claude, kind: .fiveHour, remaining: 0.4, observed: observed, reset: reset, freshness: .stale),
            snapshot(provider: .claude, kind: .fiveHour, remaining: 0.4, observed: observed, reset: reset, freshness: .live)
        ]

        let model = TrendPresentation.makeModel(snapshots: snapshots, range: .day, provider: .claude, now: now)

        XCTAssertEqual(model.coverage?.samples, 1)
        XCTAssertEqual(model.series.first?.latest.freshness, .live)
    }

    func testDownsamplePreservesFirstLastAndMinimum() throws {
        let key = TrendWindowKey(provider: .claude, kind: .fiveHour)
        let values = try [0.8, 0.7, 0.2, 0.6, 0.5].enumerated().map { index, remaining in
            try point(
                key: key,
                remaining: remaining,
                observed: now.addingTimeInterval(TimeInterval(index * 60))
            )
        }

        let result = TrendPresentation.downsample(values, bucketInterval: 3_600)

        XCTAssertEqual(result.first?.remaining, 0.8)
        XCTAssertTrue(result.contains { $0.remaining == 0.2 })
        XCTAssertEqual(result.last?.remaining, 0.5)
        XCTAssertLessThanOrEqual(result.count, 3)
    }

    func testSuggestedProviderUsesMostUrgentLatestSeries() throws {
        let snapshots = try [
            snapshot(provider: .claude, kind: .fiveHour, remaining: 0.4, observed: now.addingTimeInterval(-600)),
            snapshot(provider: .grok, kind: .sharedWeekly, remaining: 0.1, observed: now.addingTimeInterval(-300))
        ]

        XCTAssertEqual(TrendPresentation.suggestedProvider(snapshots: snapshots, now: now), .grok)
    }

    func testRateAndPaceUseCurrentFreshWindowOnly() throws {
        let reset = now.addingTimeInterval(5_000)
        let snapshots = try [
            snapshot(provider: .codex, kind: .primary, remaining: 0.8, observed: now.addingTimeInterval(-1_200), reset: reset),
            snapshot(provider: .codex, kind: .primary, remaining: 0.7, observed: now.addingTimeInterval(-600), reset: reset),
            snapshot(provider: .codex, kind: .primary, remaining: 0.6, observed: now, reset: reset)
        ]

        let model = TrendPresentation.makeModel(snapshots: snapshots, range: .day, provider: .codex, now: now)
        let series = try XCTUnwrap(model.primarySeries)

        XCTAssertEqual(try XCTUnwrap(series.ratePerHour), -0.6, accuracy: 0.0001)
        XCTAssertEqual(series.paceEstimate?.samples, 3)
    }

    func testSubSecondResetCountdownJitterStaysInOneWindow() throws {
        let nominalReset = now.addingTimeInterval(20_000)
        let snapshots = try [
            snapshot(
                provider: .claude,
                kind: .fiveHour,
                remaining: 0.52,
                observed: now.addingTimeInterval(-1_200),
                reset: nominalReset.addingTimeInterval(-0.48)
            ),
            snapshot(
                provider: .claude,
                kind: .fiveHour,
                remaining: 0.49,
                observed: now.addingTimeInterval(-600),
                reset: nominalReset.addingTimeInterval(0.47)
            ),
            snapshot(
                provider: .claude,
                kind: .fiveHour,
                remaining: 0.47,
                observed: now,
                reset: nominalReset.addingTimeInterval(0.26)
            )
        ]

        let model = TrendPresentation.makeModel(snapshots: snapshots, range: .day, provider: .claude, now: now)
        let series = try XCTUnwrap(model.primarySeries)

        XCTAssertEqual(series.segments.count, 1)
        XCTAssertEqual(series.segments.first?.points.count, 3)
        XCTAssertNotNil(series.ratePerHour)
        XCTAssertEqual(series.paceEstimate?.samples, 3)
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func snapshot(
        provider: ProviderID,
        kind: QuotaWindowKind,
        remaining: Double,
        observed: Date,
        reset: Date? = nil,
        freshness: DataFreshness = .live
    ) throws -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            state: freshness == .stale ? .stale : .available,
            windows: [QuotaWindow(
                kind: kind,
                usedRatio: try QuotaRatio(1 - remaining),
                resetsAt: reset,
                provenance: ValueProvenance(
                    source: .syntheticFixture,
                    contract: .documented,
                    observedAt: observed,
                    freshness: freshness
                )
            )],
            credits: nil,
            lastAttempt: nil,
            lastSuccessAt: observed
        )
    }

    private func point(
        key: TrendWindowKey,
        remaining: Double,
        observed: Date
    ) throws -> TrendPoint {
        TrendPoint(
            key: key,
            windowInstance: "instance",
            date: observed,
            remaining: remaining,
            freshness: .live,
            source: .syntheticFixture,
            contract: .documented,
            resetsAt: nil
        )
    }
}
