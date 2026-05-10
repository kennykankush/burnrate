import AppKit
import BurnrateCore
import SwiftUI

// MARK: - Root

struct MenuBarRootView: View {
    @Bindable var model: MenuBarModel
    @State private var panel: MenuBarPanel = .settings

    var body: some View {
        // MenuBarExtra(.window) provides the system Liquid Glass chrome for us
        // on macOS 26 — we just supply the content. No glassEffect needed at
        // the root, no manual backdrop. Older macOS gets a custom backdrop.
        Group {
            switch self.panel {
            case .settings:
                MenuBarSettingsContent(
                    model: self.model,
                    openArchive: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            self.panel = .archive
                        }
                    })
            case .archive:
                LegacyMenuBarContent(
                    model: self.model,
                    closeArchive: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            self.panel = .settings
                        }
                    })
            }
        }
            .frame(width: DesignSystem.Layout.popoverWidth, height: DesignSystem.Layout.popoverHeight)
            .modifier(LegacyBackdropIfNeeded())
    }
}

private enum MenuBarPanel {
    case settings
    case archive
}

private struct LegacyBackdropIfNeeded: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
        } else {
            content.background { AppBackdrop() }
        }
    }
}

/// Refresh button spin — uses native `.rotate` symbol effect on macOS 15+,
/// falls back to manual rotation on macOS 14.
private struct RefreshSpinModifier: ViewModifier {
    let isRefreshing: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.symbolEffect(.rotate, options: .repeating, isActive: self.isRefreshing)
        } else {
            content
                .rotationEffect(.degrees(self.isRefreshing ? 360 : 0))
                .animation(
                    self.isRefreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                    value: self.isRefreshing)
        }
    }
}

@MainActor
private struct MenuBarSettingsContent: View {
    @Bindable var model: MenuBarModel
    let openArchive: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(model: self.model)
            Divider().overlay(DesignSystem.Colors.stroke.opacity(0.6))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    StatusItemSettings(model: self.model)
                    NotchSettings(model: self.model)
                    AlertStartupSettings(model: self.model)
                    ArchiveSettings(openArchive: self.openArchive)
                }
                .padding(.horizontal, DesignSystem.Layout.contentPadding)
                .padding(.vertical, 14)
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider().overlay(DesignSystem.Colors.stroke.opacity(0.6))
            StatuslineFooter(model: self.model)
        }
    }
}

@MainActor
private struct LegacyMenuBarContent: View {
    @Bindable var model: MenuBarModel
    let closeArchive: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ArchiveHeader(model: self.model, closeArchive: self.closeArchive)
            TabBar(model: self.model)
            Divider().overlay(DesignSystem.Colors.stroke.opacity(0.6))

            TabContent(model: self.model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider().overlay(DesignSystem.Colors.stroke.opacity(0.6))
            StatuslineFooter(model: self.model)
        }
    }
}

struct MenuBarLabel: View {
    let model: MenuBarModel

    var body: some View {
        // Legacy SwiftUI label — superseded by StatusBarController's
        // custom NSStatusItem. Kept here for the MenuBarExtra fallback.
        HStack(spacing: 4) {
            Image(systemName: "flame")
            Text(self.model.menuBarDisplay.value)
                .font(.geist(size: 11, weight: .medium))
        }
    }
}

// MARK: - Settings surface

@MainActor
private struct SettingsHeader: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                BrandMark(mark: .icon3D, size: 22)
                    .shadow(color: Brand.Palette.brandPurple.opacity(0.35), radius: 5, y: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings")
                        .font(.geist(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                    Text("burnrate")
                        .font(.geistMono(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                }
            }

            Spacer()

            SourceToggle(selectedProvider: self.$model.selectedProvider, snapshots: self.model.overview.snapshots)

            Button {
                Task { await self.model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .modifier(RefreshSpinModifier(isRefreshing: self.model.isRefreshing))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            .frame(width: 26, height: 26)
            .brandGlass(cornerRadius: 7, interactive: true)
            .disabled(self.model.isRefreshing)
            .help("Refresh")
        }
        .padding(.horizontal, DesignSystem.Layout.contentPadding)
        .padding(.vertical, 10)
    }
}

@MainActor
private struct ArchiveHeader: View {
    @Bindable var model: MenuBarModel
    let closeArchive: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: self.closeArchive) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            .brandGlass(cornerRadius: 7, interactive: true)
            .help("Back to settings")

            Text("Usage archive")
                .font(.geist(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)

            Spacer()

            SourceToggle(selectedProvider: self.$model.selectedProvider, snapshots: self.model.overview.snapshots)
        }
        .padding(.horizontal, DesignSystem.Layout.contentPadding)
        .padding(.vertical, 10)
    }
}

