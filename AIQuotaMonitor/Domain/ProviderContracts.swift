import Foundation

enum ProviderAvailability: Sendable, Equatable {
    case available
    case notConfigured
    case unsupported(reason: String)
}

struct ProviderFetchResult: Sendable {
    let snapshot: ProviderSnapshot
}

enum ProviderRefreshPolicy: Sendable, Equatable {
    case scheduled
    case userInitiated

    var allowsCachedSuccess: Bool {
        self == .scheduled
    }
}

protocol QuotaProvider: Sendable {
    var id: ProviderID { get }
    func availability() async -> ProviderAvailability
    func fetchQuota() async -> ProviderFetchResult
    func fetchQuota(policy: ProviderRefreshPolicy) async -> ProviderFetchResult
}

extension QuotaProvider {
    func fetchQuota(policy: ProviderRefreshPolicy) async -> ProviderFetchResult {
        await fetchQuota()
    }
}

protocol LocalUsageSource: Sendable {
    var provider: ProviderID { get }
    func loadUsage(in interval: DateInterval) async throws -> [LocalUsageSample]
}
