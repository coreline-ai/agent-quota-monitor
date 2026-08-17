import XCTest

@MainActor
final class AIQuotaMonitorUITests: XCTestCase {
    func testMenuBarBeaconLedgerCanOpen() {
        let app = XCUIApplication()
        app.launchEnvironment["AIQUOTAMONITOR_UI_TEST"] = "1"
        app.launchEnvironment["AIQUOTAMONITOR_UI_TEST_POPOVER"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["dashboard.overview.title"].waitForExistence(timeout: 5))
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5))
        let summaryScreenshot = popover.screenshot()
        addScreenshot(summaryScreenshot, name: "quotabeacon-menu-ledger-summary-qa")

        // NSStatusItem popovers can expose their SwiftUI descendants outside the
        // application's button query. A coordinate relative to the verified
        // popover keeps this smoke test independent of ControlCenter's AX bridge.
        popover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.39)).click()
        let detailScreenshot = popover.screenshot()
        XCTAssertNotEqual(summaryScreenshot.pngRepresentation, detailScreenshot.pngRepresentation)
        addScreenshot(detailScreenshot, name: "quotabeacon-menu-ledger-detail-qa")
    }

    func testDashboardCanOpenForUITesting() {
        let app = XCUIApplication()
        app.launchEnvironment["AIQUOTAMONITOR_UI_TEST"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["dashboard.overview.title"].waitForExistence(timeout: 5))
        app.staticTexts["연결"].click()
        XCTAssertTrue(app.staticTexts["dashboard.connections.title"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["connections.apply"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["connections.gemini.toggle"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["connections.gemini.evidence"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["connections.zai.toggle"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["connections.zai.evidence"].exists)

        app.staticTexts["한도"].click()
        XCTAssertTrue(app.staticTexts["dashboard.limits.title"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["limits.provider.claude"].exists)
        let limitsScroll = app.scrollViews["dashboard.limits"]
        XCTAssertTrue(limitsScroll.exists)
        XCTAssertGreaterThan(limitsScroll.frame.minY, app.windows.firstMatch.frame.minY + 40)
        writeScreenshot(app.windows.firstMatch, name: "quotabeacon-limits-qa")
        limitsScroll.swipeUp()
        XCTAssertTrue(
            app.descendants(matching: .any)["limits.provider.gemini"]
                .waitForExistence(timeout: 3)
        )
        limitsScroll.swipeUp()
        writeScreenshot(app.windows.firstMatch, name: "quotabeacon-provider-list-qa")
        XCTAssertTrue(app.buttons["dashboard.refresh"].isHittable)

        app.staticTexts["개요"].click()
        XCTAssertTrue(app.staticTexts["dashboard.overview.title"].waitForExistence(timeout: 3))
        writeScreenshot(app.windows.firstMatch, name: "quotabeacon-readme-overview")

        app.staticTexts["추세"].click()
        let trendsScroll = app.scrollViews["dashboard.trends"]
        XCTAssertTrue(trendsScroll.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["trends.range"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["trends.provider"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["trends.coverage"].exists)
        let trendChart = app.descendants(matching: .any)["trends.chart"]
        let trendEmpty = app.descendants(matching: .any)["trends.empty"]
        XCTAssertTrue(trendChart.exists || trendEmpty.exists)
        writeScreenshot(app.windows.firstMatch, name: "quotabeacon-trends-reset-bands-qa")
        if trendChart.exists {
            trendsScroll.swipeUp()
            writeScreenshot(app.windows.firstMatch, name: "quotabeacon-trends-plot-qa")
            trendsScroll.swipeDown()
        }

        let rangeControl = app.descendants(matching: .any)["trends.range"]
        XCTAssertTrue(rangeControl.exists)
        rangeControl.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        writeScreenshot(app.windows.firstMatch, name: "quotabeacon-trends-week-qa")

        rangeControl.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: 0.5)).click()
        writeScreenshot(app.windows.firstMatch, name: "quotabeacon-trends-month-qa")

        let providerControl = app.descendants(matching: .any)["trends.provider"]
        XCTAssertTrue(providerControl.exists)
        providerControl.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).click()
        XCTAssertTrue(providerControl.exists)
        writeScreenshot(app.windows.firstMatch, name: "quotabeacon-trends-all-providers-qa")

        app.staticTexts["데이터 소스"].click()
        XCTAssertTrue(app.staticTexts["dashboard.dataSources.title"].waitForExistence(timeout: 3))

        app.staticTexts["설정"].click()
        XCTAssertTrue(app.staticTexts["dashboard.settings.title"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance.density"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance.metric"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance.reset"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance.theme"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance.inspector"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.appearance.provider.gemini"].exists)
        writeScreenshot(app.windows.firstMatch, name: "quotabeacon-settings-qa")
    }

    func testDashboardChromeStaysSeparatedAndPinned() {
        let app = XCUIApplication()
        app.launchEnvironment["AIQUOTAMONITOR_UI_TEST"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["dashboard.overview.title"].waitForExistence(timeout: 5))
        let window = app.windows.firstMatch
        let sidebarButton = app.buttons["dashboard.toggleSidebar"]
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(sidebarButton.frame.midX, window.frame.midX)

        let sidebarEntry = app.staticTexts["연결"]
        XCTAssertTrue(sidebarEntry.isHittable)
        sidebarButton.click()
        XCTAssertFalse(sidebarEntry.isHittable)
        sidebarButton.click()
        XCTAssertTrue(sidebarEntry.isHittable)

        app.staticTexts["추세"].click()
        XCTAssertTrue(app.staticTexts["dashboard.trends.title"].waitForExistence(timeout: 3))
        let providerLabel = app.staticTexts["trends.provider.label"]
        let providerControl = app.descendants(matching: .any)["trends.provider"]
        XCTAssertTrue(providerLabel.exists)
        XCTAssertTrue(providerControl.exists)
        XCTAssertLessThanOrEqual(providerLabel.frame.maxX + 8, providerControl.frame.minX)
        writeScreenshot(window, name: "quotabeacon-dashboard-chrome-qa")
    }

    private func writeScreenshot(_ element: XCUIElement, name: String) {
        addScreenshot(element.screenshot(), name: name)
    }

    private func addScreenshot(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
