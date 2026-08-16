import Foundation

struct ClaudeQuotaParser: QuotaPayloadParser {
    let provider = ProviderID.claude

    func parse(_ data: Data, observedAt: Date) throws -> ProviderSnapshot {
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: data) }
        catch { throw ProviderErrorCode.malformedPayload }

        let provenance = ValueProvenance(
            source: .readOnlyFile,
            contract: .documented,
            observedAt: observedAt,
            freshness: .live
        )
        var windows: [QuotaWindow] = []
        if let fiveHour = payload.rateLimits?.fiveHour,
           let window = try makeWindow(.fiveHour, from: fiveHour, provenance: provenance) {
            windows.append(window)
        }
        if let sevenDay = payload.rateLimits?.sevenDay,
           let window = try makeWindow(.sevenDay, from: sevenDay, provenance: provenance) {
            windows.append(window)
        }
        return ProviderSnapshot(
            provider: provider,
            state: windows.count == 2 ? .available : .partial,
            windows: windows,
            credits: nil,
            lastAttempt: nil,
            lastSuccessAt: observedAt
        )
    }

    private func makeWindow(
        _ kind: QuotaWindowKind,
        from value: Window,
        provenance: ValueProvenance
    ) throws -> QuotaWindow? {
        guard let percent = value.usedPercentage else { return nil }
        return try QuotaWindow(
            kind: kind,
            usedRatio: QuotaRatio(percent: percent),
            resetsAt: value.resetsAt.map { Date(timeIntervalSince1970: $0) },
            provenance: provenance
        )
    }

    private struct Payload: Decodable {
        let rateLimits: RateLimits?
        enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
    }

    private struct RateLimits: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    private struct Window: Decodable {
        let usedPercentage: Double?
        let resetsAt: TimeInterval?
        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }
    }
}
