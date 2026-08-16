import Darwin
import XCTest
@testable import AIQuotaMonitor

final class GrokBillingProviderTests: XCTestCase {
    func testCredentialReaderPrefersOIDCAndRejectsExpiredCredential() throws {
        let fixture = try makeCredentialFile(expiresAt: Date().addingTimeInterval(3_600))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let reader = GrokCredentialReader(
            authURL: fixture.authURL,
            validator: CredentialFileValidator(allowedRoots: [fixture.directory])
        )
        let credential = try reader.read()
        XCTAssertEqual(credential.accessToken, "temporary-test-value")
        XCTAssertEqual(credential.userID, "local-test-user")

        let expired = try makeCredentialFile(expiresAt: Date().addingTimeInterval(-3_600))
        defer { try? FileManager.default.removeItem(at: expired.directory) }
        let expiredReader = GrokCredentialReader(
            authURL: expired.authURL,
            validator: CredentialFileValidator(allowedRoots: [expired.directory])
        )
        XCTAssertThrowsError(try expiredReader.read()) {
            XCTAssertEqual($0 as? ProviderErrorCode, .invalidCredential)
        }
    }

    func testProviderSendsOnlyReadOnlyBillingGET() async throws {
        let fixture = try makeCredentialFile(expiresAt: Date().addingTimeInterval(3_600))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let body = Data(#"{"config":{"creditUsagePercent":21,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-08-23T00:00:00Z"}}}"#.utf8)
        let client = RecordingHTTPClient(response: HTTPPayload(statusCode: 200, headers: [:], body: body))
        let provider = GrokBillingProvider(
            authURL: fixture.authURL,
            validator: CredentialFileValidator(allowedRoots: [fixture.directory]),
            client: client,
            clientVersion: "test-version"
        )

        let result = await provider.fetchQuota()
        let request = await client.capturedRequest()
        XCTAssertEqual(result.snapshot.state, .available)
        XCTAssertEqual(request?.url?.absoluteString, "https://cli-chat-proxy.grok.com/v1/billing?format=credits")
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-XAI-Token-Auth"), "xai-grok-cli")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-grok-client-version"), "test-version")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer temporary-test-value")
        XCTAssertNil(request?.httpBody)
    }

    func testProviderMapsAuthenticationAndAccountFailures() async throws {
        let fixture = try makeCredentialFile(expiresAt: Date().addingTimeInterval(3_600))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        for (status, expected) in [
            (401, ProviderState.authenticationRequired),
            (403, .unsupportedAccount),
            (429, .rateLimited),
            (503, .failed),
        ] {
            let client = RecordingHTTPClient(response: HTTPPayload(statusCode: status, headers: [:], body: Data()))
            let provider = GrokBillingProvider(
                authURL: fixture.authURL,
                validator: CredentialFileValidator(allowedRoots: [fixture.directory]),
                client: client
            )
            let result = await provider.fetchQuota()
            XCTAssertEqual(result.snapshot.state, expected)
            XCTAssertTrue(result.snapshot.windows.isEmpty)
        }

        let timeoutProvider = GrokBillingProvider(
            authURL: fixture.authURL,
            validator: CredentialFileValidator(allowedRoots: [fixture.directory]),
            client: FailingHTTPClient(error: .timeout)
        )
        let timeout = await timeoutProvider.fetchQuota()
        XCTAssertEqual(timeout.snapshot.state, .failed)
        XCTAssertEqual(timeout.snapshot.lastAttempt?.diagnostic?.code, .timeout)
    }

    private func makeCredentialFile(expiresAt: Date) throws -> (directory: URL, authURL: URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let authURL = directory.appending(path: "auth.json")
        let payload: [String: Any] = [
            "https://accounts.x.ai/sign-in": [
                "key": "fallback-test-value",
                "user_id": "fallback-test-user",
                "expires_at": expiresAt.timeIntervalSince1970,
            ],
            "https://auth.x.ai::quotabeacon-tests": [
                "key": "temporary-test-value",
                "user_id": "local-test-user",
                "expires_at": expiresAt.timeIntervalSince1970,
            ],
        ]
        try JSONSerialization.data(withJSONObject: payload).write(to: authURL)
        XCTAssertEqual(chmod(authURL.path, 0o600), 0)
        return (directory, authURL)
    }
}

private struct FailingHTTPClient: HTTPClientProtocol {
    let error: HTTPClientError

    func data(for request: URLRequest, timeout: Duration) async throws -> HTTPPayload {
        throw error
    }
}

private actor RecordingHTTPClient: HTTPClientProtocol {
    private let response: HTTPPayload
    private var request: URLRequest?

    init(response: HTTPPayload) {
        self.response = response
    }

    func data(for request: URLRequest, timeout: Duration) async throws -> HTTPPayload {
        self.request = request
        return response
    }

    func capturedRequest() -> URLRequest? { request }
}
