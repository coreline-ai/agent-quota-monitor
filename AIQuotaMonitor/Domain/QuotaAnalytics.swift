import Foundation

struct PaceEstimate: Sendable, Equatable {
    let exhaustionAt: Date
    let samples: Int
}

enum QuotaAnalytics {
    static func estimateExhaustion(from values: [QuotaWindow]) -> PaceEstimate? {
        let fresh = values
            .filter { $0.provenance.freshness == .live || $0.provenance.freshness == .recent }
            .sorted { $0.provenance.observedAt < $1.provenance.observedAt }
        guard fresh.count >= 3,
              let first = fresh.first,
              let last = fresh.last,
              first.kind == last.kind,
              first.resetsAt == last.resetsAt else { return nil }
        let elapsed = last.provenance.observedAt.timeIntervalSince(first.provenance.observedAt)
        let consumed = last.usedRatio.value - first.usedRatio.value
        guard elapsed > 0, consumed > 0 else { return nil }
        let secondsPerRatio = elapsed / consumed
        let predicted = last.provenance.observedAt.addingTimeInterval((1 - last.usedRatio.value) * secondsPerRatio)
        if let reset = last.resetsAt, predicted >= reset { return nil }
        return PaceEstimate(exhaustionAt: predicted, samples: fresh.count)
    }
}
