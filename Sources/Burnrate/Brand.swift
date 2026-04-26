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
    }

    static func image(_ mark: Mark) -> Image {
        if let nsImage = Bundle.module.image(forResource: mark.rawValue) {
            return Image(nsImage: nsImage)
        }
        return Image(mark.rawValue, bundle: .module)
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
        static let deepPurple = Color(red: 0.31, green: 0.24, blue: 0.85)
        static let softLavender = Color(red: 0.68, green: 0.62, blue: 0.96)
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
