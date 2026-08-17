import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController: NSWindowController, NSToolbarDelegate {
    private nonisolated static let sidebarToolbarIdentifier = NSToolbarItem.Identifier("dashboard.toggleSidebar")
    private let chrome: DashboardChromeModel

    init(model: QuotaMonitorModel) {
        let chrome = DashboardChromeModel()
        self.chrome = chrome
        let contentView = DashboardRootView(model: model, chrome: chrome)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "dashboard.windowTitle")
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: contentView)
        window.center()
        super.init(window: window)
        installToolbar(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func installToolbar(in window: NSWindow) {
        let toolbar = NSToolbar(identifier: "QuotaBeaconDashboardToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        window.toolbarStyle = .unified
        window.toolbar = toolbar
    }

    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.sidebarToolbarIdentifier]
    }

    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.sidebarToolbarIdentifier]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.sidebarToolbarIdentifier else { return nil }

        let button = NSButton(
            image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil) ?? NSImage(),
            target: self,
            action: #selector(toggleSidebar(_:))
        )
        button.image?.isTemplate = true
        button.contentTintColor = .labelColor
        button.bezelStyle = .toolbar
        button.imagePosition = .imageOnly
        button.toolTip = "왼쪽 메뉴 보기/감추기"
        button.setAccessibilityLabel("왼쪽 메뉴 보기/감추기")
        button.setAccessibilityIdentifier("dashboard.toggleSidebar")
        button.frame = NSRect(x: 0, y: 0, width: 38, height: 30)

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "왼쪽 메뉴"
        item.paletteLabel = "왼쪽 메뉴 보기/감추기"
        item.toolTip = "왼쪽 메뉴 보기/감추기"
        item.view = button
        item.visibilityPriority = .high
        return item
    }

    @objc private func toggleSidebar(_ sender: NSButton) {
        chrome.toggleSidebar()
    }
}
