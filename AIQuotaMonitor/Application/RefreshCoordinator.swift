import Foundation

actor RefreshCoordinator {
    private let providers: [ProviderID: any QuotaProvider]
    private let store: SnapshotStore
    private var active: [ProviderID: Task<ProviderFetchResult, Never>] = [:]

    init(providers: [any QuotaProvider], store: SnapshotStore) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.store = store
    }

    func refresh(
        _ providerID: ProviderID,
        policy: ProviderRefreshPolicy = .scheduled
    ) async -> ProviderSnapshot? {
        guard let provider = providers[providerID] else { return nil }
        if let existing = active[providerID] { return await existing.value.snapshot }
        let task = Task { await provider.fetchQuota(policy: policy) }
        active[providerID] = task
        let result = await task.value
        active[providerID] = nil
        return await store.merge(result.snapshot)
    }

    func refreshAll(policy: ProviderRefreshPolicy = .scheduled) async -> [ProviderSnapshot] {
        await withTaskGroup(of: ProviderSnapshot?.self) { group in
            for provider in ProviderID.allCases {
                group.addTask { await self.refresh(provider, policy: policy) }
            }
            var snapshots: [ProviderSnapshot] = []
            for await snapshot in group {
                if let snapshot { snapshots.append(snapshot) }
            }
            return snapshots.sorted { $0.provider.rawValue < $1.provider.rawValue }
        }
    }

    func cancelAll() {
        for task in active.values { task.cancel() }
        active.removeAll()
    }
}
