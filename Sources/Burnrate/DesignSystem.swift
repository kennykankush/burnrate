import BurnrateCore
import SwiftUI

// MARK: - Tokens

enum DesignSystem {
    enum Layout {
        // Direction B sizing — wider for big numbers + generous breathing room.
        static let popoverWidth: CGFloat = 420
        static let popoverHeight: CGFloat = 700

        static let contentPadding: CGFloat = 16
        static let cardPadding: CGFloat = 12
        static let cardRadius: CGFloat = 12
        static let chipRadius: CGFloat = 7
        static let rowRadius: CGFloat = 9
        static let controlHeight: CGFloat = 26

        static let tabScrollMaxHeight: CGFloat = popoverHeight - 160
        static var scrollMaxHeight: CGFloat { tabScrollMaxHeight }
    }

    enum Colors {
        // Brand-tinted dark palette.
        // All neutrals carry a faint deepPurple cast for subconscious brand cohesion.
        static let background = Color(red: 0.062, green: 0.054, blue: 0.082)
        static let surface = Color.white.opacity(0.075)
        static let elevatedSurface = Color.white.opacity(0.115)
        static let raisedSurface = elevatedSurface
        static let stroke = Color.white.opacity(0.135)
        static let glassHighlight = Color.white.opacity(0.30)
        static let glassWash = Color.white.opacity(0.075)
        static let glassShade = Color.black.opacity(0.18)

        static let primaryText = Color.white.opacity(0.94)
        static let secondaryText = Color.white.opacity(0.70)
        static let tertiaryText = Color.white.opacity(0.48)

        // Semantic state.
        static let success = Color(red: 0.50, green: 0.84, blue: 0.66)
        static let warning = Color(red: 0.96, green: 0.74, blue: 0.36)
        static let danger = Color(red: 0.96, green: 0.42, blue: 0.46)

        // Brand accents pulled from Brand.Palette so the design system + brand layer
        // stay in sync when the brand is tweaked.
        static let brandHot = Brand.Palette.moltenOrange
        static let brandCore = Brand.Palette.warmCore
        static let brandLavender = Brand.Palette.softLavender
        static let brandDeep = Brand.Palette.deepPurple

        static func accent(for provider: ProviderKind) -> Color {
            switch provider {
            case .codex: Color(red: 0.42, green: 0.78, blue: 0.92)
            case .claude: Brand.Palette.moltenOrange
            }
        }

        static func meter(_ percent: Double, provider: ProviderKind) -> Color {
            switch percent {
            case 0..<55: accent(for: provider)
            case 55..<82: warning
            default: danger
            }
        }
    }

    enum Typography {
        // SF Pro / SF Mono — Apple's system fonts. Native macOS feel.

        static let display = Font.system(size: 22, weight: .heavy)

        static let title = Font.system(size: 14, weight: .semibold)
        static let section = Font.system(size: 12, weight: .semibold)
        static let body = Font.system(size: 12, weight: .regular)
        static let label = Font.system(size: 11, weight: .medium)
        static let caption = Font.system(size: 10, weight: .regular)
        static let micro = Font.system(size: 9, weight: .medium)

        static let number = Font.system(size: 11, weight: .medium, design: .monospaced)
        static let statValue = Font.system(size: 13, weight: .semibold, design: .monospaced)
        static let metric = Font.system(size: 24, weight: .semibold, design: .monospaced)

        static let tab = Font.system(size: 12, weight: .medium)
    }
}

// MARK: - Geist convenience

extension Font {
    /// SF Pro — Apple's system font. Native macOS feel. Modern, serious,
    /// scales correctly with system text settings.
    static func geist(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .default)
    }

    /// SF Mono — system monospaced. Tabular figures for stats / numbers.
    static func geistMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Tone

enum UsageTone {
    case calm
    case watch
    case tight

    init(percent: Double) {
        switch percent {
        case 0..<55: self = .calm
        case 55..<82: self = .watch
        default: self = .tight
        }
    }

    init(health: CodexThreadHealth) {
        switch health {
        case .efficient, .healthy: self = .calm
        case .watch: self = .watch
        case .tight, .stuck: self = .tight
        }
    }

    init(status: ClaudeHealthStatus) {
        switch status {
        case .ok: self = .calm
        case .warn: self = .watch
        case .error: self = .tight
        case .unknown: self = .watch
        }
    }

    init(patternTone: ClaudePatternTone) {
        switch patternTone {
        case .positive: self = .calm
        case .neutral: self = .watch
        case .caution: self = .tight
        }
    }

    var label: String {
        switch self {
        case .calm: "Healthy"
        case .watch: "Moderate"
        case .tight: "Tight"
        }
    }

    var color: Color {
        switch self {
        case .calm: DesignSystem.Colors.success
        case .watch: DesignSystem.Colors.warning
        case .tight: DesignSystem.Colors.danger
        }
    }
}

// MARK: - Meter