@MainActor
private struct StatusItemSettings: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        SettingsSection(title: "Status item") {
            StatusItemPreview(model: self.model)

            SettingBlock(label: "Display") {
                HStack(spacing: 6) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        SettingsChoiceButton(
                            title: mode.label,
                            isSelected: self.model.menuBarDisplayMode == mode,
                            action: { self.model.setMenuBarDisplayMode(mode) })
                    }
                }
            }

            SettingBlock(label: "Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        SettingsIconButton(
                            style: style,
                            provider: self.model.selectedProvider,
                            isSelected: self.model.menuBarIconStyle == style,
                            action: { self.model.setMenuBarIconStyle(style) })
                    }
                }
            }

            SettingBlock(label: "Metric") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(MenuBarModule.allCases) { module in
                        SettingsMetricButton(
                            module: module,
                            display: self.model.value(for: module),
                            isSelected: self.model.selectedMenuBarModule == module,
                            action: { self.model.setMenuBarModule(module) })
                    }
                }
            }
        }
    }
}

@MainActor
private struct NotchSettings: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        SettingsSection(title: "Notch") {
            SettingsToggleRow(
                title: "Show notch",
                detail: self.model.notchEnabled ? "enabled" : "hidden",
                isOn: Binding(
                    get: { self.model.notchEnabled },
                    set: { self.model.setNotchEnabled($0) }))

            SettingsToggleRow(
                title: "Haptics",
                detail: self.model.hapticsEnabled ? "tap feedback" : "silent",
                isOn: Binding(
                    get: { self.model.hapticsEnabled },
                    set: { self.model.setHapticsEnabled($0) }))

            SettingsMenuRow(
                title: "Open style",
                value: self.model.alcoveChoreography.label) {
                    ForEach(AlcoveChoreography.allCases) { choreography in
                        Button {
                            self.model.setAlcoveChoreography(choreography)
                        } label: {
                            if self.model.alcoveChoreography == choreography {
                                Label(choreography.label, systemImage: "checkmark")
                            } else {
                                Text(choreography.label)
                            }
                        }
                    }
                }

            SettingsMenuRow(
                title: "Spring",
                value: self.model.alcoveSpring.label) {
                    ForEach(AlcoveSpring.allCases) { spring in
                        Button {
                            self.model.setAlcoveSpring(spring)
                        } label: {
                            if self.model.alcoveSpring == spring {
                                Label(spring.label, systemImage: "checkmark")
                            } else {
                                Text(spring.label)
                            }
                        }
                    }
                }

            HStack(spacing: 8) {
                SettingsActionButton(
                    title: self.model.notchCalibrating ? "Done calibrating" : "Calibrate",
                    systemImage: "slider.horizontal.3",
                    action: { self.model.setNotchCalibrating(!self.model.notchCalibrating) })

                SettingsActionButton(
                    title: "Reset size",
                    systemImage: "arrow.counterclockwise",
                    action: { self.model.resetNotchSizeOverrides() })
                    .opacity(self.model.notchWidthOverride == nil && self.model.notchHeightOverride == nil ? 0.45 : 1)
                    .disabled(self.model.notchWidthOverride == nil && self.model.notchHeightOverride == nil)
            }
        }
    }
}

@MainActor
private struct AlertStartupSettings: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        SettingsSection(title: "Alerts and startup") {
            SettingsToggleRow(
                title: "Launch at login",
                detail: self.model.isLaunchAtLoginEnabled ? "enabled" : "off",
                isOn: Binding(
                    get: { self.model.isLaunchAtLoginEnabled },
                    set: { _ in self.model.toggleLaunchAtLogin() }))
        }
    }
}

private struct ArchiveSettings: View {
    let openArchive: () -> Void

