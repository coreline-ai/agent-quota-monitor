import Foundation

struct CodexQuotaParser: QuotaPayloadParser {
    let provider = ProviderID.codex

    func parse(_ data: Data, observedAt: Date) throws -> ProviderSnapshot {
        let root: Root
        do { root = try JSONDecoder().decode(Root.self, from: data) }
        catch { throw ProviderErrorCode.malformedPayload }
        let limits = root.rateLimits ?? root.inline
        let provenance = ValueProvenance(
            source: .officialCLI,
            contract: .observed,
            observedAt: observedAt,
            freshness: .live
        )
        var windows: [QuotaWindow] = []
        if let value = limits.primary,
           let window = try makeWindow(.primary, value, provenance) { windows.append(window) }
        if let value = limits.secondary,
           let window = try makeWindow(.secondary, value, provenance) { windows.append(window) }

        var credits: CreditBalance?
        if let value = limits.credits {
            credits = CreditBalance(
                amount: value.balance.flatMap { Decimal(string: $0) },
                unlimited: value.unlimited ?? false,
                provenance: provenance
            )
        }
        return ProviderSnapshot(
            provider: provider,
            state: windows.count == 2 ? .available : .partial,
            windows: windows,
            credits: credits,
            lastAttempt: nil,
            lastSuccessAt: observedAt
        )
    }

    private func makeWindow(
        _ kind: QuotaWindowKind,
        _ value: Window,
        _ provenance: ValueProvenance
    ) throws -> QuotaWindow? {
        guard let percent = value.usedPercent else { return nil }
        return try QuotaWindow(
            kind: kind,
            usedRatio: QuotaRatio(percent: percent),
            resetsAt: value.resetsAt.map { Date(timeIntervalSince1970: $0) },
            provenance: provenance
        )
    }

    private struct Root: Decodable {
        let rateLimits: Limits?
        let primary: Window?
        let secondary: Window?
        let credits: Credits?
        var inline: Limits { Limits(primary: primary, secondary: secondary, credits: credits) }
    }

    private struct Limits: Decodable {
        let primary: Window?
        let secondary: Window?
        let credits: Credits?
    }

    private struct Window: Decodable {
        let usedPercent: Double?
        let resetsAt: TimeInterval?
        let windowDurationMins: Int?
    }

    private struct Credits: Decodable {
        let balance: String?
        let hasCredits: Bool?
        let unlimited: Bool?
    }
}
