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
