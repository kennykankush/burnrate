import AppKit
import SwiftUI

/// Custom status-bar controller that bypasses `MenuBarExtra(.window)`'s
/// height cap. Owns an `NSStatusItem` plus an `NSPopover` whose content size
/// we control directly via the SwiftUI host.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    let model: MenuBarModel
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    init(model: MenuBarModel) {
        self.model = model
        super.init()
        self.installStatusItem()
        self.installPopover()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.action = #selector(self.handleClick(_:))
            button.target = self
            button.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "burnrate")
            button.imagePosition = .imageLeading
            button.title = " --"
            button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        }
        self.statusItem = item
        self.refreshLabel()
    }

    private func installPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // Compute a height that maximises the available screen real estate.
        // NSPopover will draw at this exact size — no MenuBarExtra cap.
        let size = self.computePopoverSize()
        popover.contentSize = size

        let host = NSHostingController(rootView:
            MenuBarRootView(model: self.model)
                .frame(width: size.width, height: size.height)
                .onAppear { self.model.start() })
        popover.contentViewController = host

        self.popover = popover
    }

    private func computePopoverSize() -> NSSize {
        let width = DesignSystem.Layout.popoverWidth
        let chromeReservation: CGFloat = 60   // menu bar + small breathing margin
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        let height = max(520, min(visible - chromeReservation, 1200))
        return NSSize(width: width, height: height)
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let popover = self.popover, let button = self.statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Recompute size on every open in case the user moved windows or
            // changed displays.
            popover.contentSize = self.computePopoverSize()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func refreshLabel() {
        guard let button = self.statusItem?.button else { return }
        let text = self.model.menuBarText
        button.title = " \(text)"
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        // No-op for now. Hook for analytics later.
    }
}
