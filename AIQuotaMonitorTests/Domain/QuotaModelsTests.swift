import XCTest
@testable import AIQuotaMonitor

final class QuotaModelsTests: XCTestCase {
    func testRatioAcceptsBoundariesAndCalculatesRemaining() throws {
        XCTAssertEqual(try QuotaRatio(0).value, 0)
        XCTAssertEqual(try QuotaRatio(1).value, 1)
        XCTAssertEqual(try QuotaRatio(percent: 37).value, 0.37, accuracy: 0.0001)
    }

    func testRatioRejectsInvalidNumbers() {
        for value in [-0.01, 1.01, .nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try QuotaRatio(value))
        }
    }

    func testLastKnownGoodMergeKeepsValueAndMarksItStale() throws {
        let now = Date(timeIntervalSince1970: 1_786_870_000)
        let previous = ProviderSnapshot(
            provider: .claude,
            state: .available,
            windows: [try window(kind: .fiveHour, ratio: 0.4, reset: now)],
            credits: nil,
            lastAttempt: nil,
            lastSuccessAt: now
        )
        let failed = ProviderSnapshot.unavailable(.claude, state: .failed)
        let merged = failed.mergingLastKnownGood(previous)
        XCTAssertEqual(merged.state, .stale)
        XCTAssertEqual(merged.windows.first?.usedRatio.value, 0.4)
        XCTAssertEqual(merged.windows.first?.provenance.freshness, .stale)
        XCTAssertEqual(merged.windows.first?.provenance.source, .officialCLI)
        XCTAssertEqual(merged.lastSuccessAt, now)
    }

    func testResetTimestampCreatesDifferentWindowInstance() throws {
        let first = try window(kind: .primary, ratio: 0.2, reset: Date(timeIntervalSince1970: 100))
        let second = try window(kind: .primary, ratio: 0.2, reset: Date(timeIntervalSince1970: 200))
        XCTAssertNotEqual(first.windowInstance, second.windowInstance)
    }

    func testPaceRequiresThreeFreshSamplesFromSameWindow() throws {
        let reset = Date(timeIntervalSince1970: 10_000)
        let values = try [
            paceWindow(ratio: 0.2, observed: 1_000, reset: reset),
            paceWindow(ratio: 0.3, observed: 1_100, reset: reset),
            paceWindow(ratio: 0.4, observed: 1_200, reset: reset)
        ]
        let estimate = QuotaAnalytics.estimateExhaustion(from: values)
        XCTAssertEqual(estimate?.samples, 3)
        XCTAssertEqual(try XCTUnwrap(estimate).exhaustionAt.timeIntervalSince1970, 1_800, accuracy: 0.001)
        XCTAssertNil(QuotaAnalytics.estimateExhaustion(from: Array(values.prefix(2))))

        var stale = values
        stale[2] = try paceWindow(ratio: 0.4, observed: 1_200, reset: reset, freshness: .stale)
        XCTAssertNil(QuotaAnalytics.estimateExhaustion(from: stale))
    }

    private func window(kind: QuotaWindowKind, ratio: Double, reset: Date) throws -> QuotaWindow {
        try QuotaWindow(
            kind: kind,
            usedRatio: QuotaRatio(ratio),
            resetsAt: reset,
            provenance: ValueProvenance(
                source: .officialCLI,
                contract: .observed,
                observedAt: Date(timeIntervalSince1970: 50),
                freshness: .live
            )
        )
    }

    private func paceWindow(
        ratio: Double,
        observed: TimeInterval,
        reset: Date,
        freshness: DataFreshness = .live
    ) throws -> QuotaWindow {
        try QuotaWindow(
            kind: .primary,
            usedRatio: QuotaRatio(ratio),
            resetsAt: reset,
            provenance: ValueProvenance(
                source: .officialCLI,
                contract: .observed,
                observedAt: Date(timeIntervalSince1970: observed),
                freshness: freshness
            )
        )
    }
}
