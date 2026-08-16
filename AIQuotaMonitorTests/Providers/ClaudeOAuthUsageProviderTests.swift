import XCTest
@testable import AIQuotaMonitor

final class ClaudeOAuthUsageProviderTests: XCTestCase {
    func testCredentialParserSelectsOnlyAccessToken() throws {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"test-token","refreshToken":"ignored"}}"#.utf8)
        let credential = try ClaudeKeychainCredentialReader.parseCredential(data)
        XCTAssertEqual(credential, ClaudeOAuthCredential(accessToken: "test-token"))

        XCTAssertThrowsError(try ClaudeKeychainCredentialReader.parseCredential(Data(#"{"claudeAiOauth":{}}"#.utf8))) {
            XCTAssertEqual($0 as? ProviderErrorCode, .invalidCredential)
        }
        XCTAssertThrowsError(try ClaudeKeychainCredentialReader.parseCredential(Data("not-json".utf8))) {
            XCTAssertEqual($0 as? ProviderErrorCode, .malformedPayload)
        }
    }

    func testOAuthParserHandlesISOResetsAndFableScope() throws {
        let normal = try ClaudeOAuthUsageParser().parse(fixture("claude-oauth-normal"), observedAt: Date())
        XCTAssertEqual(normal.state, .available)
        XCTAssertEqual(normal.windows.count, 3)
        XCTAssertEqual(normal.windows.first { $0.kind == .fiveHour }?.usedRatio.value ?? -1, 0.27, accuracy: 0.0001)
        XCTAssertEqual(normal.windows.first { $0.kind == .sevenDay }?.usedRatio.value ?? -1, 0.61, accuracy: 0.0001)
        XCTAssertEqual(normal.windows.first { $0.kind == .custom("Fable 주간") }?.usedRatio.value ?? -1, 0.39, accuracy: 0.0001)
        XCTAssertNotNil(normal.windows.first?.resetsAt)
        XCTAssertTrue(normal.windows.allSatisfy { $0.provenance.source == .keychain })
        XCTAssertTrue(normal.windows.allSatisfy { $0.provenance.contract == .observed })

        let partial = try ClaudeOAuthUsageParser().parse(fixture("claude-oauth-partial"), observedAt: Date())
        XCTAssertEqual(partial.state, .partial)
        XCTAssertEqual(partial.windows.count, 1)
        XCTAssertNotNil(partial.windows.first?.resetsAt)
    }

    func testOAuthParserRejectsMissingAndOutOfRangeUsage() {
        XCTAssertThrowsError(try ClaudeOAuthUsageParser().parse(Data(#"{"five_hour":{}}"#.utf8), observedAt: Date())) {
            XCTAssertEqual($0 as? ProviderErrorCode, .malformedPayload)
        }
        XCTAssertThrowsError(try ClaudeOAuthUsageParser().parse(Data(#"{"five_hour":{"utilization":101}}"#.utf8), observedAt: Date())) {
            XCTAssertEqual($0 as? QuotaValidationError, .invalidRatio)
        }
        XCTAssertThrowsError(try ClaudeOAuthUsageParser().parse(Data(#"{"five_hour":{"utilization":true}}"#.utf8), observedAt: Date())) {
            XCTAssertEqual($0 as? ProviderErrorCode, .malformedPayload)
        }
    }

    func testProviderSendsOnlyAnthropicReadOnlyUsageGET() async {
        let body = Data(#"{"five_hour":{"utilization":21},"seven_day":{"utilization":34}}"#.utf8)
        let client = ClaudeRecordingHTTPClient(response: HTTPPayload(statusCode: 200, headers: [:], body: body))
        let provider = ClaudeOAuthUsageProvider(
            credentialReader: ClaudeFixtureCredentialReader(accessToken: "test-token"),
            client: client
        )

        let result = await provider.fetchQuota()
        let request = await client.capturedRequest()
        XCTAssertEqual(result.snapshot.state, .available)
        XCTAssertEqual(request?.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "User-Agent"), "claude-code/2.1.0")
        XCTAssertNil(request?.httpBody)
        XCTAssertFalse(request?.httpShouldHandleCookies ?? true)

        _ = await provider.fetchQuota()
        let requestCount = await client.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testProviderMapsAuthenticationAndNetworkFailures() async {
        for (status, expected) in [
            (401, ProviderState.authenticationRequired),
            (403, .unsupportedAccount),
            (429, .rateLimited),
            (503, .failed),
        ] {
            let client = ClaudeRecordingHTTPClient(
                response: HTTPPayload(statusCode: status, headers: [:], body: Data())
            )
            let result = await ClaudeOAuthUsageProvider(
                credentialReader: ClaudeFixtureCredentialReader(accessToken: "test-token"),
                client: client
            ).fetchQuota()
            XCTAssertEqual(result.snapshot.state, expected)
            XCTAssertTrue(result.snapshot.windows.isEmpty)
        }

        let timeout = await ClaudeOAuthUsageProvider(
            credentialReader: ClaudeFixtureCredentialReader(accessToken: "test-token"),
            client: ClaudeFailingHTTPClient(error: .timeout)
        ).fetchQuota()
        XCTAssertEqual(timeout.snapshot.state, .failed)
        XCTAssertEqual(timeout.snapshot.lastAttempt?.diagnostic?.code, .timeout)

        for (code, expected) in [
            (ProviderErrorCode.missingCredential, ProviderState.notConfigured),
            (.invalidCredential, .authenticationRequired),
            (.forbidden, .unsupportedAccount),
            (.malformedPayload, .failed),
        ] {
            let result = await ClaudeOAuthUsageProvider(
                credentialReader: ClaudeFailingCredentialReader(error: code),
                client: ClaudeRecordingHTTPClient(response: HTTPPayload(statusCode: 200, headers: [:], body: Data()))
            ).fetchQuota()
            XCTAssertEqual(result.snapshot.state, expected)
            XCTAssertEqual(result.snapshot.lastAttempt?.diagnostic?.code, code)
        }
    }

    private func fixture(_ name: String) throws -> Data {
        let testsRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: testsRoot.appending(path: "Fixtures/Claude/\(name).json"))
    }
}

private struct ClaudeFixtureCredentialReader: ClaudeCredentialReading {
    let accessToken: String

    func read() async throws -> ClaudeOAuthCredential {
        ClaudeOAuthCredential(accessToken: accessToken)
    }
}

private struct ClaudeFailingCredentialReader: ClaudeCredentialReading {
    let error: ProviderErrorCode

    func read() async throws -> ClaudeOAuthCredential {
        throw error
    }
}

private struct ClaudeFailingHTTPClient: HTTPClientProtocol {
    let error: HTTPClientError

    func data(for request: URLRequest, timeout: Duration) async throws -> HTTPPayload {
        throw error
    }
}

private actor ClaudeRecordingHTTPClient: HTTPClientProtocol {
    private let response: HTTPPayload
    private var request: URLRequest?
    private var count = 0

    init(response: HTTPPayload) {
        self.response = response
    }

    func data(for request: URLRequest, timeout: Duration) async throws -> HTTPPayload {
        self.request = request
        count += 1
        return response
    }

    func capturedRequest() -> URLRequest? { request }
    func requestCount() -> Int { count }
}
