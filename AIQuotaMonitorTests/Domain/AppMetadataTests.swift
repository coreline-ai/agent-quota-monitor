import XCTest
@testable import AIQuotaMonitor

final class AppMetadataTests: XCTestCase {
    func testGreenfieldMetadataUsesExpectedWorkingIdentity() {
        XCTAssertEqual(AppMetadata.internalName, "AIQuotaMonitor")
        XCTAssertEqual(AppMetadata.displayName, "QuotaBeacon")
        XCTAssertEqual(AppMetadata.bundleIdentifier, "com.hwanchoi.quotabeacon")
        XCTAssertEqual(AppMetadata.minimumMacOSMajorVersion, 14)
        XCTAssertTrue(AppMetadata.isGreenfieldImplementation)
    }
}
