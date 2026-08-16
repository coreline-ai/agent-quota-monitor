import XCTest

@MainActor
final class AIQuotaMonitorUITests: XCTestCase {
    func testDashboardCanOpenForUITesting() {
        let app = XCUIApplication()
        app.launchEnvironment["AIQUOTAMONITOR_UI_TEST"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["dashboard.overview.title"].waitForExistence(timeout: 5))

        app.staticTexts["연결"].click()
        XCTAssertTrue(app.staticTexts["dashboard.connections.title"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["connections.apply"].exists)

        app.staticTexts["한도"].click()
        XCTAssertTrue(app.staticTexts["dashboard.limits.title"].waitForExistence(timeout: 3))
        let limitsScroll = app.scrollViews["dashboard.limits"]
        XCTAssertTrue(limitsScroll.exists)
        XCTAssertGreaterThan(limitsScroll.frame.minY, app.windows.firstMatch.frame.minY + 40)
        limitsScroll.swipeUp()
        XCTAssertTrue(app.buttons["dashboard.refresh"].isHittable)

        app.staticTexts["추세"].click()
        XCTAssertTrue(app.scrollViews["dashboard.trends"].waitForExistence(timeout: 3))

        app.staticTexts["데이터 소스"].click()
        XCTAssertTrue(app.staticTexts["dashboard.dataSources.title"].waitForExistence(timeout: 3))

        app.staticTexts["설정"].click()
        XCTAssertTrue(app.staticTexts["dashboard.settings.title"].waitForExistence(timeout: 3))
    }
}
