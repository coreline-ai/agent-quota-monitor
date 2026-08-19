import Foundation

struct ProviderDisplayOrder: Equatable, Sendable {
    static let defaultProviders: [ProviderID] = [.claude, .codex, .gemini, .grok, .zai]

    let providers: [ProviderID]

    init(_ providers: [ProviderID] = Self.defaultProviders) {
        self.providers = Self.normalized(providers)
    }

    init(storageValue: String?) {
        let parsed = storageValue?
            .split(separator: ",", omittingEmptySubsequences: false)
            .compactMap { ProviderID(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            ?? []
        self.init(parsed)
    }

    var storageValue: String {
        providers.map(\.rawValue).joined(separator: ",")
    }

    static var defaultStorageValue: String {
        Self().storageValue
    }

    func moving(_ provider: ProviderID, by offset: Int) -> Self {
        guard let currentIndex = providers.firstIndex(of: provider) else { return self }
        let destination = currentIndex + offset
        guard providers.indices.contains(destination) else { return self }

        var values = providers
        let moved = values.remove(at: currentIndex)
        values.insert(moved, at: destination)
        return Self(values)
    }

    func moving(_ provider: ProviderID, before destination: ProviderID) -> Self {
        guard provider != destination,
              let sourceIndex = providers.firstIndex(of: provider),
              let destinationIndex = providers.firstIndex(of: destination) else {
            return self
        }

        var values = providers
        let moved = values.remove(at: sourceIndex)
        let updatedDestination = values.firstIndex(of: destination) ?? destinationIndex
        values.insert(moved, at: updatedDestination)
        return Self(values)
    }

    func ordered(_ snapshots: [ProviderSnapshot]) -> [ProviderSnapshot] {
        let ranks = Dictionary(uniqueKeysWithValues: providers.enumerated().map { ($0.element, $0.offset) })
        return snapshots.enumerated().sorted { lhs, rhs in
            let left = (ranks[lhs.element.provider] ?? .max, lhs.offset)
            let right = (ranks[rhs.element.provider] ?? .max, rhs.offset)
            return left < right
        }
        .map(\.element)
    }

    private static func normalized(_ proposed: [ProviderID]) -> [ProviderID] {
        var seen = Set<ProviderID>()
        let unique = proposed.filter { seen.insert($0).inserted }
        return unique + defaultProviders.filter { !seen.contains($0) }
    }
}
