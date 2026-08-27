import Foundation

enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case grok
    case gemini
    case zai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .grok: "Grok Build"
        case .gemini: "Gemini · Antigravity"
        case .zai: "Z.ai GLM"
        }
    }
}

enum QuotaWindowKind: Hashable, Sendable {
    case fiveHour
    case sevenDay
    case primary
    case secondary
    case sharedWeekly
    case session
    case custom(String)

    var label: String {
        switch self {
        case .fiveHour: "5시간"
        case .sevenDay: "7일"
        case .primary: "기본 창"
        case .secondary: "보조 창"
        case .sharedWeekly: "주간 공용"
        case .session: "세션"
        case let .custom(value): value
        }
    }
}

extension QuotaWindowKind: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "fiveHour": self = .fiveHour
        case "sevenDay": self = .sevenDay
        case "primary": self = .primary
        case "secondary": self = .secondary
        case "sharedWeekly": self = .sharedWeekly
        case "session": self = .session
        case "custom": self = .custom(try container.decode(String.self, forKey: .value))
        default: self = .custom(type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fiveHour: try container.encode("fiveHour", forKey: .type)
        case .sevenDay: try container.encode("sevenDay", forKey: .type)
        case .primary: try container.encode("primary", forKey: .type)
        case .secondary: try container.encode("secondary", forKey: .type)
        case .sharedWeekly: try container.encode("sharedWeekly", forKey: .type)
        case .session: try container.encode("session", forKey: .type)
        case let .custom(value):
            try container.encode("custom", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

enum UsageSource: String, Codable, Sendable {
    case officialDocument
    case officialCLI
    case readOnlyFile
    case keychain
    case syntheticFixture
    case cache
}

enum SourceContractKind: String, Codable, Sendable {
    case documented
    case observed
    case experimental
}

enum DataFreshness: String, Codable, Sendable {
    case live
    case recent
    case stale
    case unknown
}

enum ProviderState: String, Codable, Sendable {
    case available
    case partial
    case stale
    case notConfigured
    case authenticationRequired
    case unsupportedAccount
    case unsupportedContract
    case rateLimited
    case offline
    case failed
}

enum ProviderErrorCode: String, Codable, Error, Sendable {
    case missingCredential
    case invalidCredential
    case forbidden
    case notFound
    case rateLimited
    case server
    case timeout
    case cancelled
    case malformedPayload
    case unsupported
    case io
}

enum QuotaValidationError: Error, Equatable {
    case invalidRatio
}

struct QuotaRatio: Codable, Hashable, Sendable {
    let value: Double

    init(_ value: Double) throws {
        guard value.isFinite, (0 ... 1).contains(value) else {
            throw QuotaValidationError.invalidRatio
        }
        self.value = value
    }

    init(percent: Double) throws {
        try self.init(percent / 100)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(Double.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct ValueProvenance: Codable, Hashable, Sendable {
    let source: UsageSource
    let contract: SourceContractKind
    let observedAt: Date
    let freshness: DataFreshness
}

struct QuotaWindow: Codable, Hashable, Identifiable, Sendable {
    let kind: QuotaWindowKind
    let usedRatio: QuotaRatio
    let resetsAt: Date?
    let provenance: ValueProvenance

    var id: String {
        "\(kind.label)-\(resetsAt?.timeIntervalSince1970 ?? 0)"
    }

    var remainingRatio: Double { 1 - usedRatio.value }
    var windowInstance: String { id }
}

struct CreditBalance: Codable, Hashable, Sendable {
    let amount: Decimal?
    let unlimited: Bool
    let provenance: ValueProvenance
}

struct RedactedDiagnostic: Codable, Hashable, Sendable {
    let summary: String
    let code: ProviderErrorCode?
}

struct CollectionAttempt: Codable, Hashable, Sendable {
    let startedAt: Date
    let finishedAt: Date
    let succeeded: Bool
    let diagnostic: RedactedDiagnostic?
}

struct ProviderSnapshot: Codable, Hashable, Identifiable, Sendable {
    let provider: ProviderID
    var state: ProviderState
    var windows: [QuotaWindow]
    var credits: CreditBalance?
    var lastAttempt: CollectionAttempt?
    var lastSuccessAt: Date?

    var id: ProviderID { provider }

    static func unavailable(_ provider: ProviderID, state: ProviderState) -> Self {
        Self(
            provider: provider,
            state: state,
            windows: [],
            credits: nil,
            lastAttempt: nil,
            lastSuccessAt: nil
        )
    }

    func mergingLastKnownGood(_ previous: ProviderSnapshot?) -> ProviderSnapshot {
        guard let previous, previous.provider == provider else { return self }
        var result = self
        if windows.isEmpty {
            result.windows = previous.windows.map { window in
                QuotaWindow(
                    kind: window.kind,
                    usedRatio: window.usedRatio,
                    resetsAt: window.resetsAt,
                    provenance: ValueProvenance(
                        source: window.provenance.source,
                        contract: window.provenance.contract,
                        observedAt: window.provenance.observedAt,
                        freshness: .stale
                    )
                )
            }
        }
        if credits == nil { result.credits = previous.credits }
        if lastSuccessAt == nil { result.lastSuccessAt = previous.lastSuccessAt }
        if result.state != .available, !result.windows.isEmpty { result.state = .stale }
        return result
    }

    func markingFreshness(_ freshness: DataFreshness) -> ProviderSnapshot {
        var result = self
        result.windows = windows.map { window in
            QuotaWindow(
                kind: window.kind,
                usedRatio: window.usedRatio,
                resetsAt: window.resetsAt,
                provenance: ValueProvenance(
                    source: window.provenance.source,
                    contract: window.provenance.contract,
                    observedAt: window.provenance.observedAt,
                    freshness: freshness
                )
            )
        }
        if let credits {
            result.credits = CreditBalance(
                amount: credits.amount,
                unlimited: credits.unlimited,
                provenance: ValueProvenance(
                    source: credits.provenance.source,
                    contract: credits.provenance.contract,
                    observedAt: credits.provenance.observedAt,
                    freshness: freshness
                )
            )
        }
        return result
    }
}
