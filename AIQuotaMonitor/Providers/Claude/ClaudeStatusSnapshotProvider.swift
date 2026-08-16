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
        let provider = ReadOnlyPayloadProvider(id: id, parser: ClaudeQuotaParser()) {
            try validator.validate(snapshotURL)
            return try Data(contentsOf: snapshotURL, options: [.mappedIfSafe])
        }
        return await provider.fetchQuota()
    }
}
