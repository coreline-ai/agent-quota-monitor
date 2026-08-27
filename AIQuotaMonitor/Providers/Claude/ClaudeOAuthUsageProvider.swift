import Foundation

actor ClaudeOAuthUsageProvider: QuotaProvider {
    nonisolated let id = ProviderID.claude
    let credentialReader: any ClaudeCredentialReading
    let client: any HTTPClientProtocol

    private var cachedSuccess: ProviderFetchResult?
    private var lastRequestAt: Date?
    private var retryAt: Date?

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let minimumRequestInterval: TimeInterval = 180
    private static let defaultRateLimitBackoff: TimeInterval = 15 * 60

    init(
        credentialReader: (any ClaudeCredentialReading)? = nil,
        client: (any HTTPClientProtocol)? = nil
    ) {
        self.credentialReader = credentialReader ?? ClaudeKeychainCredentialReader()
        self.client = client ?? Self.makePrivateHTTPClient()
    }

    func availability() async -> ProviderAvailability {
        do {
            _ = try await credentialReader.read()
            return .available
        } catch {
            return .notConfigured
        }
    }

    func fetchQuota() async -> ProviderFetchResult {
        await fetchQuota(policy: .scheduled)
    }

    func fetchQuota(policy: ProviderRefreshPolicy) async -> ProviderFetchResult {
        let startedAt = Date()
        if let retryAt, retryAt > startedAt {
            return failure(startedAt: startedAt, code: .rateLimited)
        }
        if policy.allowsCachedSuccess,
           let lastRequestAt,
           startedAt.timeIntervalSince(lastRequestAt) < Self.minimumRequestInterval,
           let cachedSuccess {
            return ProviderFetchResult(snapshot: cachedSuccess.snapshot.markingFreshness(.recent))
        }
        do {
            let credential = try await credentialReader.read()
            lastRequestAt = Date()
            let payload = try await client.data(
                for: request(using: credential),
                timeout: .seconds(10)
            )
            if payload.statusCode == 429 {
                retryAt = Date().addingTimeInterval(retryDelay(from: payload.headers))
            }
            try validateStatus(payload.statusCode)
            var snapshot = try ClaudeOAuthUsageParser().parse(payload.body, observedAt: Date())
            snapshot.lastAttempt = CollectionAttempt(
                startedAt: startedAt,
                finishedAt: Date(),
                succeeded: true,
                diagnostic: nil
            )
            snapshot.lastSuccessAt = Date()
            let result = ProviderFetchResult(snapshot: snapshot)
            cachedSuccess = result
            retryAt = nil
            return result
        } catch let code as ProviderErrorCode {
            return failure(startedAt: startedAt, code: code)
        } catch let error as HTTPClientError {
            let code: ProviderErrorCode = switch error {
            case .timeout: .timeout
            case .cancelled: .cancelled
            case .invalidResponse, .transport: .io
            }
            return failure(startedAt: startedAt, code: code)
        } catch {
            return failure(startedAt: startedAt, code: .malformedPayload)
        }
    }

    private func request(using credential: ClaudeOAuthCredential) -> URLRequest {
        var request = URLRequest(
            url: Self.endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validateStatus(_ statusCode: Int) throws {
        switch statusCode {
        case 200 ... 299: return
        case 401: throw ProviderErrorCode.invalidCredential
        case 403: throw ProviderErrorCode.forbidden
        case 429: throw ProviderErrorCode.rateLimited
        case 500 ... 599: throw ProviderErrorCode.server
        default: throw ProviderErrorCode.malformedPayload
        }
    }

    private func retryDelay(from headers: [String: String]) -> TimeInterval {
        guard let value = headers.first(where: { $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame })?.value else {
            return Self.defaultRateLimitBackoff
        }
        if let seconds = TimeInterval(value), seconds > 0 {
            return min(seconds, 24 * 60 * 60)
        }
        return Self.defaultRateLimitBackoff
    }

    private func failure(startedAt: Date, code: ProviderErrorCode) -> ProviderFetchResult {
        let state: ProviderState = switch code {
        case .missingCredential, .notFound: .notConfigured
        case .invalidCredential: .authenticationRequired
        case .forbidden: .unsupportedAccount
        case .rateLimited: .rateLimited
        case .unsupported: .unsupportedContract
        case .server, .timeout, .cancelled, .malformedPayload, .io: .failed
        }
        var snapshot = ProviderSnapshot.unavailable(id, state: state)
        snapshot.lastAttempt = CollectionAttempt(
            startedAt: startedAt,
            finishedAt: Date(),
            succeeded: false,
            diagnostic: RedactedDiagnostic(
                summary: "Claude read-only usage collection failed.",
                code: code
            )
        )
        return ProviderFetchResult(snapshot: snapshot)
    }

    private static func makePrivateHTTPClient() -> HTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(
            configuration: configuration,
            delegate: ClaudeRedirectRejectingDelegate(),
            delegateQueue: nil
        )
        return HTTPClient(session: session)
    }
}

private final class ClaudeRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
