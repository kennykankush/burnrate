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
            // Capture both left- and right-clicks. Left opens the
            // configuration popover; right gives a quick appearance menu.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(self.handleClick(_:))
            button.target = self

            // Replace the default NSButton image+title with a custom anchor
            // that can render icon-only, icon+metric, or the legacy two-line
            // metric stack. The button still owns the click area; we just
            // paint inside.
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

    /// Build the quick appearance NSMenu and pop it under the status item.
    /// The full configuration surface lives in the left-click popover.
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
        menu.addItem(Self.headerItem("Status item"))

        let modeItem = NSMenuItem(title: "Display mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in MenuBarDisplayMode.allCases {
            let entry = NSMenuItem(
                title: mode.menuTitle,
                action: #selector(self.handleDisplayModeSelection(_:)),
                keyEquivalent: "")
            entry.target = self
            entry.representedObject = mode.rawValue
            entry.state = (self.model.menuBarDisplayMode == mode) ? .on : .off
            modeMenu.addItem(entry)
        }
        menu.setSubmenu(modeMenu, for: modeItem)
        menu.addItem(modeItem)

        let iconItem = NSMenuItem(title: "Icon style", action: nil, keyEquivalent: "")
        let iconMenu = NSMenu()
        for style in MenuBarIconStyle.allCases {
            let entry = NSMenuItem(
                title: style.label,
                action: #selector(self.handleIconStyleSelection(_:)),
                keyEquivalent: "")
            entry.target = self
            entry.representedObject = style.rawValue
            entry.state = (self.model.menuBarIconStyle == style) ? .on : .off
            iconMenu.addItem(entry)
        }
        menu.setSubmenu(iconMenu, for: iconItem)
        menu.addItem(iconItem)

        menu.addItem(NSMenuItem.separator())
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

    @objc private func handleDisplayModeSelection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = MenuBarDisplayMode(rawValue: raw)
        else { return }
        self.model.setMenuBarDisplayMode(mode)
        self.refreshLabel()
    }

    @objc private func handleIconStyleSelection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = MenuBarIconStyle(rawValue: raw)
        else { return }
        self.model.setMenuBarIconStyle(style)
        self.refreshLabel()
    }

    func refreshLabel() {
        guard let stack = self.stackView else { return }
        let display = self.model.menuBarDisplay
        let iconSymbol = self.model.menuBarIconStyle.symbol(for: self.model.selectedProvider)
        let accent = NSColor(self.model.selectedProvider == .codex
            ? DesignSystem.Colors.accent(for: .codex)
            : DesignSystem.Colors.brandHot)
        stack.update(
            label: display.label,
            value: display.value,
            iconSymbol: iconSymbol,
            iconTint: accent,
            mode: self.model.menuBarDisplayMode)
        let targetWidth = ceil(stack.intrinsicContentSize.width) + 14
        self.statusItem?.length = max(self.model.menuBarDisplayMode == .iconOnly ? 28 : 34, targetWidth)
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
    private let rootStack: NSStackView
    private let textStack: NSStackView
    private let iconView: NSImageView
    private let labelField: NSTextField
    private let valueField: NSTextField

    override init(frame: NSRect) {
        self.rootStack = NSStackView()
        self.textStack = NSStackView()
        self.iconView = NSImageView()
        self.labelField = Self.makeLabelField()
        self.valueField = Self.makeValueField()
        super.init(frame: frame)
        self.commonInit()
    }

    required init?(coder: NSCoder) {
        self.rootStack = NSStackView()
        self.textStack = NSStackView()
        self.iconView = NSImageView()
        self.labelField = Self.makeLabelField()
        self.valueField = Self.makeValueField()
        super.init(coder: coder)
        self.commonInit()
    }

    private func commonInit() {
        self.rootStack.orientation = .horizontal
        self.rootStack.alignment = .centerY
        self.rootStack.spacing = 4
        self.rootStack.distribution = .gravityAreas
        self.rootStack.translatesAutoresizingMaskIntoConstraints = false

        self.textStack.orientation = .vertical
        self.textStack.alignment = .centerX
        self.textStack.spacing = -1
        self.textStack.distribution = .gravityAreas

        self.iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 12,
            weight: .semibold)
        self.iconView.contentTintColor = NSColor.labelColor
        self.iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.iconView.setContentHuggingPriority(.required, for: .horizontal)

        self.textStack.addArrangedSubview(self.labelField)
        self.textStack.addArrangedSubview(self.valueField)
        self.rootStack.addArrangedSubview(self.iconView)
        self.rootStack.addArrangedSubview(self.textStack)
        self.addSubview(self.rootStack)

        NSLayoutConstraint.activate([
            self.rootStack.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.rootStack.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.rootStack.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor),
            self.rootStack.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor),
            self.rootStack.topAnchor.constraint(greaterThanOrEqualTo: self.topAnchor),
            self.rootStack.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor),
        ])
    }

    func update(
        label: String,
        value: String,
        iconSymbol: String,
        iconTint: NSColor,
        mode: MenuBarDisplayMode
    ) {
        self.iconView.image = NSImage(systemSymbolName: iconSymbol, accessibilityDescription: nil)
        self.iconView.contentTintColor = iconTint
        self.labelField.stringValue = label
        self.valueField.stringValue = value
        switch mode {
        case .iconOnly:
            self.iconView.isHidden = false
            self.textStack.isHidden = true
            self.labelField.isHidden = true
            self.valueField.isHidden = true
            self.rootStack.spacing = 0
        case .iconAndMetric:
            self.iconView.isHidden = false
            self.textStack.isHidden = false
            self.labelField.isHidden = true
            self.valueField.isHidden = false
            self.rootStack.spacing = 4
        case .metricStack:
            self.iconView.isHidden = true
            self.textStack.isHidden = false
            self.labelField.isHidden = false
            self.valueField.isHidden = false
            self.rootStack.spacing = 0
        }
        self.needsLayout = true
        self.invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        self.layoutSubtreeIfNeeded()
        let width = ceil(self.rootStack.fittingSize.width)
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
