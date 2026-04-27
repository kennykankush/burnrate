import AppKit
import CoreText
import Foundation

enum FontRegistration {
    static func registerBundledFonts() {
        let names = [
            "Geist-Regular",
            "Geist-Medium",
            "Geist-SemiBold",
            "Geist-Bold",
            "Geist-Black",
            "GeistMono-Regular",
            "GeistMono-Medium",
            "GeistMono-SemiBold",
        ]

        for name in names {
            guard let url = Bundle.module.url(forResource: name, withExtension: "otf") else {
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}
