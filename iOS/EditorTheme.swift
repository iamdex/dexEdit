import UIKit

/// The Mac's theme, in UIKit terms. Same metrics, same semantic-colour rule so
/// light and dark come for free.
enum EditorTheme {
    static let bodySize: CGFloat = 17
    static let monoSize: CGFloat = 15

    static let bodyFont = UIFont.systemFont(ofSize: bodySize)
    static let monoFont = UIFont.monospacedSystemFont(ofSize: monoSize, weight: .regular)
    static let boldFont = UIFont.boldSystemFont(ofSize: bodySize)
    static var italicFont: UIFont {
        let descriptor = bodyFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? bodyFont.fontDescriptor
        return UIFont(descriptor: descriptor, size: bodySize)
    }

    static let maxLineWidth: CGFloat = 700
    static let minHorizontalInset: CGFloat = 20
    static let verticalInset: CGFloat = 24
    static let lineHeightMultiple: CGFloat = 1.4

    static let markerOpacity: CGFloat = 0.35
    static let markerSizeReduction: CGFloat = 1

    static func headingFont(level: Int) -> UIFont {
        let size: CGFloat
        switch level {
        case 1: size = 28
        case 2: size = 24
        case 3: size = 21
        case 4: size = 19
        case 5: size = 18
        default: size = bodySize
        }
        return UIFont.systemFont(ofSize: size, weight: .bold)
    }

    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        return style
    }

    static func baseAttributes(for mode: EditorMode) -> [NSAttributedString.Key: Any] {
        [
            .font: mode == .raw ? monoFont : bodyFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle,
        ]
    }
}

/// Shared with the Mac in spirit; declared here because the iOS target does not
/// compile the Mac's sources.
enum EditorMode: String, CaseIterable {
    case styled
    case raw

    mutating func toggle() {
        self = self == .styled ? .raw : .styled
    }
}
