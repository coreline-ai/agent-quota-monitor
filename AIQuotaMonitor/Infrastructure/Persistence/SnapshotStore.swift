import Foundation

actor SnapshotStore {
    private var snapshots: [ProviderID: ProviderSnapshot] = [:]

    func snapshot(for provider: ProviderID) -> ProviderSnapshot? {
        snapshots[provider]
    }

    func all() -> [ProviderSnapshot] {
        ProviderID.allCases.compactMap { snapshots[$0] }
    }

    @discardableResult
    func merge(_ incoming: ProviderSnapshot) -> ProviderSnapshot {
        let merged = incoming.mergingLastKnownGood(snapshots[incoming.provider])
        snapshots[incoming.provider] = merged
        return merged
    }

    func removeAll() {
        snapshots.removeAll()
    }
}
