import Foundation

struct RefreshPolicy: Sendable {
    static let standard = Self()

    func interval(
        popoverVisible: Bool,
        idle: Bool,
        consecutiveFailures: Int,
        configuredMinutes: Int = 5
    ) -> Duration {
        if consecutiveFailures >= 3 { return .seconds(60 * 60) }
        if consecutiveFailures >= 1 { return .seconds(15 * 60) }
        let configuredInterval = Duration.seconds(Int64(max(1, configuredMinutes) * 60))
        // An open popover should feel current even if the background cadence is
        // intentionally longer. The user's one-minute preference remains the
        // lower bound; we do not poll providers more often than once a minute.
        if popoverVisible { return min(configuredInterval, .seconds(60)) }
        if idle { return .seconds(15 * 60) }
        return configuredInterval
    }
}
