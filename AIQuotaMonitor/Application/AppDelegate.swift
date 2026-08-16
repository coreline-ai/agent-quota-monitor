import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dashboardWindowController: DashboardWindowController?
    private var statusItemController: StatusItemController?
    private let model = QuotaMonitorModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

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

        if ProcessInfo.processInfo.environment["AIQUOTAMONITOR_UI_TEST"] == "1" {
            dashboardWindowController.showWindow()
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
