import AppKit

/// Fonts, metrics and colours for the editor. Colours are always semantic so
/// light and dark appearance come for free.
enum EditorTheme {
    static let bodySize: CGFloat = 15
    static let monoSize: CGFloat = 14

    static let bodyFont = NSFont.systemFont(ofSize: bodySize)
    static let monoFont = NSFont.monospacedSystemFont(ofSize: monoSize, weight: .regular)
    static let boldFont = NSFont.boldSystemFont(ofSize: bodySize)
    static var italicFont: NSFont {
        NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
    }

    /// Text stops growing past this width, however wide the window gets.
    static let maxLineWidth: CGFloat = 700
    static let minHorizontalInset: CGFloat = 24
    static let verticalInset: CGFloat = 32
    static let lineHeightMultiple: CGFloat = 1.5

    /// Syntax markers are dimmed rather than hidden: most of the visual benefit,
    /// none of the layout-manager surgery that hiding them would need.
    static let markerOpacity: CGFloat = 0.35
    static let markerSizeReduction: CGFloat = 1

    static func headingFont(level: Int) -> NSFont {
        let size: CGFloat
        switch level {
        case 1: size = 26
        case 2: size = 22
        case 3: size = 19
        case 4: size = 17
        case 5: size = 16
        default: size = bodySize
        }
        return NSFont.systemFont(ofSize: size, weight: .bold)
    }

    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        return style
    }

    /// The attributes every character starts from before styling is layered on.
    static func baseAttributes(for mode: EditorMode) -> [NSAttributedString.Key: Any] {
        [
            .font: mode == .raw ? monoFont : bodyFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle,
        ]
    }
}
