import AppKit
import MarkdownCore

/// The one formatting operation that needs a text view, and so cannot live in
/// the platform-independent package.
extension MarkdownFormatter {
    /// Applies an edit through the normal input path so undo and the styling
    /// delegate both see it as an ordinary change.
    static func apply(_ edit: TextEdit, to textView: NSTextView) {
        textView.insertText(edit.replacement, replacementRange: edit.range)
        textView.setSelectedRange(edit.selection)
    }
}
