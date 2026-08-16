import Foundation

enum ProviderAvailability: Sendable, Equatable {
    case available
    case notConfigured
    case unsupported(reason: String)
}

struct ProviderFetchResult: Sendable {
    let snapshot: ProviderSnapshot
}

protocol QuotaProvider: Sendable {
    var id: ProviderID { get }
    func availability() async -> ProviderAvailability
    func fetchQuota() async -> ProviderFetchResult
}

protocol LocalUsageSource: Sendable {
    var provider: ProviderID { get }
    func loadUsage(in interval: DateInterval) async throws -> [LocalUsageSample]
}
