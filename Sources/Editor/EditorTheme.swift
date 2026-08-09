import AppKit

/// Fonts, metrics and colours for the editor. Colours are always semantic so
/// light and dark appearance come for free.
enum EditorTheme {
    static let bodyFont = NSFont.systemFont(ofSize: 15)
    static let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    /// Text stops growing past this width, however wide the window gets.
    static let maxLineWidth: CGFloat = 700
    static let minHorizontalInset: CGFloat = 24
    static let verticalInset: CGFloat = 32
    static let lineHeightMultiple: CGFloat = 1.5

    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        return style
    }

    /// The attributes every character starts with. The styling layer in M4 will
    /// layer on top of these, never replace them wholesale.
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle,
        ]
    }
}
