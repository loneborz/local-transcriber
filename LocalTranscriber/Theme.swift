import SwiftUI
import AppKit

// The v0.5 identity colors (doc-2, section 3). Values come from the Wavesweb and
// Local Transcriber website design systems; nothing else is introduced. Each
// color has light, dark and Increase Contrast variants.
enum Theme {
    // Window ground, continued under the title bar.
    static let paper = color(light: 0xF3F0EA, dark: 0x171214)
    // The import zone.
    static let recessed = color(light: 0xE8E2D9, dark: 0x171214)
    // The record zone, the action bar's record segment and the queue list.
    static let raised = color(light: 0xFAF8F4, dark: 0x251E20)
    // Surface borders and dividers.
    static let rule = color(light: 0xD4C9BD, dark: 0x3A3133, highContrastLight: 0xA89D96, highContrastDark: 0x605855)
    // The one italic brand word and the underline of output links.
    static let emphasis = color(light: 0x762F3D, dark: 0xD7A3AD)
    // Only the prominent button and checkboxes. Never tint a container with it:
    // that also tints ordinary button, picker and menu labels.
    static let wineFill = color(light: 0x762F3D, dark: 0x8F3D4E)

    private static func color(light: UInt32, dark: UInt32, highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
            case .darkAqua?: rgb(dark)
            case .accessibilityHighContrastAqua?: rgb(highContrastLight ?? light)
            case .accessibilityHighContrastDarkAqua?: rgb(highContrastDark ?? dark)
            default: rgb(light)
            }
        })
    }

    private static func rgb(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    // A bordered surface: radius 16, a 1 px rule, no shadow.
    func surface() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.rule, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
