import Foundation

struct RefreshPolicy: Sendable {
    static let standard = Self()

    func interval(popoverVisible: Bool, idle: Bool, consecutiveFailures: Int) -> Duration {
        if consecutiveFailures >= 3 { return .seconds(60 * 60) }
        if consecutiveFailures >= 1 { return .seconds(15 * 60) }
        if popoverVisible { return .seconds(60) }
        if idle { return .seconds(15 * 60) }
        return .seconds(5 * 60)
    }
}
