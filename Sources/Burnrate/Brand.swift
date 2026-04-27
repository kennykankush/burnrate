import AppKit
import BurnrateCore
import SwiftUI

enum Brand {
    enum Mark: String {
        case circle2D = "base_2d_circle"
        case shape2D = "base_2d"
        case icon3D = "base_3d_icon"
        case shape3D = "base_3d"
        case outline = "base_outline"
        case fullWhite = "logo_full_white"
        case main3D = "main_3d"
        case maxMountain = "max_mountain"
    }

    static func image(_ mark: Mark) -> Image {
        if let nsImage = Bundle.module.image(forResource: mark.rawValue) {
            return Image(nsImage: nsImage)
        }
        return Image(mark.rawValue, bundle: .module)
    }

    /// AppKit accessor used by code that needs an `NSImage` directly,
    /// such as `NSStatusItem.button.image`.
    static func nsImage(_ mark: Mark) -> NSImage? {
        return Bundle.module.image(forResource: mark.rawValue)
    }

    static func providerImage(_ kind: ProviderKind) -> Image? {
        let name: String
        switch kind {
        case .claude: name = "claude"
        case .codex: name = "codex"
        }
        if let nsImage = Bundle.module.image(forResource: name) {
            return Image(nsImage: nsImage)
        }
        return nil
    }

    enum Palette {
        // Single canonical brand purple — vibrant violet that works at full
        // strength (pill text, accents) and at low opacity (washes, glows).
        static let brandPurple = Color(red: 0.55, green: 0.42, blue: 0.95)
        static let softLavender = brandPurple   // legacy alias
        static let deepPurple = brandPurple     // legacy alias
        static let moltenOrange = Color(red: 0.99, green: 0.55, blue: 0.16)
        static let warmCore = Color(red: 1.00, green: 0.78, blue: 0.32)
    }
}

struct BrandMark: View {
    var mark: Brand.Mark = .icon3D
    var size: CGFloat = 24

    var body: some View {
        Brand.image(self.mark)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: self.size, height: self.size)
    }
}

struct ProviderMark: View {
    let kind: ProviderKind
    var size: CGFloat = 18
    var renderingMode: Image.TemplateRenderingMode = .template

    var body: some View {
        Group {
            if let image = Brand.providerImage(self.kind) {
                image
                    .renderingMode(self.renderingMode)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: self.kind.symbolName)
            }
        }
        .frame(width: self.size, height: self.size)
    }
}
