import Foundation

struct HistoryEnvelope: Codable, Sendable {
    let schemaVersion: Int
    var snapshots: [ProviderSnapshot]
}

enum HistoryStoreError: Error {
    case unsupportedSchema(Int)
}

actor HistoryStore {
    static let schemaVersion = 1
    static let maximumBytes = 25 * 1_024 * 1_024
    static let retentionDays = 90

    private let fileURL: URL
    private let calendar: Calendar

    init(fileURL: URL, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.fileURL = fileURL
        self.calendar = calendar
    }

    func load() throws -> [ProviderSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let envelope = try JSONDecoder().decode(HistoryEnvelope.self, from: data)
            guard envelope.schemaVersion == Self.schemaVersion else {
                throw HistoryStoreError.unsupportedSchema(envelope.schemaVersion)
            }
            return envelope.snapshots
        } catch {
            let quarantine = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: quarantine)
            throw error
        }
    }

    func save(_ snapshots: [ProviderSnapshot], now: Date = Date()) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now) ?? now
        var retained = snapshots.filter { ($0.lastAttempt?.finishedAt ?? $0.lastSuccessAt ?? now) >= cutoff }
        var data = try encode(retained)
        while data.count > Self.maximumBytes, !retained.isEmpty {
            retained.removeFirst(max(1, retained.count / 10))
            data = try encode(retained)
        }
        try data.write(to: fileURL, options: [.atomic])
    }

    func delete() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func encode(_ snapshots: [ProviderSnapshot]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(HistoryEnvelope(schemaVersion: Self.schemaVersion, snapshots: snapshots))
    }
}
