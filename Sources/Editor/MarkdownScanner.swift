import Foundation

/// A stretch of characters the styler should treat specially. Ranges are
/// absolute document offsets in UTF-16, ready to hand to `NSTextStorage`.
struct MarkdownSpan {
    enum Kind: Equatable {
        /// Syntax characters: `#`, `**`, backticks, `-`, `>`, brackets.
        case marker
        case headingText(level: Int)
        case bold
        case italic
        case strike
        case code
        case codeBlock
        case quoteText
        case rule
        case linkText
        case linkURL
    }

    let range: NSRange
    let kind: Kind
}

/// Hand-rolled, line at a time. No AST is built and no tree is walked: the
/// styler needs character ranges, and it needs them on every keystroke.
///
/// Only the constructs listed in the spec are recognised. Anything nested or
/// exotic falls through as plain text, which is the intended behaviour.
enum MarkdownScanner {

    /// Where the fenced code blocks are. Built once per styling pass, because a
    /// line's meaning depends on how many fences opened above it.
    struct FenceMap {
        private let delimiters: [NSRange]

        init(text: NSString) {
            var found: [NSRange] = []
            let length = text.length
            var searchStart = 0

            while searchStart < length {
                let searchRange = NSRange(location: searchStart, length: length - searchStart)
                let hit = text.range(of: "```", range: searchRange)
                guard hit.location != NSNotFound else { break }

                let lineRange = text.lineRange(for: NSRange(location: hit.location, length: 0))
                // Only a fence when it opens the line.
                if hit.location == lineRange.location {
                    found.append(lineRange)
                }
                searchStart = max(NSMaxRange(lineRange), hit.location + 3)
            }
            delimiters = found
        }

        func isDelimiter(lineStart: Int) -> Bool {
            delimiters.contains { $0.location == lineStart }
        }

        /// A line is inside a block when an odd number of fences opened above it.
        func isInsideFence(lineStart: Int) -> Bool {
            delimiters.reduce(into: 0) { count, fence in
                if fence.location < lineStart { count += 1 }
            }.isMultiple(of: 2) == false
        }
    }

    /// Spans for a single line. `lineRange` is the full line including its
    /// newline, in document coordinates.
    static func spans(in text: NSString, lineRange: NSRange, fences: FenceMap) -> [MarkdownSpan] {
        if fences.isDelimiter(lineStart: lineRange.location) {
            return [MarkdownSpan(range: lineRange, kind: .marker)]
        }
        if fences.isInsideFence(lineStart: lineRange.location) {
            return [MarkdownSpan(range: lineRange, kind: .codeBlock)]
        }

        let chars = Array(text.substring(with: lineRange).utf16)
        let base = lineRange.location
        guard !chars.isEmpty else { return [] }

        var start = 0
        while start < chars.count, chars[start] == C.space || chars[start] == C.tab {
            start += 1
        }
        guard start < chars.count else { return [] }

        if isRule(chars, from: start) {
            return [MarkdownSpan(range: lineRange, kind: .rule)]
        }

        if let heading = headingSpans(chars, from: start, base: base) {
            // No inline pass inside a heading: nesting is out of scope, and
            // letting bold reset the font would undo the heading's size.
            return heading
        }

        if chars[start] == C.greaterThan {
            var index = start + 1
            if index < chars.count, chars[index] == C.space { index += 1 }
            var spans = [MarkdownSpan(range: range(base, start, index - start), kind: .marker)]
            if index < chars.count {
                spans.append(
                    MarkdownSpan(range: range(base, index, chars.count - index), kind: .quoteText)
                )
            }
            spans += inlineSpans(chars, from: index, base: base)
            return spans
        }

        if let markerEnd = listMarkerEnd(chars, from: start) {
            var spans = [MarkdownSpan(range: range(base, start, markerEnd - start), kind: .marker)]
            spans += inlineSpans(chars, from: markerEnd, base: base)
            return spans
        }

        return inlineSpans(chars, from: start, base: base)
    }

    // MARK: - Block constructs

    private static func headingSpans(_ chars: [unichar], from start: Int, base: Int) -> [MarkdownSpan]? {
        guard chars[start] == C.hash else { return nil }

        var level = 0
        var index = start
        while index < chars.count, chars[index] == C.hash, level < 6 {
            level += 1
            index += 1
        }
        // "#tag" is not a heading; the hashes must be followed by a space.
        guard index < chars.count, chars[index] == C.space else { return nil }

        var spans = [MarkdownSpan(range: range(base, start, index + 1 - start), kind: .marker)]
        let textStart = index + 1
        if textStart < chars.count {
            spans.append(
                MarkdownSpan(
                    range: range(base, textStart, chars.count - textStart),
                    kind: .headingText(level: level)
                )
            )
        }
        return spans
    }

    /// Three or more of the same rule character, and nothing else on the line.
    private static func isRule(_ chars: [unichar], from start: Int) -> Bool {
        let first = chars[start]
        guard first == C.dash || first == C.asterisk || first == C.underscore else { return false }

        var count = 0
        for character in chars[start...] {
            if character == first {
                count += 1
            } else if character != C.space && character != C.newline && character != C.carriageReturn {
                return false
            }
        }
        return count >= 3
    }

