import Foundation

/// What markdown applies where the cursor is, so the formatting bar can show it.
struct ActiveFormats: Equatable {
    var bold = false
    var italic = false
    var strike = false
    var code = false
    var link = false
    var bulletList = false
    var quote = false
    var headingLevel: Int?
}

/// Reads the markdown around the selection.
///
/// Called on every cursor move, so it scans one line and never the document —
/// fences are deliberately ignored here, since a code block changes nothing
/// about which button should look pressed.
enum MarkdownContext {

    static func active(in text: NSString, selection: NSRange) -> ActiveFormats {
        guard text.length > 0 else { return ActiveFormats() }

        let caret = min(selection.location, text.length)
        let probe = NSRange(location: caret, length: min(selection.length, text.length - caret))
        let lineRange = text.lineRange(for: NSRange(location: caret, length: 0))

        var formats = ActiveFormats()

        for span in MarkdownScanner.spans(
            in: text,
            lineRange: lineRange,
            fences: .ignoringFences
        ) where touches(span.range, probe) {
            switch span.kind {
            case .bold: formats.bold = true
            case .italic: formats.italic = true
            case .strike: formats.strike = true
            case .code, .codeBlock: formats.code = true
            case .linkText, .linkURL: formats.link = true
            case .headingText(let level): formats.headingLevel = level
            case .marker, .quoteText, .rule: break
            }
        }

        let line = Array(text.substring(with: lineRange).utf16)
        var index = 0
        while index < line.count, line[index] == 32 || line[index] == 9 { index += 1 }

        // Heading level from the line itself: the caret is often sitting in the
        // "## " marker, which is not part of the heading's text span.
        var hashes = 0
        while index + hashes < line.count, line[index + hashes] == 35, hashes < 6 { hashes += 1 }
        if hashes > 0, index + hashes < line.count, line[index + hashes] == 32 {
            formats.headingLevel = hashes
        }

        if index + 1 < line.count, line[index + 1] == 32 {
            if line[index] == 45 || line[index] == 42 { formats.bulletList = true }
        }
        if index < line.count, line[index] == 62 { formats.quote = true }

        return formats
    }

    /// A zero-length selection counts as inside a span when it sits anywhere in
    /// it, including either edge — that is where you type to extend it.
    private static func touches(_ span: NSRange, _ selection: NSRange) -> Bool {
        if selection.length == 0 {
            return selection.location >= span.location && selection.location <= NSMaxRange(span)
        }
        return NSIntersectionRange(span, selection).length > 0
    }
}
