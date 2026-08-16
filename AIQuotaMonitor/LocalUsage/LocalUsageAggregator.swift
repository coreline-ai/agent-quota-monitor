import Foundation

struct LocalUsageBucket: Sendable, Equatable {
    let provider: ProviderID
    let day: Date
    let projectLabel: String?
    let tokens: TokenBreakdown
}

enum LocalUsageAggregator {
    static func daily(
        _ samples: [LocalUsageSample],
        calendar: Calendar = .current
    ) -> [LocalUsageBucket] {
        struct Key: Hashable {
            let provider: ProviderID
            let day: Date
            let project: String?
        }
        let values = Dictionary(grouping: samples) {
            Key(provider: $0.provider, day: calendar.startOfDay(for: $0.occurredAt), project: $0.projectLabel)
        }
        return values.map { key, samples in
            LocalUsageBucket(
                provider: key.provider,
                day: key.day,
                projectLabel: key.project,
                tokens: samples.reduce(.zero) { $0 + $1.tokens }
            )
        }
        .sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            if $0.provider != $1.provider { return $0.provider.rawValue < $1.provider.rawValue }
            return ($0.projectLabel ?? "") < ($1.projectLabel ?? "")
        }
    }
}
