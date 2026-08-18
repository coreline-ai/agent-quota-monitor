import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popoverController: PopoverController
    private let onShowDashboard: () -> Void
    private let onQuit: () -> Void
    private let model: QuotaMonitorModel

    init(
        model: QuotaMonitorModel,
        onShowDashboard: @escaping () -> Void,
        onShowAllProviders: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.model = model
        self.onShowDashboard = onShowDashboard
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popoverController = PopoverController(model: model, onShowAllProviders: onShowAllProviders)
        super.init()
        configureStatusButton()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(named: AppTheme.statusItemAssetName) ?? NSImage(
            systemSymbolName: AppTheme.statusItemSymbolName,
            accessibilityDescription: String(localized: "status.accessibilityLabel")
        )
        button.image?.accessibilityDescription = String(localized: "status.accessibilityLabel")
        button.image?.isTemplate = true
        button.toolTip = String(localized: "status.tooltip")
        button.setAccessibilityLabel(String(localized: "status.accessibilityLabel"))
        button.setAccessibilityIdentifier("status.quotaBeacon")
        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc
    private func handleStatusItemClick() {
        guard let event = NSApplication.shared.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        popoverController.toggle(relativeTo: button.bounds, of: button)
    }

    func showPopoverForTesting() {
        guard ProcessInfo.processInfo.environment["AIQUOTAMONITOR_UI_TEST_POPOVER"] == "1" else { return }
        guard let button = statusItem.button else { return }
        popoverController.show(relativeTo: button.bounds, of: button)
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let dashboardItem = NSMenuItem(
            title: String(localized: "menu.openDashboard"),
            action: #selector(openDashboard),
            keyEquivalent: "d"
        )
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let refreshItem = NSMenuItem(
            title: String(localized: "menu.refresh"),
            action: #selector(refresh),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "menu.quit"),
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc
    private func openDashboard() {
        onShowDashboard()
    }

    @objc
    private func quitApplication() {
        onQuit()
    }

    @objc
    private func refresh() {
        Task { await model.refresh() }
    }
}
