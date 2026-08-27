import Foundation

enum AppPreferences {
    private static let uiTestSuiteName = "ai.coreline.quotabeacon.uitests"

    static var current: UserDefaults {
        guard ProcessInfo.processInfo.environment["AIQUOTAMONITOR_UI_TEST"] == "1" else {
            return .standard
        }
        return UserDefaults(suiteName: uiTestSuiteName) ?? .standard
    }

    static func resetUITestDomain() {
        guard ProcessInfo.processInfo.environment["AIQUOTAMONITOR_UI_TEST"] == "1" else { return }
        current.removePersistentDomain(forName: uiTestSuiteName)
    }
}
