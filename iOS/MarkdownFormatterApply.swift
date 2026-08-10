import MarkdownCore
import UIKit

/// The one formatting operation that needs a text view, and so cannot live in
/// the platform-independent package.
extension MarkdownFormatter {
    /// Applies an edit through the normal input path, so undo and the styling
    /// delegate both see it as ordinary typing.
    static func apply(_ edit: TextEdit, to textView: UITextView) {
        textView.selectedRange = edit.range
        textView.insertText(edit.replacement)
        textView.selectedRange = edit.selection
    }
}
