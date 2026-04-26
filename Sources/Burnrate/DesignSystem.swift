import BurnrateCore
import SwiftUI

enum DesignSystem {
    enum Layout {
        static let popoverWidth: CGFloat = 396
        static let contentPadding: CGFloat = 12
        static let rowRadius: CGFloat = 8
        static let controlHeight: CGFloat = 28

        /// Maximises the scroll-area height to whatever the current screen allows,
        /// minus the menu bar, our own header/footer, and a small breathing margin.
        /// Falls back to 720pt if NSScreen is unavailable (background process, etc.).
        static var scrollMaxHeight: CGFloat {
            let chromeReservation: CGFloat = 130
            guard let screen = NSScreen.main else { return 720 }
            let usable = screen.visibleFrame.height - chromeReservation
            return max(420, min(usable, 1100))
        }
    }

    enum Colors {
        static let background = Color(red: 0.050, green: 0.052, blue: 0.058)
        static let surface = Color.white.opacity(0.082)
        static let elevatedSurface = Color.white.opacity(0.125)
        static let raisedSurface = elevatedSurface
        static let stroke = Color.white.opacity(0.145)
        static let glassHighlight = Color.white.opacity(0.30)
        static let glassWash = Color.white.opacity(0.075)
        static let glassShade = Color.black.opacity(0.18)
        static let primaryText = Color.white.opacity(0.94)
        static let secondaryText = Color.white.opacity(0.68)
        static let tertiaryText = Color.white.opacity(0.46)
        static let success = Color(red: 0.54, green: 0.82, blue: 0.68)
        static let warning = Color(red: 0.91, green: 0.72, blue: 0.38)
        static let danger = Color(red: 0.92, green: 0.43, blue: 0.45)

        static func accent(for provider: ProviderKind) -> Color {
            switch provider {
            case .codex: Color(red: 0.31, green: 0.78, blue: 0.88)
            case .claude: Color(red: 0.95, green: 0.56, blue: 0.38)
            }
        }

        static func meter(_ percent: Double, provider: ProviderKind) -> Color {
            switch percent {
            case 0..<55:
                accent(for: provider)
            case 55..<82:
                warning
            default:
                danger
            }
        }
    }

    enum Typography {
        static let title = Font.system(size: 14, weight: .semibold, design: .default)
        static let section = Font.system(size: 12, weight: .semibold, design: .default)
        static let body = Font.system(size: 12, weight: .regular)
        static let label = Font.system(size: 11, weight: .medium, design: .default)
        static let caption = Font.system(size: 10, weight: .regular, design: .default)
        static let metric = Font.system(size: 24, weight: .semibold, design: .default)
        static let number = Font.system(size: 11, weight: .medium, design: .default)
    }
}

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

struct MeterBar: View {
    let tone: UsageTone
    let usedPercent: Double

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = max(4, proxy.size.width * min(1, max(0, self.usedPercent / 100)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(self.tone.color).frame(width: fillWidth)
            }
        }
        .frame(height: 5)
    }
}

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

extension View {
    func premiumCard(accent: Color, includeGlow: Bool = true) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(accent.opacity(0.10))
                                .frame(width: 118, height: 42)
                                .offset(x: -22, y: -18)
                                .clipped()
                        }
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.10))
            }
            .shadow(color: Color.black.opacity(0.16), radius: 10, y: 6)
    }

    func glassSurface(cornerRadius: CGFloat, tint: Color = .clear) -> some View {
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
