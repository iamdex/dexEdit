import AppKit
import Combine

/// Lets the menu commands reach the live text view, and lets them move focus
/// between the three things that can hold it.
///
/// The menu bar lives at App scope and the text view is created deep inside a
/// representable; this is the seam between them.
final class EditorBridge: ObservableObject {
    enum FocusTarget {
        case editor
        case search
        case list
    }

    /// Identity carries a token so two requests for the same target still read
    /// as a change worth acting on.
    struct FocusRequest: Equatable {
        let target: FocusTarget
        let token = UUID()
    }

    weak var textView: NSTextView?

    @Published var focusRequest: FocusRequest?

    /// Set when the user has asked for an editor they mean to type in — at
    /// launch, and on Cmd+N. A new editor takes focus only then, so arrowing
    /// through the sidebar doesn't get hijacked by each note it lands on.
    var wantsEditorFocus = true

    // MARK: - Formatting

    func toggleBold() { wrap(with: "**") }
    func toggleItalic() { wrap(with: "*") }

    func insertLink() {
        guard let textView else { return }
        let edit = MarkdownFormatter.link(
            in: textView.string as NSString,
            selection: textView.selectedRange()
        )
        MarkdownFormatter.apply(edit, to: textView)
    }

    func toggleHeading(level: Int) {
        guard let textView else { return }
        let edit = MarkdownFormatter.toggleHeading(
            in: textView.string as NSString,
            selection: textView.selectedRange(),
            level: level
        )
        MarkdownFormatter.apply(edit, to: textView)
    }

    private func wrap(with marker: String) {
        guard let textView else { return }
        let edit = MarkdownFormatter.toggleWrap(
            in: textView.string as NSString,
            selection: textView.selectedRange(),
            marker: marker
        )
        MarkdownFormatter.apply(edit, to: textView)
    }

    // MARK: - Focus

    func focus(_ target: FocusTarget) {
        if target == .editor, let textView {
            textView.window?.makeFirstResponder(textView)
            return
        }
        focusRequest = FocusRequest(target: target)
    }
}
