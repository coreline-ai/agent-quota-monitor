import Foundation

struct GrokQuotaParser: QuotaPayloadParser {
    let provider = ProviderID.grok

    func parse(_ data: Data, observedAt: Date) throws -> ProviderSnapshot {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ProviderErrorCode.malformedPayload
        }
        guard let config = payload.config else {
            throw ProviderErrorCode.forbidden
        }

        let provenance = ValueProvenance(
            source: .officialCLI,
            contract: .observed,
            observedAt: observedAt,
            freshness: .live
        )
        let percent = try usedPercent(from: config)
        let reset = parseDate(config.currentPeriod?.end ?? config.billingPeriodEnd)
        let windows = try percent.map { value in
            [QuotaWindow(
                kind: windowKind(for: config.currentPeriod?.periodType),
                usedRatio: try QuotaRatio(percent: value),
                resetsAt: reset,
                provenance: provenance
            )]
        } ?? []

        let credits: CreditBalance?
        if let balance = config.prepaidBalance?.val {
            guard balance >= 0 else { throw ProviderErrorCode.malformedPayload }
            credits = CreditBalance(
                amount: Decimal(balance) / Decimal(100),
                unlimited: false,
                provenance: provenance
            )
        } else {
            credits = nil
        }
        let state: ProviderState = windows.isEmpty || reset == nil ? .partial : .available
        return ProviderSnapshot(
            provider: provider,
            state: state,
            windows: windows,
            credits: credits,
            lastAttempt: nil,
            lastSuccessAt: observedAt
        )
    }

    private func usedPercent(from config: BillingConfig) throws -> Double? {
        if let percent = config.creditUsagePercent {
            guard percent.isFinite, (0 ... 100).contains(percent) else {
                throw ProviderErrorCode.malformedPayload
            }
            return percent
        }
        guard let limit = config.monthlyLimit?.val,
              let used = config.used?.val,
              limit > 0 else {
            return nil
        }
        let percent = Double(used) / Double(limit) * 100
        guard percent.isFinite, (0 ... 100).contains(percent) else {
            throw ProviderErrorCode.malformedPayload
        }
        return percent
    }

    private func windowKind(for periodType: String?) -> QuotaWindowKind {
        let normalized = periodType?.uppercased() ?? ""
        switch normalized {
        case let value where value.contains("WEEK"):
            return .sharedWeekly
        case let value where value.contains("MONTH"):
            return .custom("월간 공용")
        default:
            // Do not infer a five-hour subscription window from a future or
            // unknown billing period. Only observed official period contracts
            // receive a dedicated product label.
            return .custom("공용 크레딧")
        }
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private struct Payload: Decodable {
        let config: BillingConfig?
    }

    private struct BillingConfig: Decodable {
        let creditUsagePercent: Double?
        let currentPeriod: UsagePeriod?
        let monthlyLimit: Cent?
        let used: Cent?
        let prepaidBalance: Cent?
        let billingPeriodEnd: String?
    }

    private struct UsagePeriod: Decodable {
        let periodType: String?
        let end: String?

        enum CodingKeys: String, CodingKey {
            case periodType = "type"
            case end
        }
    }

    private struct Cent: Decodable {
        let val: Int64?
    }
}
