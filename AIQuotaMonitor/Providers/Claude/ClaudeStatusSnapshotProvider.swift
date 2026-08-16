import Foundation

struct ClaudeStatusSnapshotProvider: QuotaProvider {
    let id = ProviderID.claude
    let snapshotURL: URL
    let validator: CredentialFileValidator

    func availability() async -> ProviderAvailability {
        do {
            try validator.validate(snapshotURL)
            return .available
        } catch {
            return .notConfigured
        }
    }

    func fetchQuota() async -> ProviderFetchResult {
        guard case .available = await availability() else {
            return ProviderFetchResult(snapshot: .unavailable(id, state: .notConfigured))
        }
        let provider = ReadOnlyPayloadProvider(id: id, parser: ClaudeQuotaParser()) {
            try validator.validate(snapshotURL)
            return try Data(contentsOf: snapshotURL, options: [.mappedIfSafe])
        }
        return await provider.fetchQuota()
    }
}
