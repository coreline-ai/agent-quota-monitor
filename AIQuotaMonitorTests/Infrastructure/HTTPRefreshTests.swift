import XCTest
@testable import AIQuotaMonitor

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var delay: TimeInterval = 0
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let delay = Self.delay
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let response = HTTPURLResponse(
                url: self.request.url ?? URL(string: "https://invalid.local")!,
                statusCode: Self.statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Self.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

final class HTTPRefreshTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.delay = 0
        StubURLProtocol.statusCode = 200
        StubURLProtocol.body = Data("{}".utf8)
    }

    func testHTTPClientReturnsOnceAndTimesOut() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = HTTPClient(session: URLSession(configuration: configuration))
        let request = URLRequest(url: URL(string: "https://quota.invalid/read")!)
        let response = try await client.data(for: request, timeout: .seconds(1))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.body, Data("{}".utf8))

        StubURLProtocol.delay = 0.3
        do {
            _ = try await client.data(for: request, timeout: .milliseconds(30))
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? HTTPClientError, .timeout)
        }
    }

    func testRefreshCoordinatorCoalescesSameProvider() async {
        let provider = CountingProvider()
        let coordinator = RefreshCoordinator(providers: [provider], store: SnapshotStore())
        await withTaskGroup(of: ProviderSnapshot?.self) { group in
            for _ in 0 ..< 6 { group.addTask { await coordinator.refresh(.codex) } }
            for await result in group { XCTAssertEqual(result?.provider, .codex) }
        }
        let count = await provider.fetchCount()
        XCTAssertEqual(count, 1)
    }

    func testRefreshCoordinatorKeepsOtherProvidersWhenGeminiFails() async {
        let providers: [any QuotaProvider] = ProviderID.allCases.map { provider in
            FixedStateProvider(
                id: provider,
                state: provider == .gemini ? .failed : .partial
            )
        }
        let coordinator = RefreshCoordinator(providers: providers, store: SnapshotStore())
        let snapshots = await coordinator.refreshAll()

        XCTAssertEqual(snapshots.count, ProviderID.allCases.count)
        XCTAssertEqual(snapshots.first { $0.provider == .gemini }?.state, .failed)
        for provider in ProviderID.allCases where provider != .gemini {
            XCTAssertEqual(snapshots.first { $0.provider == provider }?.state, .partial)
        }
    }

    @MainActor
    func testQuotaMonitorModelCoalescesOverlappingRefreshesAndCanCancel() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = CountingProvider()
        let model = QuotaMonitorModel(
            providers: [provider],
            historyStore: HistoryStore(fileURL: directory.appending(path: "history.json"))
        )

        let first = Task { await model.refresh() }
        try? await Task.sleep(for: .milliseconds(10))
        let second = Task { await model.refresh() }
        await first.value
        await second.value

        let count = await provider.fetchCount()
        XCTAssertEqual(count, 1)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNotNil(model.lastRefreshAt)

        let cancelled = Task { await model.refresh() }
        try? await Task.sleep(for: .milliseconds(10))
        model.cancel()
        await cancelled.value
        XCTAssertFalse(model.isRefreshing)
    }

    func testGlobalFailureStreakOnlyBacksOffWhenEveryAttemptFails() {
        let success = attemptedSnapshot(.codex, succeeded: true)
        let failure = attemptedSnapshot(.grok, succeeded: false)
        let notConfigured = ProviderSnapshot.unavailable(.gemini, state: .notConfigured)

        XCTAssertEqual(
            QuotaMonitorModel.nextFailureStreak(
                current: 2,
                snapshots: [success, failure, notConfigured]
            ),
            0
        )
        XCTAssertEqual(
            QuotaMonitorModel.nextFailureStreak(
                current: 2,
                snapshots: [failure, notConfigured]
            ),
            3
        )
        XCTAssertEqual(
            QuotaMonitorModel.nextFailureStreak(
                current: 2,
                snapshots: [notConfigured]
            ),
            0
        )
    }

    private func attemptedSnapshot(_ provider: ProviderID, succeeded: Bool) -> ProviderSnapshot {
        var snapshot = ProviderSnapshot.unavailable(
            provider,
            state: succeeded ? .partial : .failed
        )
        snapshot.lastAttempt = CollectionAttempt(
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2),
            succeeded: succeeded,
            diagnostic: nil
        )
        return snapshot
    }
}

private actor CountingProvider: QuotaProvider {
    nonisolated let id = ProviderID.codex
    private var count = 0

    func availability() async -> ProviderAvailability { .available }

    func fetchQuota() async -> ProviderFetchResult {
        count += 1
        try? await Task.sleep(for: .milliseconds(80))
        return ProviderFetchResult(snapshot: .unavailable(.codex, state: .partial))
    }

    func fetchCount() -> Int { count }
}

private struct FixedStateProvider: QuotaProvider {
    let id: ProviderID
    let state: ProviderState

    func availability() async -> ProviderAvailability { .available }

    func fetchQuota() async -> ProviderFetchResult {
        ProviderFetchResult(snapshot: .unavailable(id, state: state))
    }
}
