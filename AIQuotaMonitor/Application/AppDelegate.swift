import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dashboardWindowController: DashboardWindowController?
    private var statusItemController: StatusItemController?
    private lazy var model = QuotaMonitorModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        let isUITesting = environment["AIQUOTAMONITOR_UI_TEST"] == "1"
        let isUnitTestHost = environment["XCTestConfigurationFilePath"] != nil && !isUITesting
        NSApplication.shared.setActivationPolicy(isUITesting ? .regular : .accessory)

        // Hosted unit tests exercise adapters with injected fixtures. Starting the
        // production refresh loop here would read real credentials and keep the
        // XCTest host alive after the assertions have completed.
        if isUnitTestHost { return }

        LegacyPreferencesMigrator.migrateIfNeeded()
        let dashboardWindowController = DashboardWindowController(model: model)
        self.dashboardWindowController = dashboardWindowController
        statusItemController = StatusItemController(
            model: model,
            onShowDashboard: { [weak dashboardWindowController] in
                dashboardWindowController?.showWindow()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )

        if isUITesting {
            dashboardWindowController.showWindow()
        }
        if environment["AIQUOTAMONITOR_UI_TEST_POPOVER"] == "1" {
            // Give NSStatusBar one run-loop cycle to attach and lay out its button.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.statusItemController?.showPopoverForTesting()
            }
        }
        model.startAutomaticRefresh()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        model.cancel()
        statusItemController = nil
        dashboardWindowController = nil
    }

    @objc
    private func handleWake() {
        model.handleWake()
    }

    @objc
    private func handleSleep() {
        model.cancel()
    }
}
