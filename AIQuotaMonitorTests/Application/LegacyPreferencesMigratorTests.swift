import Foundation
import XCTest
@testable import AIQuotaMonitor

final class LegacyPreferencesMigratorTests: XCTestCase {
    func testCopiesAllowlistedLegacyPreferences() throws {
        let suiteName = "ai.coreline.quotabeacon.tests.\(UUID().uuidString)"
        let legacyName = "legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            defaults.removePersistentDomain(forName: legacyName)
        }
        defaults.setPersistentDomain(
            [
                "claude.readOnlyEnabled": true,
                "gemini.readOnlyEnabled": true,
                "gemini.executablePath": "/tmp/synthetic-agy",
                "appearance.provider.gemini.visible": false,
                "appearance.theme": "midnight",
                "unrelated.secret": "must-not-migrate"
            ],
            forName: legacyName
        )

        LegacyPreferencesMigrator.migrateIfNeeded(
            defaults: defaults,
            legacyBundleIdentifier: legacyName
        )

        XCTAssertTrue(defaults.bool(forKey: "claude.readOnlyEnabled"))
        XCTAssertTrue(defaults.bool(forKey: "gemini.readOnlyEnabled"))
        XCTAssertEqual(defaults.string(forKey: "gemini.executablePath"), "/tmp/synthetic-agy")
        XCTAssertFalse(defaults.bool(forKey: "appearance.provider.gemini.visible"))
        XCTAssertEqual(defaults.string(forKey: "appearance.theme"), "midnight")
        XCTAssertNil(defaults.object(forKey: "unrelated.secret"))
    }

    func testDoesNotOverwriteCurrentPreference() throws {
        let suiteName = "ai.coreline.quotabeacon.tests.\(UUID().uuidString)"
        let legacyName = "legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            defaults.removePersistentDomain(forName: legacyName)
        }
        defaults.set("graphite", forKey: "appearance.theme")
        defaults.setPersistentDomain(["appearance.theme": "midnight"], forName: legacyName)

        LegacyPreferencesMigrator.migrateIfNeeded(
            defaults: defaults,
            legacyBundleIdentifier: legacyName
        )

        XCTAssertEqual(defaults.string(forKey: "appearance.theme"), "graphite")
    }
}