    var body: some View {
        SettingsSection(title: "Archive") {
            Button(action: self.openArchive) {
                HStack(spacing: 10) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 13, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open usage archive")
                            .font(.geist(size: 12, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.primaryText)
                        Text("Now, map, patterns, wrap, health")
                            .font(.geistMono(size: 9, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                }
                .padding(10)
                .background(DesignSystem.Colors.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DesignSystem.Colors.stroke.opacity(0.9))
                }
            }
            .buttonStyle(.plain)
        }
    }
}

@MainActor
private struct StatusItemPreview: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        let display = self.model.menuBarDisplay
        HStack(spacing: 10) {
            Image(systemName: self.model.menuBarIconStyle.symbol(for: self.model.selectedProvider))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.accent(for: self.model.selectedProvider))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            if self.model.menuBarDisplayMode != .iconOnly {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.value)
                        .font(.geistMono(size: 15, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                    Text("\(display.label) · \(self.model.menuBarDisplayMode.menuTitle)")
                        .font(.geistMono(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.model.menuBarIconStyle.label)
                        .font(.geist(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                    Text(self.model.menuBarDisplayMode.menuTitle)
                        .font(.geistMono(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                }
            }

            Spacer()
        }
        .padding(10)
        .background(DesignSystem.Colors.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DesignSystem.Colors.stroke.opacity(0.9))
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.title)
                .font(.geist(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
            VStack(spacing: 10) {
                self.content
            }
        }
        .padding(12)
        .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignSystem.Colors.stroke.opacity(0.75))
        }
    }
}

private struct SettingBlock<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(self.label)
                .font(.geistMono(size: 9, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
            self.content
        }
    }
}

