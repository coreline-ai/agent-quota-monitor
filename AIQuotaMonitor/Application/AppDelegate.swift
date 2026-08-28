import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dashboardWindowController: DashboardWindowController?
    private var statusItemController: StatusItemController?
    private lazy var model = QuotaMonitorModel()
    private lazy var diskUsageProvider: any DiskUsageProviding = DiskUsageService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        let isUITesting = environment["AIQUOTAMONITOR_UI_TEST"] == "1"
        let isUnitTestHost = environment["XCTestConfigurationFilePath"] != nil && !isUITesting
        NSApplication.shared.setActivationPolicy(isUITesting ? .regular : .accessory)

        // Hosted unit tests exercise adapters with injected fixtures. Starting the
        // production refresh loop here would read real credentials and keep the
        // XCTest host alive after the assertions have completed.
        if isUnitTestHost { return }

        if isUITesting, environment["AIQUOTAMONITOR_UI_TEST_RESET_DEFAULTS"] == "1" {
            AppPreferences.resetUITestDomain()
        }

        if !isUITesting {
            LegacyPreferencesMigrator.migrateIfNeeded(defaults: AppPreferences.current)
        }
        statusItemController = StatusItemController(
            model: model,
            diskUsageProvider: diskUsageProvider,
            onShowDashboard: { [weak self] in
                self?.showDashboard()
            },
            onShowAllProviders: { [weak self] in
                self?.showAllProviders()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )

        if isUITesting {
            showDashboard()
        }
        if environment["AIQUOTAMONITOR_UI_TEST_POPOVER"] == "1" {
            // Status-item attachment can lag behind the app window on a busy UI
            // test host. Repeating an idempotent `show` keeps this test-only hook
            // deterministic without changing production interaction.
            for delay in [0.25, 0.75, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.statusItemController?.showPopoverForTesting()
                }
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

    private func showDashboard() {
        dashboardController().showWindow()
    }

    private func showAllProviders() {
        dashboardController().showAllProviders()
    }

    private func dashboardController() -> DashboardWindowController {
        if let dashboardWindowController { return dashboardWindowController }
        let controller = DashboardWindowController(model: model)
        dashboardWindowController = controller
        return controller
    }
}
