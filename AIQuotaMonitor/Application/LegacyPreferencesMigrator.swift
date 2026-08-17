import Foundation

enum LegacyPreferencesMigrator {
    private static let legacyDomainIdentifier = "com.hwanchoi.quotabeacon"
    private static let migrationKey = "identityMigration.coreline.v1"
    private static let migratedKeys = [
        "codex.readOnlyEnabled",
        "codex.executablePath",
        "claude.readOnlyEnabled",
        "claude.snapshotEnabled",
        "grok.readOnlyEnabled",
        "grok.authPath",
        "zai.readOnlyEnabled",
        "notifications.authorized",
        "notifications.enabled",
        "quietHours.enabled",
        "refresh.minutes",
        "appearance.density",
        "appearance.metricMode",
        "appearance.resetStyle",
        "appearance.theme",
        "appearance.inspectorMode",
        "appearance.provider.claude.visible",
        "appearance.provider.codex.visible",
        "appearance.provider.grok.visible",
        "appearance.provider.zai.visible"
    ]

    static func migrateIfNeeded(
        defaults: UserDefaults = .standard,
        legacyBundleIdentifier: String = legacyDomainIdentifier
    ) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        defer { defaults.set(true, forKey: migrationKey) }

        guard let legacy = defaults.persistentDomain(forName: legacyBundleIdentifier) else {
            return
        }

        for key in migratedKeys where defaults.object(forKey: key) == nil {
            if let value = legacy[key] {
                defaults.set(value, forKey: key)
            }
        }
    }
}
