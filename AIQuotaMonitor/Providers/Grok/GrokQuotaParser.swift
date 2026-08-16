import Foundation

struct GrokQuotaParser: QuotaPayloadParser {
    let provider = ProviderID.grok

    func parse(_ data: Data, observedAt: Date) throws -> ProviderSnapshot {
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: data) }
        catch { throw ProviderErrorCode.malformedPayload }
        let provenance = ValueProvenance(
            source: .syntheticFixture,
            contract: .experimental,
            observedAt: observedAt,
            freshness: .unknown
        )
        var windows: [QuotaWindow] = []
        if let percent = payload.weekly?.usedPercentage {
            windows.append(try QuotaWindow(
                kind: .sharedWeekly,
                usedRatio: QuotaRatio(percent: percent),
                resetsAt: payload.weekly?.resetsAt.map { Date(timeIntervalSince1970: $0) },
                provenance: provenance
            ))
        }
        return ProviderSnapshot(
            provider: provider,
            state: .unsupportedContract,
            windows: windows,
            credits: nil,
            lastAttempt: nil,
            lastSuccessAt: nil
        )
    }

    private struct Payload: Decodable {
        let weekly: Window?
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
