import Foundation

protocol QuotaPayloadParser: Sendable {
    var provider: ProviderID { get }
    func parse(_ data: Data, observedAt: Date) throws -> ProviderSnapshot
}

struct ReadOnlyPayloadProvider<Parser: QuotaPayloadParser>: QuotaProvider {
    let id: ProviderID
    let parser: Parser
    let loader: @Sendable () async throws -> Data

    func availability() async -> ProviderAvailability { .available }

    func fetchQuota() async -> ProviderFetchResult {
        let startedAt = Date()
        do {
            let data = try await loader()
            var snapshot = try parser.parse(data, observedAt: Date())
            snapshot.lastAttempt = CollectionAttempt(
                startedAt: startedAt,
                finishedAt: Date(),
                succeeded: true,
                diagnostic: nil
            )
            snapshot.lastSuccessAt = Date()
            return ProviderFetchResult(snapshot: snapshot)
        } catch let code as ProviderErrorCode {
            return ProviderFetchResult(snapshot: failedSnapshot(startedAt: startedAt, code: code))
        } catch {
            return ProviderFetchResult(snapshot: failedSnapshot(startedAt: startedAt, code: .malformedPayload))
        }
    }

    private func failedSnapshot(startedAt: Date, code: ProviderErrorCode) -> ProviderSnapshot {
        var snapshot = ProviderSnapshot.unavailable(id, state: code == .unsupported ? .unsupportedContract : .failed)
        snapshot.lastAttempt = CollectionAttempt(
            startedAt: startedAt,
            finishedAt: Date(),
            succeeded: false,
            diagnostic: RedactedDiagnostic(summary: "Provider collection failed safely.", code: code)
        )
        return snapshot
    }
}

struct StateOnlyProvider: QuotaProvider {
    let id: ProviderID
    let state: ProviderState

    func availability() async -> ProviderAvailability {
        state == .unsupportedContract ? .unsupported(reason: "machine contract unavailable") : .notConfigured
    }

    func fetchQuota() async -> ProviderFetchResult {
        ProviderFetchResult(snapshot: .unavailable(id, state: state))
    }
}
