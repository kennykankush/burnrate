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
    private var stackView: MenuBarStackView?
    private var observation: NSKeyValueObservation?

    init(model: MenuBarModel) {
        self.model = model
        super.init()
        self.installStatusItem()
        self.installPopover()
        // Re-render the menu bar label after every model refresh tick.
        self.model.onSnapshotChanged = { [weak self] in
            self?.refreshLabel()
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // Capture both left- and right-clicks. Left opens the popover,
            // right pops the module-picker menu — Stats does this exact
            // pattern, and it's what users instinctively reach for.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(self.handleClick(_:))
            button.target = self

            // Replace the default NSButton image+title with a Stats-style
            // two-line stack: tiny label up top, monospace value below.
            // The button still owns the click area; we just paint inside.
            let stack = MenuBarStackView()
            stack.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 6),
                stack.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -6),
                stack.topAnchor.constraint(equalTo: button.topAnchor),
                stack.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            self.stackView = stack
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
        // Fixed dimensions — the tabbed layout handles overflow internally.
        return NSSize(
            width: DesignSystem.Layout.popoverWidth,
            height: DesignSystem.Layout.popoverHeight)
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            self.presentModulePicker(sender)
            return
        }
        guard let popover = self.popover, let button = self.statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Recompute size on every open in case the user moved windows or
            // changed displays.
            popover.contentSize = self.computePopoverSize()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Make the underlying window transparent so Liquid Glass on cards
            // can actually refract the desktop content behind the popover.
            // Without this, NSPopover's default opaque chrome means glass
            // effects render against a solid background and look flat.
            if let window = popover.contentViewController?.view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
                window.makeKey()
            }
        }
    }

    /// Build the module-picker NSMenu and pop it under the status item.
    /// Reused by the gear-icon submenu in the popover for users who don't
    /// know to right-click.
    private func presentModulePicker(_ sender: NSStatusBarButton) {
        guard let item = self.statusItem else { return }
        let menu = self.buildModulePickerMenu()
        item.menu = menu
        sender.performClick(nil)
        // Detach immediately so the next left-click reopens the popover
        // instead of replaying this menu.
        DispatchQueue.main.async { [weak item] in
            item?.menu = nil
        }
    }

    func buildModulePickerMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(Self.headerItem("Menu bar shows"))
        for module in MenuBarModule.allCases {
            let entry = NSMenuItem(
                title: "\(module.displayName)  ·  \(module.label)",
                action: #selector(self.handleModuleSelection(_:)),
                keyEquivalent: "")
            entry.target = self
            entry.representedObject = module.rawValue
            entry.state = (self.model.selectedMenuBarModule == module) ? .on : .off
            menu.addItem(entry)
        }
        return menu
    }

    private static func headerItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        item.isEnabled = false
        return item
    }

    @objc private func handleModuleSelection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let module = MenuBarModule(rawValue: raw)
        else { return }
        self.model.setMenuBarModule(module)
        self.refreshLabel()
    }

    func refreshLabel() {
        guard let stack = self.stackView else { return }
        let display = self.model.menuBarDisplay
        stack.update(label: display.label, value: display.value)
        let targetWidth = ceil(stack.intrinsicContentSize.width) + 14
        self.statusItem?.length = max(34, targetWidth)
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        // No-op for now. Hook for analytics later.
    }
}

// MARK: - MenuBarStackView

/// Stats-style two-line label: a tiny uppercase tag on top, a slightly
/// larger monospace value below. Centered, fixed metrics so the menu-bar
/// item width changes only when the value's character count changes.
final class MenuBarStackView: NSView {
    private let labelField: NSTextField
    private let valueField: NSTextField

    override init(frame: NSRect) {
        self.labelField = Self.makeLabelField()
        self.valueField = Self.makeValueField()
        super.init(frame: frame)
        self.commonInit()
    }

    required init?(coder: NSCoder) {
        self.labelField = Self.makeLabelField()
        self.valueField = Self.makeValueField()
        super.init(coder: coder)
        self.commonInit()
    }

    private func commonInit() {
        self.labelField.translatesAutoresizingMaskIntoConstraints = false
        self.valueField.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.labelField)
        self.addSubview(self.valueField)

        // Two-line stack with a 1pt gap. The label sits in the top half,
        // value in the bottom half — slightly larger font to stay
        // readable at the menu bar's ~22pt total height.
        NSLayoutConstraint.activate([
            self.labelField.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.labelField.topAnchor.constraint(equalTo: self.topAnchor, constant: 1),

            self.valueField.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.valueField.topAnchor.constraint(equalTo: self.labelField.bottomAnchor, constant: -1),
            self.valueField.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor, constant: -1),
        ])
    }

    func update(label: String, value: String) {
        self.labelField.stringValue = label
        self.valueField.stringValue = value
        self.invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let labelWidth = self.labelField.intrinsicContentSize.width
        let valueWidth = self.valueField.intrinsicContentSize.width
        let width = ceil(max(labelWidth, valueWidth))
        return NSSize(width: width, height: NSView.noIntrinsicMetric)
    }

    private static func makeLabelField() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.systemFont(ofSize: 8, weight: .semibold)
        field.textColor = NSColor.secondaryLabelColor
        field.alignment = .center
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private static func makeValueField() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        field.textColor = NSColor.labelColor
        field.alignment = .center
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}
