import Foundation

struct HistoryEnvelope: Codable, Sendable {
    let schemaVersion: Int
    var snapshots: [ProviderSnapshot]
}

struct HistoryRecordResult: Sendable {
    let snapshots: [ProviderSnapshot]
    let changed: Bool
}

enum HistoryStoreError: Error {
    case unsupportedSchema(Int)
}

actor HistoryStore {
    static let schemaVersion = 1
    static let maximumBytes = 8 * 1_024 * 1_024
    static let retentionDays = 30

    private static let bucketDuration: TimeInterval = 5 * 60

    private let fileURL: URL
    private let calendar: Calendar
    private var cachedSnapshots: [ProviderSnapshot]?

    init(fileURL: URL, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.fileURL = fileURL
        self.calendar = calendar
    }

    func load(now: Date = Date()) throws -> [ProviderSnapshot] {
        if let cachedSnapshots { return cachedSnapshots }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cachedSnapshots = []
            return []
        }

        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let envelope: HistoryEnvelope
        do {
            envelope = try JSONDecoder().decode(HistoryEnvelope.self, from: data)
            guard envelope.schemaVersion == Self.schemaVersion else {
                throw HistoryStoreError.unsupportedSchema(envelope.schemaVersion)
            }
        } catch {
            quarantineCorruptFile()
            throw error
        }

        let compacted = compact(envelope.snapshots, now: now)
        let retained: [ProviderSnapshot]
        if compacted != envelope.snapshots || data.count > Self.maximumBytes {
            // The payload decoded successfully, so a failed maintenance rewrite
            // must not quarantine or hide otherwise usable history.
            retained = (try? persist(compacted)) ?? compacted
        } else {
            retained = compacted
        }
        cachedSnapshots = retained
        return retained
    }

    @discardableResult
    func save(_ snapshots: [ProviderSnapshot], now: Date = Date()) throws -> [ProviderSnapshot] {
        let retained = try persist(compact(snapshots, now: now))
        cachedSnapshots = retained
        return retained
    }

    func record(_ snapshots: [ProviderSnapshot], now: Date = Date()) throws -> HistoryRecordResult {
        let current = try load(now: now)
        guard snapshots.contains(where: { !$0.windows.isEmpty }) else {
            return HistoryRecordResult(snapshots: current, changed: false)
        }

        var candidates = current
        candidates.append(contentsOf: snapshots)
        let compacted = compact(candidates, now: now)
        guard compacted != current else {
            return HistoryRecordResult(snapshots: current, changed: false)
        }

        let retained = try persist(compacted)
        cachedSnapshots = retained
        return HistoryRecordResult(snapshots: retained, changed: retained != current)
    }

    func delete() throws {
        cachedSnapshots = []
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func compact(_ snapshots: [ProviderSnapshot], now: Date) -> [ProviderSnapshot] {
        let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now) ?? now
        var buckets: [HistoryBucketKey: ProviderSnapshot] = [:]
        buckets.reserveCapacity(min(snapshots.count, 10_000))

        for snapshot in snapshots {
            guard let observedAt = observationDate(for: snapshot), observedAt >= cutoff else { continue }
            let key = HistoryBucketKey(snapshot: snapshot, observedAt: observedAt)
            guard let existing = buckets[key] else {
                buckets[key] = snapshot
                continue
            }
            if shouldReplace(existing, with: snapshot) {
                buckets[key] = snapshot
            }
        }

        return buckets.values.sorted { lhs, rhs in
            let lhsDate = observationDate(for: lhs) ?? .distantPast
            let rhsDate = observationDate(for: rhs) ?? .distantPast
            if lhsDate == rhsDate { return lhs.provider.rawValue < rhs.provider.rawValue }
            return lhsDate < rhsDate
        }
    }

    private func shouldReplace(_ existing: ProviderSnapshot, with candidate: ProviderSnapshot) -> Bool {
        let existingFreshness = freshnessRank(for: existing)
        let candidateFreshness = freshnessRank(for: candidate)
        if candidateFreshness != existingFreshness {
            return candidateFreshness > existingFreshness
        }

        // Repeated polling frequently changes only timestamps. Keeping the first
        // equivalent observation in a five-minute bucket avoids a JSON rewrite
        // and a new published history array for no user-visible information.
        if hasEquivalentPayload(existing, candidate) { return false }

        let existingDate = observationDate(for: existing) ?? .distantPast
        let candidateDate = observationDate(for: candidate) ?? .distantPast
        if candidateDate != existingDate { return candidateDate > existingDate }
        return (candidate.lastAttempt?.finishedAt ?? .distantPast)
            > (existing.lastAttempt?.finishedAt ?? .distantPast)
    }

    private func hasEquivalentPayload(_ lhs: ProviderSnapshot, _ rhs: ProviderSnapshot) -> Bool {
        guard lhs.provider == rhs.provider,
              lhs.state == rhs.state,
              lhs.windows.count == rhs.windows.count,
              equivalentCredits(lhs.credits, rhs.credits) else {
            return false
        }

        let lhsWindows = lhs.windows.sorted { windowIdentity($0) < windowIdentity($1) }
        let rhsWindows = rhs.windows.sorted { windowIdentity($0) < windowIdentity($1) }
        return zip(lhsWindows, rhsWindows).allSatisfy { left, right in
            left.kind == right.kind
                && left.usedRatio == right.usedRatio
                && left.resetsAt == right.resetsAt
                && left.provenance.source.rawValue == right.provenance.source.rawValue
                && left.provenance.contract.rawValue == right.provenance.contract.rawValue
                && left.provenance.freshness.rawValue == right.provenance.freshness.rawValue
        }
    }

    private func equivalentCredits(_ lhs: CreditBalance?, _ rhs: CreditBalance?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return left.amount == right.amount
                && left.unlimited == right.unlimited
                && left.provenance.source.rawValue == right.provenance.source.rawValue
                && left.provenance.contract.rawValue == right.provenance.contract.rawValue
                && left.provenance.freshness.rawValue == right.provenance.freshness.rawValue
        default:
            return false
        }
    }

    private func freshnessRank(for snapshot: ProviderSnapshot) -> Int {
        snapshot.windows.map { window in
            switch window.provenance.freshness {
            case .live: 3
            case .recent: 2
            case .stale: 1
            case .unknown: 0
            }
        }.max() ?? 0
    }

    private func observationDate(for snapshot: ProviderSnapshot) -> Date? {
        snapshot.windows.map(\.provenance.observedAt).max()
    }

    private func windowIdentity(_ window: QuotaWindow) -> String {
        let resetMinute = window.resetsAt.map { String(Int64($0.timeIntervalSince1970 / 60)) } ?? "none"
        return "\(kindToken(window.kind))|\(resetMinute)"
    }

    private func kindToken(_ kind: QuotaWindowKind) -> String {
        switch kind {
        case .fiveHour: "fiveHour"
        case .sevenDay: "sevenDay"
        case .primary: "primary"
        case .secondary: "secondary"
        case .sharedWeekly: "sharedWeekly"
        case .session: "session"
        case let .custom(value): "custom:\(value)"
        }
    }

    private func persist(_ snapshots: [ProviderSnapshot]) throws -> [ProviderSnapshot] {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var retained = snapshots
        var data = try encode(retained)
        if data.count > Self.maximumBytes, !retained.isEmpty {
            let targetFraction = Double(Self.maximumBytes) / Double(data.count) * 0.92
            let targetCount = max(1, Int(Double(retained.count) * targetFraction))
            retained = Array(retained.suffix(targetCount))
            data = try encode(retained)
        }
        while data.count > Self.maximumBytes, !retained.isEmpty {
            retained.removeFirst(max(1, retained.count / 20))
            data = try encode(retained)
        }
        try data.write(to: fileURL, options: [.atomic])
        return retained
    }

    private func encode(_ snapshots: [ProviderSnapshot]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(HistoryEnvelope(schemaVersion: Self.schemaVersion, snapshots: snapshots))
    }

    private func quarantineCorruptFile() {
        let quarantine = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: fileURL, to: quarantine)
    }

    private struct HistoryBucketKey: Hashable {
        let provider: ProviderID
        let bucket: Int64
        let windows: [String]

        init(snapshot: ProviderSnapshot, observedAt: Date) {
            provider = snapshot.provider
            bucket = Int64(observedAt.timeIntervalSince1970 / HistoryStore.bucketDuration)
            windows = snapshot.windows.map { window in
                let resetMinute = window.resetsAt.map { String(Int64($0.timeIntervalSince1970 / 60)) } ?? "none"
                let kind: String
                switch window.kind {
                case .fiveHour: kind = "fiveHour"
                case .sevenDay: kind = "sevenDay"
                case .primary: kind = "primary"
                case .secondary: kind = "secondary"
                case .sharedWeekly: kind = "sharedWeekly"
                case .session: kind = "session"
                case let .custom(value): kind = "custom:\(value)"
                }
                return "\(kind)|\(resetMinute)"
            }.sorted()
        }
    }
}
