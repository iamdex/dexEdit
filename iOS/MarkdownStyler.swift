import MarkdownCore
import UIKit

/// Turns scanner spans into text attributes — the Mac styler, in UIKit colours.
///
/// Attributes only, never characters: this runs inside
/// `textStorage(_:didProcessEditing:…)`, where touching characters is re-entrant.
enum MarkdownStyler {

    /// Restyles exactly `range`, which the caller has already expanded to
    /// paragraph boundaries.
    static func apply(to storage: NSTextStorage, range: NSRange, mode: EditorMode) {
        let text = storage.string as NSString
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard clamped.length > 0 else { return }

        storage.setAttributes(EditorTheme.baseAttributes(for: mode), range: clamped)
        guard mode == .styled else { return }

        let fences = MarkdownScanner.FenceMap(text: text)
        var location = clamped.location

        while location < NSMaxRange(clamped) {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            for span in MarkdownScanner.spans(in: text, lineRange: lineRange, fences: fences) {
                let target = NSIntersectionRange(span.range, clamped)
                guard target.length > 0 else { continue }
                storage.addAttributes(attributes(for: span.kind), range: target)
            }
            guard lineRange.length > 0 else { break }
            location = NSMaxRange(lineRange)
        }
    }

    /// A fence delimiter changes the meaning of every line below it.
    static func affectsFences(_ text: NSString, range: NSRange) -> Bool {
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard clamped.length > 0 else { return false }
        return text.range(of: "```", range: clamped).location != NSNotFound
    }

    private static func attributes(for kind: MarkdownSpan.Kind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .marker:
            return [
                .foregroundColor: UIColor.label.withAlphaComponent(EditorTheme.markerOpacity),
                .font: UIFont.systemFont(ofSize: EditorTheme.bodySize - EditorTheme.markerSizeReduction),
            ]

        case .headingText(let level):
            return [.font: EditorTheme.headingFont(level: level)]

        case .bold:
            return [.font: EditorTheme.boldFont]

        case .italic:
            return [.font: EditorTheme.italicFont]

        case .strike:
            return [.strikethroughStyle: NSUnderlineStyle.single.rawValue]

        case .code, .codeBlock:
            return [
                .font: EditorTheme.monoFont,
                .backgroundColor: UIColor.label.withAlphaComponent(0.06),
            ]

        case .quoteText:
            return [.foregroundColor: UIColor.secondaryLabel]

        case .rule:
            return [.foregroundColor: UIColor.label.withAlphaComponent(EditorTheme.markerOpacity)]

        case .linkText:
            return [.foregroundColor: UIColor.link]

        case .linkURL:
            return [
                .foregroundColor: UIColor.secondaryLabel,
                .font: UIFont.systemFont(ofSize: EditorTheme.bodySize - EditorTheme.markerSizeReduction),
            ]
        }
    }
}