struct MeterBar: View {
    let tone: UsageTone
    let usedPercent: Double

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = max(4, proxy.size.width * min(1, max(0, self.usedPercent / 100)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                // All meter fills use the canonical brand purple — state info
                // is communicated via the percent number / text color, not the bar.
                Capsule()
                    .fill(Brand.Palette.brandPurple)
                    .frame(width: fillWidth)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Display text helpers

enum DisplayText {
    static func reset(_ date: Date?) -> String? {
        guard let date else { return nil }
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return "resets now" }
        let minutes = Int(remaining / 60)
        if minutes < 60 { return "resets in \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "resets in \(hours)h" }
        return "resets in \(hours / 24)d"
    }

    static func resetShort(_ date: Date?) -> String {
        guard let text = reset(date) else { return "--" }
        return text.replacingOccurrences(of: "resets in ", with: "")
            .replacingOccurrences(of: "resets ", with: "")
    }

    static func runsOut(_ date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return "now" }
        let minutes = Int(remaining / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rem = minutes % 60
        if hours < 24 {
            if rem == 0 { return "\(hours)h" }
            return "\(hours)h \(rem)m"
        }
        let days = hours / 24
        let remHours = hours % 24
        if remHours == 0 { return "\(days)d" }
        return "\(days)d \(remHours)h"
    }

    static func relative(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...:
            return "\(value / 1_000)K"
        case 1_000...:
            return String(format: "%.1fK", Double(value) / 1_000)
        default:
            return "\(value)"
        }
    }

    static func minutes(_ value: Int) -> String {
        if value < 60 { return "\(value)m" }
        let hours = value / 60
        let minutes = value % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    static func money(_ value: Double?, currency: String?) -> String {
        guard let value else { return "--" }
        return money(value, currency: currency ?? "USD")
    }

    static func money(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Glass surfaces

extension View {
    /// On macOS 26 the whole popover is a single Liquid Glass slab, so per-card
    /// glass would be glass-on-glass (visually muddy + against Apple's guidance
    /// that glass should emphasize *key* surfaces, not decorate everything).
    /// Cards become subtle stroke-bordered cells on the slab.
    @ViewBuilder
    func brandGlass(
        cornerRadius: CGFloat = DesignSystem.Layout.cardRadius,
        tint: Color? = nil,
        interactive: Bool = true
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.cardOnGlass(cornerRadius: cornerRadius)
        } else {
            self.glassSurface(cornerRadius: cornerRadius, tint: .clear)
        }
    }

    @ViewBuilder
    func brandGlassThin(cornerRadius: CGFloat = DesignSystem.Layout.chipRadius) -> some View {
        if #available(macOS 26.0, *) {
            self.cardOnGlass(cornerRadius: cornerRadius, opacity: 0.6)
        } else {
            self.glassSurface(cornerRadius: cornerRadius, tint: .clear)
        }
    }

    /// Subtle stroke + faint fill — used for cards on the Liquid Glass slab.
    fileprivate func cardOnGlass(cornerRadius: CGFloat, opacity: Double = 1.0) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.04 * opacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12 * opacity), lineWidth: 0.7)
            }
    }
}

@available(macOS 26.0, *)
struct LiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool
    var variant: GlassVariant = .regular

    enum GlassVariant {
        case regular
        case clear
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
        switch (self.variant, self.tint, self.interactive) {
        case (.regular, let tint?, true):
            content.glassEffect(.regular.tint(tint).interactive(), in: shape)
        case (.regular, let tint?, false):
            content.glassEffect(.regular.tint(tint), in: shape)
        case (.regular, nil, true):
            content.glassEffect(.regular.interactive(), in: shape)
        case (.regular, nil, false):
            content.glassEffect(.regular, in: shape)
        case (.clear, let tint?, true):
            content.glassEffect(.clear.tint(tint).interactive(), in: shape)
        case (.clear, let tint?, false):
            content.glassEffect(.clear.tint(tint), in: shape)
        case (.clear, nil, true):
            content.glassEffect(.clear.interactive(), in: shape)
        case (.clear, nil, false):
            content.glassEffect(.clear, in: shape)
        }
    }
}

// MARK: - Legacy / Liquid Glass bridge
//
// `premiumCard` and `glassSurface` are the names used by every existing card
// view in the codebase. We redefine them here so they automatically resolve to
// real Liquid Glass on macOS 26 (Tahoe) — no per-callsite changes needed.
// On macOS 14/15 they fall back to the custom gradient-glass that shipped in
// v0.1.x.

extension View {
    @ViewBuilder
    func premiumCard(accent: Color, includeGlow: Bool = true) -> some View {
        if #available(macOS 26.0, *) {
            self.cardOnGlass(cornerRadius: DesignSystem.Layout.cardRadius)
        } else {
            self.legacyPremiumCard(accent: accent, includeGlow: includeGlow)
        }
    }

    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat, tint: Color = .clear) -> some View {
        if #available(macOS 26.0, *) {
            self.cardOnGlass(cornerRadius: cornerRadius, opacity: 0.6)
        } else {
            self.legacyGlassSurface(cornerRadius: cornerRadius, tint: tint)
        }
    }

    fileprivate func legacyPremiumCard(accent: Color, includeGlow: Bool) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cardRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.075),
                                Color.white.opacity(0.040),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                    .overlay(alignment: .topLeading) {
                        if includeGlow {
                            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardRadius, style: .continuous)
                                .fill(accent.opacity(0.10))
                                .frame(width: 118, height: 42)
                                .offset(x: -22, y: -18)
                                .clipped()
                        }
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: DesignSystem.Layout.cardRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.34),
                                        Color.white.opacity(0.10),
                                        Color.white.opacity(0.04),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing),
                                lineWidth: 1)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cardRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10))
            }
            .shadow(color: Color.black.opacity(0.16), radius: 10, y: 6)
    }

    fileprivate func legacyGlassSurface(cornerRadius: CGFloat, tint: Color = .clear) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.045),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.32),
                                        Color.white.opacity(0.08),
                                        Color.white.opacity(0.03),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing),
                                lineWidth: 1)
                    }
            }
    }
}
