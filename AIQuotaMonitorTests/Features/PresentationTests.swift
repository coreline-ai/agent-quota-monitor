import XCTest
@testable import AIQuotaMonitor

final class PresentationTests: XCTestCase {
    func testQuotaPresentationSupportsRemainingAndUsedMetrics() throws {
        let window = QuotaWindow(
            kind: .fiveHour,
            usedRatio: try QuotaRatio(0.75),
            resetsAt: nil,
            provenance: ValueProvenance(
                source: .syntheticFixture,
                contract: .documented,
                observedAt: Date(timeIntervalSince1970: 0),
                freshness: .live
            )
        )

        XCTAssertEqual(QuotaPresentation.ratio(for: window, mode: .remaining), 0.25, accuracy: 0.0001)
        XCTAssertEqual(QuotaPresentation.ratio(for: window, mode: .used), 0.75, accuracy: 0.0001)
        XCTAssertEqual(QuotaPresentation.percentText(0.256), "26%")
        XCTAssertEqual(QuotaPresentation.percentText(-1), "0%")
        XCTAssertEqual(QuotaPresentation.percentText(2), "100%")
    }

    func testQuotaUrgencyUsesRemainingThresholds() {
        XCTAssertEqual(QuotaPresentation.urgency(forRemaining: 0), .critical)
        XCTAssertEqual(QuotaPresentation.urgency(forRemaining: 0.10), .critical)
        XCTAssertEqual(QuotaPresentation.urgency(forRemaining: 0.1001), .warning)
        XCTAssertEqual(QuotaPresentation.urgency(forRemaining: 0.25), .warning)
        XCTAssertEqual(QuotaPresentation.urgency(forRemaining: 0.2501), .healthy)
        XCTAssertEqual(QuotaPresentation.urgency(forRemaining: 1), .healthy)
    }

    func testResetPresentationHandlesRelativeUnknownAndPastDates() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(
            QuotaPresentation.resetText(for: now.addingTimeInterval(2 * 86_400 + 3_600), style: .relative, relativeTo: now),
            "2일 1시간 후"
        )
        XCTAssertEqual(
            QuotaPresentation.resetText(for: now.addingTimeInterval(90), style: .relative, relativeTo: now),
            "1분 이내"
        )
        XCTAssertEqual(QuotaPresentation.resetText(for: now, style: .relative, relativeTo: now), "리셋 확인 필요")
        XCTAssertEqual(QuotaPresentation.resetText(for: nil, style: .absolute, relativeTo: now), "리셋 미확인")
    }

    func testProviderMarksAreIndependentAndUnique() {
        XCTAssertEqual(Set(ProviderID.allCases.map(\.beaconSymbol)).count, ProviderID.allCases.count)
    }

    func testUnavailableStatesHaveNoInventedWindows() async throws {
        for provider in ProviderID.allCases {
            let state: ProviderState = provider == .zai ? .unsupportedContract : .notConfigured
            let result = await StateOnlyProvider(id: provider, state: state).fetchQuota()
            XCTAssertTrue(result.snapshot.windows.isEmpty)
            XCTAssertNil(result.snapshot.credits)
        }
    }

    func testExportContainsNoDiagnosticsOrAccountData() throws {
        var snapshot = ProviderSnapshot.unavailable(.codex, state: .failed)
        snapshot.lastAttempt = CollectionAttempt(
            startedAt: Date(), finishedAt: Date(), succeeded: false,
            diagnostic: RedactedDiagnostic(summary: "Bearer abcdefghijklmnop user@example.com", code: .invalidCredential)
        )
        let data = try ExportService.data(for: [snapshot], format: .json)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("Bearer"))
        XCTAssertFalse(text.contains("example.com"))
        XCTAssertTrue(text.contains("codex"))
    }

    func testNotificationDedupeKeyIsWindowScoped() async {
        let deduplicator = NotificationDeduplicator()
        let first = NotificationKey(provider: .claude, windowInstance: "one", event: "25")
        let second = NotificationKey(provider: .claude, windowInstance: "two", event: "25")
        let firstDelivery = await deduplicator.shouldDeliver(first)
        let duplicateDelivery = await deduplicator.shouldDeliver(first)
        let nextWindowDelivery = await deduplicator.shouldDeliver(second)
        XCTAssertTrue(firstDelivery)
        XCTAssertFalse(duplicateDelivery)
        XCTAssertTrue(nextWindowDelivery)
        XCTAssertNil(QuotaAlertEvaluator.event(for: 0.26))
        XCTAssertEqual(QuotaAlertEvaluator.event(for: 0.25), "25")
        XCTAssertEqual(QuotaAlertEvaluator.event(for: 0.10), "10")
        XCTAssertEqual(QuotaAlertEvaluator.event(for: 0), "exhausted")
    }
}
