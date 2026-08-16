import Foundation

struct HTTPPayload: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

enum HTTPClientError: Error, Equatable {
    case invalidResponse
    case timeout
    case cancelled
    case transport
}

protocol HTTPClientProtocol: Sendable {
    func data(for request: URLRequest, timeout: Duration) async throws -> HTTPPayload
}

actor HTTPClient: HTTPClientProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest, timeout: Duration = .seconds(8)) async throws -> HTTPPayload {
        do {
            return try await withThrowingTaskGroup(of: HTTPPayload.self) { group in
                group.addTask { [session] in
                    let (data, response) = try await session.data(for: request)
                    guard let response = response as? HTTPURLResponse else {
                        throw HTTPClientError.invalidResponse
                    }
                    let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                        result[String(describing: pair.key)] = String(describing: pair.value)
                    }
                    return HTTPPayload(statusCode: response.statusCode, headers: headers, body: data)
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw HTTPClientError.timeout
                }
                guard let first = try await group.next() else { throw HTTPClientError.transport }
                group.cancelAll()
                return first
            }
        } catch is CancellationError {
            throw HTTPClientError.cancelled
        } catch let error as HTTPClientError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw HTTPClientError.timeout
        } catch {
            throw HTTPClientError.transport
        }
    }
}
