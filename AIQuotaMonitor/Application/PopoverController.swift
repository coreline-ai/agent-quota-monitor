import AppKit
import SwiftUI

@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover: NSPopover
    private let model: QuotaMonitorModel

    init(model: QuotaMonitorModel, onShowDashboard: @escaping () -> Void) {
        self.model = model
        popover = NSPopover()
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 430, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPlaceholderView(model: model, onShowDashboard: onShowDashboard)
        )
        popover.delegate = self
    }

    func toggle(relativeTo positioningRect: NSRect, of positioningView: NSView) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show(relativeTo: positioningRect, of: positioningView)
        }
    }

    func show(relativeTo positioningRect: NSRect, of positioningView: NSView) {
        guard !popover.isShown else { return }
        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: .minY)
    }

    func popoverDidShow(_ notification: Notification) {
        model.setPopoverVisible(true)
    }

    func popoverDidClose(_ notification: Notification) {
        model.setPopoverVisible(false)
    }
}
