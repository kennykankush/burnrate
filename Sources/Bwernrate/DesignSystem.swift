import BwernrateCore
import SwiftUI

enum DesignSystem {
    enum Layout {
        static let popoverWidth: CGFloat = 356
        static let contentPadding: CGFloat = 12
        static let rowRadius: CGFloat = 8
        static let controlHeight: CGFloat = 28
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
