import AppKit

/// One replacement to make in the buffer, and where the selection lands after.
struct TextEdit: Equatable {
    let range: NSRange
    let replacement: String
    let selection: NSRange
}

/// The formatting shortcuts. Every one of them inserts or removes markdown
/// characters — there is no formatting state anywhere, only text.
///
/// These are pure functions of the text and the selection so they can be
/// reasoned about without a text view in the room.
enum MarkdownFormatter {

    /// Wraps the selection in `marker`, or unwraps it if it is already wrapped.
    /// An empty selection gets an empty pair with the cursor between.
    static func toggleWrap(in text: NSString, selection: NSRange, marker: String) -> TextEdit {
        let markerLength = (marker as NSString).length
        let selected = text.substring(with: selection)

        // The markers are inside the selection: "**bold**" is selected whole.
        if selection.length >= markerLength * 2,
           selected.hasPrefix(marker),
           selected.hasSuffix(marker) {
            let inner = (selected as NSString).substring(
                with: NSRange(location: markerLength, length: selection.length - markerLength * 2)
            )
            return TextEdit(
                range: selection,
                replacement: inner,
                selection: NSRange(location: selection.location, length: (inner as NSString).length)
            )
        }

        // The markers sit just outside the selection: "**" + "bold" + "**".
        let before = selection.location - markerLength
        let after = NSMaxRange(selection)
        if before >= 0,
           after + markerLength <= text.length,
           text.substring(with: NSRange(location: before, length: markerLength)) == marker,
           text.substring(with: NSRange(location: after, length: markerLength)) == marker,
           !isPartOfLongerRun(text, marker: marker, before: before, after: after) {
            return TextEdit(
                range: NSRange(location: before, length: selection.length + markerLength * 2),
                replacement: selected,
                selection: NSRange(location: before, length: selection.length)
            )
        }

        return TextEdit(
            range: selection,
            replacement: marker + selected + marker,
            selection: NSRange(
                location: selection.location + markerLength,
                length: selection.length
            )
        )
    }

    /// Wraps the selection as a link with the cursor waiting inside the parens.
    static func link(in text: NSString, selection: NSRange) -> TextEdit {
        let selected = text.substring(with: selection)
        let cursor = selection.location + 1 + (selected as NSString).length + 2
        return TextEdit(
            range: selection,
            replacement: "[\(selected)]()",
            selection: NSRange(location: cursor, length: 0)
        )
    }

    /// Sets the current line to a heading, or strips it if it is already that
    /// level. Any existing heading marker is replaced, not stacked.
    static func toggleHeading(in text: NSString, selection: NSRange, level: Int) -> TextEdit {
        let lineRange = text.lineRange(for: selection)
        let line = Array(text.substring(with: lineRange).utf16)

        var hashes = 0
        while hashes < line.count, line[hashes] == 35, hashes < 6 { hashes += 1 }
        let hasSpace = hashes < line.count && line[hashes] == 32
        let existingLevel = hasSpace ? hashes : 0
        let prefixLength = existingLevel > 0 ? existingLevel + 1 : 0

        let replacement = existingLevel == level ? "" : String(repeating: "#", count: level) + " "
        let delta = (replacement as NSString).length - prefixLength

        return TextEdit(
            range: NSRange(location: lineRange.location, length: prefixLength),
            replacement: replacement,
            selection: NSRange(
                location: max(lineRange.location, selection.location + delta),
                length: selection.length
            )
        )
    }

    /// Guards italic against eating one asterisk off a bold pair: "*" next to
    /// another "*" belongs to a longer run and is not ours to remove.
    private static func isPartOfLongerRun(
        _ text: NSString,
        marker: String,
        before: Int,
        after: Int
    ) -> Bool {
        guard marker == "*" else { return false }
        let markerLength = 1
        if before - markerLength >= 0,
           text.substring(with: NSRange(location: before - markerLength, length: markerLength)) == marker {
            return true
        }
        if after + markerLength * 2 <= text.length,
           text.substring(with: NSRange(location: after + markerLength, length: markerLength)) == marker {
            return true
        }
        return false
    }

    /// Applies an edit through the normal input path so undo and the styling
    /// delegate both see it as an ordinary change.
    static func apply(_ edit: TextEdit, to textView: NSTextView) {
        textView.insertText(edit.replacement, replacementRange: edit.range)
        textView.setSelectedRange(edit.selection)
    }
}
