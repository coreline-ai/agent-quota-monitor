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
              sameResetInstance(first.resetsAt, last.resetsAt) else { return nil }
        let elapsed = last.provenance.observedAt.timeIntervalSince(first.provenance.observedAt)
        let consumed = last.usedRatio.value - first.usedRatio.value
        guard elapsed > 0, consumed > 0 else { return nil }
        let secondsPerRatio = elapsed / consumed
        let predicted = last.provenance.observedAt.addingTimeInterval((1 - last.usedRatio.value) * secondsPerRatio)
        if let reset = last.resetsAt, predicted >= reset { return nil }
        return PaceEstimate(exhaustionAt: predicted, samples: fresh.count)
    }

    private static func sameResetInstance(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?):
            // Countdown-based providers can drift by fractions of a second at each poll.
            // Reset-minute identity keeps one real quota window together without joining
            // genuinely different reset cycles.
            return Int64((lhs.timeIntervalSince1970 / 60).rounded())
                == Int64((rhs.timeIntervalSince1970 / 60).rounded())
        default: return false
        }
    }
}
