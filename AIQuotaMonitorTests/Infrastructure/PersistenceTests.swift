import XCTest
@testable import AIQuotaMonitor

final class PersistenceTests: XCTestCase {
    func testSnapshotStoreMergesLastKnownGood() async throws {
        let store = SnapshotStore()
        let snapshot = ProviderSnapshot(
            provider: .codex,
            state: .available,
            windows: [try makeWindow()],
            credits: nil,
            lastAttempt: nil,
            lastSuccessAt: Date(timeIntervalSince1970: 100)
        )
        _ = await store.merge(snapshot)
        let merged = await store.merge(.unavailable(.codex, state: .offline))
        XCTAssertEqual(merged.state, .stale)
        XCTAssertEqual(merged.windows.count, 1)
    }

    func testHistoryRoundTripRetentionAndCorruptionQuarantine() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let file = directory.appending(path: "history.json")
        let store = HistoryStore(fileURL: file)
        let now = Date(timeIntervalSince1970: 1_786_860_000)
        let recent = try snapshot(observedAt: now)
        let duplicate = try snapshot(observedAt: now.addingTimeInterval(60))
        let expired = try snapshot(observedAt: now.addingTimeInterval(-31 * 86_400))
        let retained = try await store.save([expired, recent, duplicate], now: now)
        XCTAssertEqual(retained.count, 1)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.count, 1)

        try Data("broken".utf8).write(to: file)
        do {
            _ = try await HistoryStore(fileURL: file).load()
            XCTFail("Corrupt history should fail")
        } catch {
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            XCTAssertTrue(contents.contains { $0.contains("corrupt-") })
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeWindow() throws -> QuotaWindow {
        try QuotaWindow(
            kind: .primary,
            usedRatio: QuotaRatio(0.25),
            resetsAt: Date(timeIntervalSince1970: 200),
            provenance: ValueProvenance(
                source: .officialCLI, contract: .observed,
                observedAt: Date(timeIntervalSince1970: 100), freshness: .live
            )
        )
    }

    private func snapshot(observedAt: Date) throws -> ProviderSnapshot {
        try ProviderSnapshot(
            provider: .claude,
            state: .available,
            windows: [QuotaWindow(
                kind: .fiveHour,
                usedRatio: QuotaRatio(0.25),
                resetsAt: Date(timeIntervalSince1970: 1_786_880_000),
                provenance: ValueProvenance(
                    source: .officialDocument,
                    contract: .documented,
                    observedAt: observedAt,
                    freshness: .live
                )
            )],
            credits: nil,
            lastAttempt: CollectionAttempt(
                startedAt: observedAt,
                finishedAt: observedAt,
                succeeded: true,
                diagnostic: nil
            ),
            lastSuccessAt: observedAt
        )
    }
}
