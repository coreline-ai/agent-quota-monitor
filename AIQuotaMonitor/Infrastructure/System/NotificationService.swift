import Foundation
import UserNotifications

struct NotificationKey: Hashable, Sendable {
    let provider: ProviderID
    let windowInstance: String
    let event: String
}

enum QuotaAlertEvaluator {
    static func event(for remainingRatio: Double) -> String? {
        if remainingRatio <= 0 { return "exhausted" }
        if remainingRatio <= 0.1 { return "10" }
        if remainingRatio <= 0.25 { return "25" }
        return nil
    }
}

actor NotificationDeduplicator {
    private var delivered = Set<NotificationKey>()

    func shouldDeliver(_ key: NotificationKey) -> Bool {
        delivered.insert(key).inserted
    }

    func reset(provider: ProviderID, keepingWindowInstance: String) {
        delivered = delivered.filter {
            $0.provider != provider || $0.windowInstance == keepingWindowInstance
        }
    }
}

actor NotificationService {
    private let center = UNUserNotificationCenter.current()
    private let deduplicator = NotificationDeduplicator()

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func notifyIfNeeded(
        key: NotificationKey,
        title: String,
        body: String,
        quietHours: DateInterval? = nil,
        now: Date = Date()
    ) async throws {
        if let quietHours, quietHours.contains(now) { return }
        guard await deduplicator.shouldDeliver(key) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: "\(key.provider.rawValue).\(key.windowInstance).\(key.event)",
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }
}
