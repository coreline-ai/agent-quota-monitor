import Foundation

struct ZAIQuotaParser: QuotaPayloadParser {
    let provider = ProviderID.zai

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
        let windows = try payload.limits.compactMap { value -> QuotaWindow? in
            guard let percent = value.usedPercentage else { return nil }
            let kind: QuotaWindowKind = switch value.type {
            case "session": .session
            case "weekly": .sevenDay
            default: .custom(value.type)
            }
            return try QuotaWindow(
                kind: kind,
                usedRatio: QuotaRatio(percent: percent),
                resetsAt: value.resetsAt.map { Date(timeIntervalSince1970: $0) },
                provenance: provenance
            )
        }
        let credits = payload.credits.map {
            CreditBalance(
                amount: Decimal(string: $0.balance),
                unlimited: false,
                provenance: provenance
            )
        }
        return ProviderSnapshot(
            provider: provider,
            state: .unsupportedContract,
            windows: windows,
            credits: credits,
            lastAttempt: nil,
            lastSuccessAt: nil
        )
    }

    private struct Payload: Decodable {
        let limits: [Limit]
        let credits: Credits?
    }
    private struct Limit: Decodable {
        let type: String
        let usedPercentage: Double?
        let resetsAt: TimeInterval?
        enum CodingKeys: String, CodingKey {
            case type
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }
    }
    private struct Credits: Decodable { let balance: String }
}
