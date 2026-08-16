import Foundation

struct GrokBillingProvider: QuotaProvider {
    let id = ProviderID.grok
    let credentialReader: GrokCredentialReader
    let client: any HTTPClientProtocol
    let clientVersion: String
    private static let endpoint = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!

    init(
        authURL: URL,
        validator: CredentialFileValidator,
        client: (any HTTPClientProtocol)? = nil,
        clientVersion: String = "1.0.4"
    ) {
        credentialReader = GrokCredentialReader(authURL: authURL, validator: validator)
        self.client = client ?? Self.makePrivateHTTPClient()
        self.clientVersion = clientVersion
    }

    func availability() async -> ProviderAvailability {
        do {
            _ = try credentialReader.read()
            return .available
        } catch {
            return .notConfigured
        }
    }

    func fetchQuota() async -> ProviderFetchResult {
        let startedAt = Date()
        do {
            let credential = try credentialReader.read()
            let payload = try await client.data(for: request(using: credential), timeout: .seconds(15))
            try validateStatus(payload.statusCode)
            var snapshot = try GrokQuotaParser().parse(payload.body, observedAt: Date())
            snapshot.lastAttempt = CollectionAttempt(
                startedAt: startedAt,
                finishedAt: Date(),
                succeeded: true,
                diagnostic: nil
            )
            snapshot.lastSuccessAt = Date()
            return ProviderFetchResult(snapshot: snapshot)
        } catch let code as ProviderErrorCode {
            return failure(startedAt: startedAt, code: code)
        } catch let error as HTTPClientError {
            let code: ProviderErrorCode = switch error {
            case .timeout: .timeout
            case .cancelled: .cancelled
            case .invalidResponse, .transport: .io
            }
            return failure(startedAt: startedAt, code: code)
        } catch is CredentialFileError {
            return failure(startedAt: startedAt, code: .missingCredential)
        } catch {
            return failure(startedAt: startedAt, code: .malformedPayload)
        }
    }

    private func request(using credential: GrokCredential) -> URLRequest {
        var request = URLRequest(
            url: Self.endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue(credential.userID, forHTTPHeaderField: "x-userid")
        request.setValue(clientVersion, forHTTPHeaderField: "x-grok-client-version")
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
            diagnostic: RedactedDiagnostic(summary: "Grok read-only billing collection failed.", code: code)
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
            delegate: RedirectRejectingDelegate(),
            delegateQueue: nil
        )
        return HTTPClient(session: session)
    }
}

private final class RedirectRejectingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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
