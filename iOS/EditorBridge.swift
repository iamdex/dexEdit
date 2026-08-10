import MarkdownCore
import UIKit

/// Connects the formatting bar to the live text view, and reports what
/// markdown the cursor is sitting in so the bar can show it.
@MainActor
final class EditorBridge: ObservableObject {
    weak var textView: UITextView?

    /// What surrounds the cursor. Recomputed on every cursor move, which is why
    /// MarkdownContext scans one line and never the document.
    @Published var active = ActiveFormats()

    /// Raised when a note is created, so the editor knows to take the keyboard
    /// rather than making you tap the page first.
    var wantsFocus = false

    // MARK: - Formatting

    func toggleBold() { wrap("**") }
    func toggleItalic() { wrap("*") }
    func toggleStrike() { wrap("~~") }
    func toggleCode() { wrap("`") }

    func toggleBulletList() { linePrefix("- ") }
    func toggleQuote() { linePrefix("> ") }

    func insertLink() {
        apply { MarkdownFormatter.link(in: $0, selection: $1) }
    }

    func insertImage() {
        apply { MarkdownFormatter.image(in: $0, selection: $1) }
    }

    func toggleHeading(level: Int) {
        apply { MarkdownFormatter.toggleHeading(in: $0, selection: $1, level: level) }
    }

    func clearHeading() {
        guard let level = active.headingLevel else { return }
        toggleHeading(level: level)
    }

    private func wrap(_ marker: String) {
        apply { MarkdownFormatter.toggleWrap(in: $0, selection: $1, marker: marker) }
    }

    private func linePrefix(_ prefix: String) {
        apply { MarkdownFormatter.toggleLinePrefix(in: $0, selection: $1, prefix: prefix) }
    }

    private func apply(_ edit: (NSString, NSRange) -> TextEdit) {
        guard let textView else { return }
        // Tapping the bar takes first responder away from the editor, and an
        // edit applied to a text view that isn't focused goes nowhere. The
        // selection survives the round trip, so taking it back is enough.
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        MarkdownFormatter.apply(
            edit(textView.text as NSString, textView.selectedRange),
            to: textView
        )
        refreshActiveFormats()
    }

    // MARK: - Context

    func refreshActiveFormats() {
        guard let textView else {
            active = ActiveFormats()
            return
        }
        active = MarkdownContext.active(
            in: textView.text as NSString,
            selection: textView.selectedRange
        )
    }
}