private struct SettingsChoiceButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Text(self.title)
                .font(.geist(size: 10, weight: self.isSelected ? .semibold : .medium))
                .foregroundStyle(self.isSelected ? DesignSystem.Colors.primaryText : DesignSystem.Colors.tertiaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(self.isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(self.isSelected ? Color.white.opacity(0.24) : DesignSystem.Colors.stroke.opacity(0.55))
                }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsIconButton: View {
    let style: MenuBarIconStyle
    let provider: ProviderKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 6) {
                Image(systemName: self.style.symbol(for: self.provider))
                    .font(.system(size: 11, weight: .semibold))
                Text(self.style.label)
                    .font(.geist(size: 10, weight: self.isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(self.isSelected ? DesignSystem.Colors.primaryText : DesignSystem.Colors.tertiaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(self.isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(self.isSelected ? Color.white.opacity(0.24) : DesignSystem.Colors.stroke.opacity(0.55))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsMetricButton: View {
    let module: MenuBarModule
    let display: MenuBarDisplay?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            VStack(spacing: 2) {
                Text(self.module.label)
                    .font(.geistMono(size: 8, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                Text(self.display?.value ?? "--")
                    .font(.geistMono(size: 11, weight: .semibold))
                    .foregroundStyle(self.isSelected ? DesignSystem.Colors.primaryText : DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(self.isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(self.isSelected ? Color.white.opacity(0.24) : DesignSystem.Colors.stroke.opacity(0.55))
            }
        }
        .buttonStyle(.plain)
        .help(self.module.displayName)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(self.title)
                    .font(.geist(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                Text(self.detail)
                    .font(.geistMono(size: 9, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
            }
            Spacer()
            Toggle("", isOn: self.$isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(10)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsMenuRow<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            Text(self.title)
                .font(.geist(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
            Spacer()
            Menu {
                self.content
            } label: {
                HStack(spacing: 6) {
                    Text(self.value)
                        .font(.geistMono(size: 10, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(10)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 6) {
                Image(systemName: self.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(self.title)
                    .font(.geist(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DesignSystem.Colors.stroke.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header

@MainActor
private struct HeaderBar: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                BrandMark(mark: .icon3D, size: 22)
                    .shadow(color: Brand.Palette.brandPurple.opacity(0.45), radius: 6, y: 2)
                Text("burnrate")
                    .font(.geist(size: 15, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
            }

            Spacer()

            SourceToggle(selectedProvider: self.$model.selectedProvider, snapshots: self.model.overview.snapshots)

            Button {
                Task { await self.model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .modifier(RefreshSpinModifier(isRefreshing: self.model.isRefreshing))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            .frame(width: 26, height: 26)
            .brandGlass(cornerRadius: 7, interactive: true)
            .disabled(self.model.isRefreshing)
            .help("Refresh — ⌘R")
            .keyboardShortcut("r", modifiers: .command)

            // Hidden binding for ⌘\ — flips between Codex and Claude
            // when both have data. Zero-size, no visual presence; the
            // tooltip on the SourceToggle documents the shortcut.
            Button("Toggle source") {
                self.model.cycleProvider()
            }
            .keyboardShortcut("\\", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, DesignSystem.Layout.contentPadding)
        .padding(.vertical, 10)
    }
}

// MARK: - Source toggle (CC | Codex, 2-state)

@MainActor
private struct SourceToggle: View {
    @Binding var selectedProvider: ProviderKind
    let snapshots: [ProviderUsageSnapshot]
    @Namespace private var pillNS

    private func shortName(for provider: ProviderKind) -> String {
        switch provider {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ProviderKind.allCases) { provider in
                let isSelected = self.selectedProvider == provider
                let isAvailable = self.snapshots.contains { $0.kind == provider }
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                        self.selectedProvider = provider
                    }
                } label: {
                    HStack(spacing: 4) {
                        ProviderMark(kind: provider, size: 10, renderingMode: .template)
                        Text(self.shortName(for: provider))
                            .font(.geist(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .foregroundStyle(isSelected ? DesignSystem.Colors.primaryText : DesignSystem.Colors.tertiaryText)
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.18))
                            .matchedGeometryEffect(id: "sourcePill", in: self.pillNS)
                    }
                }
                .opacity(isAvailable ? 1.0 : 0.4)
                .disabled(!isAvailable)
                .help(isAvailable ? "\(provider.displayName) — ⌘\\ to toggle" : "no \(provider.displayName.lowercased()) usage detected")
            }
        }
        .padding(2)
        .brandGlass(cornerRadius: 8)
    }
}

// MARK: - Tab bar

@MainActor
private struct TabBar: View {
    @Bindable var model: MenuBarModel
    @Namespace private var tabPillNS

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                TabButton(
                    tab: tab,
                    isActive: self.model.activeTab == tab,
                    pillNamespace: self.tabPillNS,
                    action: {
                        // Snappier spring with a touch of overshoot — that's
                        // the "addictive" cadence Linear/Things use.
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                            self.model.setActiveTab(tab)
                        }
                    })
            }
        }
        .padding(.horizontal, DesignSystem.Layout.contentPadding)
        .padding(.bottom, 10)
    }
}

@MainActor
private struct TabButton: View {
    let tab: AppTab
    let isActive: Bool
    let pillNamespace: Namespace.ID
    let action: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 4) {
                Image(systemName: self.tab.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .symbolEffect(.bounce.up.byLayer, value: self.isActive)
                Text(self.tab.label)
                    .font(.geist(size: 11, weight: self.isActive ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .help("\(self.tab.label) — ⌘\(String(self.tab.keyEquivalent))")
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .foregroundStyle(self.isActive ? DesignSystem.Colors.primaryText : DesignSystem.Colors.tertiaryText)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            // Tactile press feedback — physical "give" on click
            .scaleEffect(self.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: self.isPressed)
        }
        .buttonStyle(.plain)
        .background {
            if self.isActive {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.20))
                    }
                    .matchedGeometryEffect(id: "tabPill", in: self.pillNamespace)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in self.isPressed = true }
                .onEnded { _ in self.isPressed = false })
        .keyboardShortcut(KeyEquivalent(self.tab.keyEquivalent), modifiers: .command)
    }
}

// MARK: - Tab content router

@MainActor
private struct TabContent: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        ZStack {
            if let snapshot = self.model.selectedSnapshot {
                Group {
                    switch self.model.activeTab {
                    case .now:
                        NowView(
                            snapshot: snapshot,
                            overview: self.model.overview,
                            turnPattern: self.turnPattern(for: snapshot),
                            model: self.model)
                    case .surface: SurfaceView(snapshot: snapshot)
                    case .patterns: PatternsView(snapshot: snapshot)
                    case .wrap: WrapView(snapshot: snapshot)
                    case .health: HealthView(snapshot: snapshot)
                    }
                }
                .id(self.model.activeTab)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.97, anchor: .top)),
                        removal: .opacity.combined(with: .offset(y: -4))))
            } else {
                EmptyOverviewView(isRefreshing: self.model.isRefreshing, error: self.model.lastError)
            }
        }
        // Same spring as the pill morph — pill + content move as one motion
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: self.model.activeTab)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: self.model.selectedProvider)
    }

    private func turnPattern(for snapshot: ProviderUsageSnapshot) -> MenuBarModel.TurnPattern? {
        guard let context = snapshot.workContext else { return nil }
        let pattern = self.model.turnPattern(
            forSessionId: context.sessionId,
            provider: snapshot.kind)
        return pattern.hasEnoughData ? pattern : nil
    }
}

// MARK: - Footer (statusline)

@MainActor
private struct StatuslineFooter: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        HStack(spacing: 8) {
            StatuslinePulse(model: self.model)
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                // Menu bar module picker — same options also appear via
                // right-click on the status item itself. Both surfaces
                // exist because some users never right-click status items.
                Menu("Menu bar shows") {
                    ForEach(MenuBarModule.allCases) { module in
                        Button {
                            self.model.setMenuBarModule(module)
                        } label: {
                            if self.model.selectedMenuBarModule == module {
                                Label("\(module.displayName)  ·  \(module.label)", systemImage: "checkmark")
                            } else {
                                Text("\(module.displayName)  ·  \(module.label)")
                            }
                        }
                    }
                }

                Button {
                    self.model.setNotchEnabled(!self.model.notchEnabled)
                } label: {
                    if self.model.notchEnabled {
                        Label("Show in notch (M-series MacBook)", systemImage: "checkmark")
                    } else {
                        Text("Show in notch (M-series MacBook)")
                    }
                }

                Button {
                    self.model.toggleLaunchAtLogin()
                } label: {
                    if self.model.isLaunchAtLoginEnabled {
                        Label("Launch at login", systemImage: "checkmark")
                    } else {
                        Text("Launch at login")
                    }
                }

                Divider()

                Button("Quit burnrate") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
        }
        .padding(.horizontal, DesignSystem.Layout.contentPadding)
        .padding(.vertical, 9)
    }
}

@MainActor
private struct StatuslinePulse: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        HStack(spacing: 6) {
            if let fire = self.model.fireEvent {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.brandHot)
                    .symbolEffect(.bounce, value: fire.triggeredAt)
                Text(self.fireCopy(fire))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.brandHot)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
            } else if let error = self.model.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.danger)
                Text("paused · \(error.title)")
                    .font(.geistMono(size: 10))
                    .foregroundStyle(DesignSystem.Colors.danger)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(error.recovery ?? error.raw)
            } else if let live = self.liveSummary {
                Image(systemName: live.glyph)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.brandLavender)
                Text(live.text)
                    .font(.geistMono(size: 10))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: live.text)
            } else {
                Text("no live session · refreshed \(self.refreshedText)")
                    .font(.geistMono(size: 10))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
            }
        }
    }

    private struct LiveSummary {
        let glyph: String
        let text: String
    }

    private var liveSummary: LiveSummary? {
        if let session = self.model.selectedSnapshot?.claudeSession,
           !session.activeTaskChain.isEmpty || session.activeTaskTitle != nil
        {
            return LiveSummary(glyph: self.glyph(for: session.activeTaskChain.last), text: self.claudeText(session: session))
        }
        if let codex = self.model.selectedSnapshot?.codexSession,
           let last = codex.lastActivityAt,
           Date().timeIntervalSince(last) < 1_800
        {
            return LiveSummary(glyph: "terminal", text: self.codexText(session: codex))
        }
        return nil
    }

    private func claudeText(session: ClaudeSessionStats) -> String {
        let chain = session.activeTaskChain.suffix(3).joined(separator: " → ")
        let project = session.projectName ?? "session"
        let lastSeen: String = {
            guard let last = session.lastActivityAt else { return "" }
            let s = max(0, Int(Date().timeIntervalSince(last)))
            if s < 5 { return "live" }
            if s < 60 { return "\(s)s ago" }
            return "\(s / 60)m ago"
        }()
        let parts = [
            chain.isEmpty ? "turn \(session.assistantMessageCount)" : chain,
            project,
            lastSeen,
        ].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private func codexText(session: CodexSessionStats) -> String {
        let title = session.threadTitle?.isEmpty == false ? session.threadTitle! : "codex"
        let lastSeen: String = {
            guard let last = session.lastActivityAt else { return "" }
            let s = max(0, Int(Date().timeIntervalSince(last)))
            if s < 5 { return "live" }
            if s < 60 { return "\(s)s ago" }
            return "\(s / 60)m ago"
        }()
        return "\(title) · \(session.toolCalls) tools · \(lastSeen)"
    }

    private func glyph(for tool: String?) -> String {
        switch tool {
        case "Edit", "Write", "NotebookEdit": "pencil.line"
        case "Read": "doc.text"
        case "Bash": "terminal"
        case "Grep", "Glob": "magnifyingglass"
        case "WebSearch", "WebFetch": "globe"
        case "Skill": "sparkles"
        case "Task", "Agent": "person.2"
        default: "wand.and.stars"
        }
    }

    private var refreshedText: String {
        guard let last = self.model.lastRefreshAt else { return "never" }
        return DisplayText.relative(last)
    }

    /// Celebratory copy when the user just shoved a giant turn through near-full
    /// context and lived to tell the tale. Picks a variant deterministically
    /// from the trigger time so it doesn't flicker between refreshes.
    private func fireCopy(_ fire: MenuBarModel.FireEvent) -> String {
        let tokensK = Int((Double(fire.turnTokens) / 1_000).rounded())
        let pct = Int(fire.contextUsedPercent.rounded())
        let variants: [String] = [
            "playing with fire — \(tokensK)K turn at \(pct)%",
            "woah ok cooking — \(tokensK)K turn, still alive",
            "no fear — \(tokensK)K through at \(pct)% used",
            "burning hot — squeezed \(tokensK)K through",
            "pushing it — \(tokensK)K turn, \(pct)% used",
        ]
        let idx = Int(fire.triggeredAt.timeIntervalSince1970) % variants.count
        return variants[idx]
    }
}

