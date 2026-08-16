import Foundation

struct TokenBreakdown: Codable, Hashable, Sendable {
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int

    static let zero = Self(input: 0, output: 0, cacheRead: 0, cacheWrite: 0)

    var total: Int { input + output + cacheRead + cacheWrite }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite
        )
    }
}

struct LocalUsageSample: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let provider: ProviderID
    let occurredAt: Date
    let model: String
    let projectLabel: String?
    let tokens: TokenBreakdown
}

struct EstimatedCost: Codable, Hashable, Sendable {
    let currencyCode: String
    let amount: Decimal
    let catalogVersion: String
    let disclaimer: String
}