    /// End index of a `-`, `*` or `1.` list marker, including its trailing space.
    private static func listMarkerEnd(_ chars: [unichar], from start: Int) -> Int? {
        if chars[start] == C.dash || chars[start] == C.asterisk {
            guard start + 1 < chars.count, chars[start + 1] == C.space else { return nil }
            return start + 2
        }

        var index = start
        while index < chars.count, chars[index] >= C.zero, chars[index] <= C.nine {
            index += 1
        }
        guard index > start,
              index + 1 < chars.count,
              chars[index] == C.dot,
              chars[index + 1] == C.space
        else { return nil }
        return index + 2
    }

    // MARK: - Inline constructs

    /// Single left-to-right pass. Delimiters must close on the same line, and
    /// nothing nests — the first construct to open wins.
    private static func inlineSpans(_ chars: [unichar], from start: Int, base: Int) -> [MarkdownSpan] {
        var spans: [MarkdownSpan] = []
        var index = start

        while index < chars.count {
            let character = chars[index]

            if character == C.backtick, let close = find(chars, C.backtick, from: index + 1) {
                spans += wrapped(base, open: index, openLength: 1, close: close, closeLength: 1, kind: .code)
                index = close + 1
                continue
            }

            if character == C.asterisk {
                if index + 1 < chars.count, chars[index + 1] == C.asterisk {
                    if let close = findPair(chars, C.asterisk, from: index + 2) {
                        spans += wrapped(base, open: index, openLength: 2, close: close, closeLength: 2, kind: .bold)
                        index = close + 2
                        continue
                    }
                } else if let close = find(chars, C.asterisk, from: index + 1), close > index + 1 {
                    spans += wrapped(base, open: index, openLength: 1, close: close, closeLength: 1, kind: .italic)
                    index = close + 1
                    continue
                }
            }

            if character == C.tilde,
               index + 1 < chars.count,
               chars[index + 1] == C.tilde,
               let close = findPair(chars, C.tilde, from: index + 2) {
                spans += wrapped(base, open: index, openLength: 2, close: close, closeLength: 2, kind: .strike)
                index = close + 2
                continue
            }

            if character == C.openBracket, let link = linkSpans(chars, from: index, base: base) {
                spans += link.spans
                index = link.end
                continue
            }

            index += 1
        }

        return spans
    }

    /// `[text](url)` — all four delimiter runs dimmed, text and URL styled.
    private static func linkSpans(
        _ chars: [unichar],
        from start: Int,
        base: Int
    ) -> (spans: [MarkdownSpan], end: Int)? {
        guard let closeBracket = find(chars, C.closeBracket, from: start + 1),
              closeBracket + 1 < chars.count,
              chars[closeBracket + 1] == C.openParen,
              let closeParen = find(chars, C.closeParen, from: closeBracket + 2)
        else { return nil }

        var spans = [MarkdownSpan(range: range(base, start, 1), kind: .marker)]
        if closeBracket > start + 1 {
            spans.append(
                MarkdownSpan(range: range(base, start + 1, closeBracket - start - 1), kind: .linkText)
            )
        }
        spans.append(MarkdownSpan(range: range(base, closeBracket, 2), kind: .marker))
        if closeParen > closeBracket + 2 {
            spans.append(
                MarkdownSpan(
                    range: range(base, closeBracket + 2, closeParen - closeBracket - 2),
                    kind: .linkURL
                )
            )
        }
        spans.append(MarkdownSpan(range: range(base, closeParen, 1), kind: .marker))

        return (spans, closeParen + 1)
    }

    // MARK: - Helpers

    private static func wrapped(
        _ base: Int,
        open: Int,
        openLength: Int,
        close: Int,
        closeLength: Int,
        kind: MarkdownSpan.Kind
    ) -> [MarkdownSpan] {
        var spans = [MarkdownSpan(range: range(base, open, openLength), kind: .marker)]
        let contentStart = open + openLength
        if close > contentStart {
            spans.append(MarkdownSpan(range: range(base, contentStart, close - contentStart), kind: kind))
        }
        spans.append(MarkdownSpan(range: range(base, close, closeLength), kind: .marker))
        return spans
    }

    private static func find(_ chars: [unichar], _ target: unichar, from start: Int) -> Int? {
        var index = start
        while index < chars.count {
            if chars[index] == C.newline { return nil }
            if chars[index] == target { return index }
            index += 1
        }
        return nil
    }

    /// The start of the next doubled `target`, e.g. the closing `**`.
    private static func findPair(_ chars: [unichar], _ target: unichar, from start: Int) -> Int? {
        var index = start
        while index + 1 < chars.count {
            if chars[index] == C.newline { return nil }
            if chars[index] == target, chars[index + 1] == target { return index }
            index += 1
        }
        return nil
    }

    private static func range(_ base: Int, _ start: Int, _ length: Int) -> NSRange {
        NSRange(location: base + start, length: length)
    }

    private enum C {
        static let tab: unichar = 9
        static let newline: unichar = 10
        static let carriageReturn: unichar = 13
        static let space: unichar = 32
        static let hash: unichar = 35
        static let openParen: unichar = 40
        static let closeParen: unichar = 41
        static let asterisk: unichar = 42
        static let dash: unichar = 45
        static let dot: unichar = 46
        static let zero: unichar = 48
        static let nine: unichar = 57
        static let greaterThan: unichar = 62
        static let openBracket: unichar = 91
        static let closeBracket: unichar = 93
        static let underscore: unichar = 95
        static let backtick: unichar = 96
        static let tilde: unichar = 126
    }
}
