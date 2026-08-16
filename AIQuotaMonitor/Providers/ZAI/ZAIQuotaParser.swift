import Foundation

struct ZAIQuotaParser: QuotaPayloadParser {
    let provider = ProviderID.zai

    func parse(_ data: Data, observedAt: Date) throws -> ProviderSnapshot {
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: data) }
        catch { throw ProviderErrorCode.malformedPayload }
        let provenance = ValueProvenance(
            source: .officialCLI,
            contract: .observed,
            observedAt: observedAt,
            freshness: .live
        )
        let windows = try payload.limits.compactMap { value -> QuotaWindow? in
            guard let percent = value.percentage else { return nil }
            let kind: QuotaWindowKind
            switch value.type {
            case "Token usage(5 Hour)", "TOKENS_LIMIT": kind = .fiveHour
            case "MCP usage(1 Month)", "TIME_LIMIT": kind = .custom("MCP 월간")
            default: return nil
            }
            return try QuotaWindow(
                kind: kind,
                usedRatio: QuotaRatio(percent: percent),
                resetsAt: nil,
                provenance: provenance
            )
        }
        guard !windows.isEmpty else { throw ProviderErrorCode.malformedPayload }
        return ProviderSnapshot(
            provider: provider,
            state: windows.count >= 2 ? .available : .partial,
            windows: windows,
            credits: nil,
            lastAttempt: nil,
            lastSuccessAt: observedAt
        )
    }

    private struct Payload: Decodable {
        let limits: [Limit]
    }
    private struct Limit: Decodable {
        let type: String
        let percentage: Double?
    }
}
