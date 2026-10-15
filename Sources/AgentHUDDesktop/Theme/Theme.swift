import AppKit
import SwiftUI
import AgentHUDCore

extension Color {
    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(RGBA(hex: hex, alpha: opacity))
    }
}

extension NSColor {
    convenience init(_ rgba: RGBA) {
        self.init(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }

    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(RGBA(hex: hex, alpha: alpha))
    }
}

extension CGColor {
    static func rgba(_ c: RGBA) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [c.red, c.green, c.blue, c.alpha])!
    }
}

extension Font {
    /// System font (SF Pro) at the design's sizes.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func tabular(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

/// Design tokens for the dark and light window chrome, in the Nexa brand's paper and ink neutrals. The island/glow
/// always use `.island` (dark).
struct Theme {
    /// The Nexa brand accent.
    static let accent = Color(hex: 0xf15436)

    /// Chooses the status palette variant.
    private let isLight: Bool
    let windowBackground: Color
    let sidebarBackground: Color
    let sidebarBorder: Color
    let inputBackground: Color
    let text: Color
    let secondary: Color
    let tertiary: Color
    let card: Color
    let cardBorder: Color
    let divider: Color
    let track: Color
    let rowBackground: Color
    let rowBorder: Color
    let sessionRowBackground: Color
    let segmentBackground: Color
    let segmentSelected: Color
    let sidebarText: Color
    let dotEnded: Color

    func status(_ level: StatusLevel) -> Color {
        Color(StatusPalette.color(for: level, light: isLight))
    }

    func statusText(_ level: StatusLevel) -> Color {
        Color(StatusPalette.textColor(for: level, light: isLight))
    }

    /// One hue per token kind, lighter on the dark chrome.
    func kind(_ kind: TokenKind) -> Color {
        switch kind {
        case .cacheWrite: Color(hex: isLight ? 0x9470cd : 0xb699eb)
        case .input: Color(hex: isLight ? 0x398ad6 : 0x6db0f4)
        case .reasoning: Color(hex: isLight ? 0xc35f92 : 0xe38ab5)
        case .output: Color(hex: isLight ? 0xc26e12 : 0xe29858)
        case .cacheRead: Color(hex: isLight ? 0x00a091 : 0x31c3b5)
        }
    }

    static let dark = Theme(
        isLight: false,
        windowBackground: Color(hex: 0x202020),
        sidebarBackground: Color(hex: 0x171717),
        sidebarBorder: Color(hex: 0x4d4946).opacity(0.6),
        inputBackground: Color(hex: 0x282927),
        text: Color(hex: 0xf3f1ed),
        secondary: Color(hex: 0xb2aea9),
        tertiary: Color(hex: 0x7d7974),
        card: Color(hex: 0x282927),
        cardBorder: Color(hex: 0x4d4946).opacity(0.7),
        divider: Color(hex: 0xf3f1ed).opacity(0.10),
        track: Color(hex: 0xf3f1ed).opacity(0.12),
        rowBackground: Color(hex: 0xf3f1ed).opacity(0.05),
        rowBorder: Color.clear,
        sessionRowBackground: Color(hex: 0xf3f1ed).opacity(0.04),
        segmentBackground: Color(hex: 0xf3f1ed).opacity(0.08),
        segmentSelected: Color(hex: 0x4d4946),
        sidebarText: Color(hex: 0xdeddd8),
        dotEnded: Color(hex: 0x7d7974)
    )

    static let light = Theme(
        isLight: true,
        windowBackground: Color(hex: 0xfafafa),
        sidebarBackground: Color(hex: 0xeeeee9),
        sidebarBorder: Color(hex: 0x171717).opacity(0.08),
        inputBackground: Color.white,
        text: Color(hex: 0x171717),
        secondary: Color(hex: 0x737373),
        tertiary: Color(hex: 0x9a968f),
        card: Color.white,
        cardBorder: Color(hex: 0xd3d3d3).opacity(0.8),
        divider: Color(hex: 0x171717).opacity(0.08),
        track: Color(hex: 0x171717).opacity(0.10),
        rowBackground: Color.white,
        rowBorder: Color(hex: 0xd3d3d3).opacity(0.7),
        sessionRowBackground: Color(hex: 0x171717).opacity(0.03),
        segmentBackground: Color(hex: 0x171717).opacity(0.07),
        segmentSelected: Color.white,
        sidebarText: Color(hex: 0x171717),
        dotEnded: Color(hex: 0xb2aea9)
    )

    /// The island panel is always black with dark-mode tokens.
    static let island = Theme.dark

    static func forScheme(_ scheme: ColorScheme) -> Theme {
        scheme == .light ? .light : .dark
    }
}

/// Convenience: `Color(rgba)` for agent palette entries.
extension AgentPalette {
    static func swiftUIColor(index: Int) -> Color {
        Color(color(index: index))
    }
}
