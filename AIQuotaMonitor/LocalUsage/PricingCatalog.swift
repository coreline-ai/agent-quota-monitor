import Foundation

struct PricingCatalog: Codable, Sendable {
    let version: String
    let effectiveDate: String
    let entries: [PricingEntry]

    func entry(for model: String) -> PricingEntry? {
        entries.first { $0.model == model || $0.aliases.contains(model) }
    }

    func estimate(for sample: LocalUsageSample) -> EstimatedCost? {
        guard let entry = entry(for: sample.model) else { return nil }
        let million = Decimal(1_000_000)
        let input = Decimal(sample.tokens.input) * entry.inputPerMillion / million
        let output = Decimal(sample.tokens.output) * entry.outputPerMillion / million
        let cacheRead = Decimal(sample.tokens.cacheRead) * entry.cacheReadPerMillion / million
        let cacheWrite = Decimal(sample.tokens.cacheWrite) * (entry.cacheWritePerMillion ?? entry.inputPerMillion) / million
        return EstimatedCost(
            currencyCode: "USD",
            amount: input + output + cacheRead + cacheWrite,
            catalogVersion: version,
            disclaimer: "API 정가 기준 예상 / 실제 구독 결제액 아님"
        )
    }
}

struct PricingEntry: Codable, Sendable {
    let provider: ProviderID
    let model: String
    let aliases: [String]
    let inputPerMillion: Decimal
    let outputPerMillion: Decimal
    let cacheReadPerMillion: Decimal
    let cacheWritePerMillion: Decimal?
    let sourceURL: URL
}

enum PricingCatalogLoader {
    static func bundled(bundle: Bundle = .main) throws -> PricingCatalog {
        guard let url = bundle.url(forResource: "PricingCatalog", withExtension: "json") else {
            throw ProviderErrorCode.io
        }
        return try JSONDecoder().decode(PricingCatalog.self, from: Data(contentsOf: url))
    }
}
