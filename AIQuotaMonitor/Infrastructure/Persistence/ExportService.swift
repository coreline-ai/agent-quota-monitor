import Foundation

enum ExportFormat: String, CaseIterable, Sendable {
    case json
    case csv
}

enum ExportService {
    static func data(for snapshots: [ProviderSnapshot], format: ExportFormat) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(snapshots.map(ExportSnapshot.init))
        case .csv:
            var rows = ["provider,state,window,used_ratio,reset_at,source,freshness"]
            for snapshot in snapshots {
                if snapshot.windows.isEmpty {
                    rows.append("\(snapshot.provider.rawValue),\(snapshot.state.rawValue),,,,,")
                }
                for window in snapshot.windows {
                    rows.append([
                        snapshot.provider.rawValue,
                        snapshot.state.rawValue,
                        csv(window.kind.label),
                        String(format: "%.4f", window.usedRatio.value),
                        window.resetsAt.map(ISO8601DateFormatter().string) ?? "",
                        window.provenance.source.rawValue,
                        window.provenance.freshness.rawValue
                    ].joined(separator: ","))
                }
            }
            return Data((rows.joined(separator: "\n") + "\n").utf8)
        }
    }

    private static func csv(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private struct ExportSnapshot: Encodable {
        let provider: ProviderID
        let state: ProviderState
        let windows: [QuotaWindow]
        let credits: CreditBalance?
        let lastSuccessAt: Date?

        init(_ snapshot: ProviderSnapshot) {
            provider = snapshot.provider
            state = snapshot.state
            windows = snapshot.windows
            credits = snapshot.credits
            lastSuccessAt = snapshot.lastSuccessAt
        }
    }
}
