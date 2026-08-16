import XCTest
@testable import AIQuotaMonitor

final class PresentationTests: XCTestCase {
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