// MARK: - Empty / loading / error overview

private struct EmptyOverviewView: View {
    let isRefreshing: Bool
    let error: MenuBarModel.UsageError?

    var body: some View {
        Group {
            if let error {
                ErrorOverview(error: error)
            } else if self.isRefreshing {
                LoadingOverview()
            } else {
                FirstRunOverview()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
    }
}

private struct LoadingOverview: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.brandLavender)
                .symbolEffect(.pulse, options: .repeating)
            Text("Warming up the watcher\u{2026}")
                .font(.geist(size: 12))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
    }
}

private struct ErrorOverview: View {
    let error: MenuBarModel.UsageError

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.danger)
            Text(self.error.title)
                .font(.geist(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .multilineTextAlignment(.center)
            if let recovery = self.error.recovery {
                Text(recovery)
                    .font(.geist(size: 11))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// First-launch / no-data state. Explains what burnrate is, lists which
/// providers are detected, and points new users at the next action.
private struct FirstRunOverview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.brandLavender)
                    Text("Welcome to burnrate")
                        .font(.geist(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                }
                Text("A live watcher for your Claude Code and Codex usage \u{2014} context windows, 5h burst limits, weekly caps, and per-turn pace.")
                    .font(.geist(size: 11))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("To get started")
                    .font(.geist(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .tracking(0.6)
                    .textCase(.uppercase)
                FirstRunStepRow(
                    symbol: "1.circle.fill",
                    title: "Install Claude Code or Codex",
                    detail: "burnrate reads transcripts from \u{223C}/.claude or \u{223C}/.codex.")
                FirstRunStepRow(
                    symbol: "2.circle.fill",
                    title: "Authorize Keychain access",
                    detail: "Grants read-only access to OAuth tokens for live 5h\u{202F}/\u{202F}7d window data.")
                FirstRunStepRow(
                    symbol: "3.circle.fill",
                    title: "Start coding",
                    detail: "Numbers populate within a turn or two.")
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                Text("Already configured? Use \u{2318}R to refresh.")
                    .font(.geist(size: 10))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FirstRunStepRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: self.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.brandLavender)
                .frame(width: 14, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(self.title)
                    .font(.geist(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                Text(self.detail)
                    .font(.geist(size: 10))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Background

private struct AppBackdrop: View {
    var body: some View {
        // Fully transparent — let Liquid Glass on cards be the only visible chrome.
        Color.clear
    }
}
