import AppKit
import Combine

/// Lets the menu commands and the formatting bar reach the live text view, and
/// lets them move focus between the three things that can hold it.
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

    /// Deliberately not @Published: the formatting bar observes this object
    /// instead, so a cursor move redraws the bar and nothing else.
    var formatState: FormatState?

    // MARK: - Formatting

    func toggleBold() { wrap(with: "**") }
    func toggleItalic() { wrap(with: "*") }
    func toggleStrike() { wrap(with: "~~") }
    func toggleCode() { wrap(with: "`") }

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

    /// Strips whatever heading the current line carries.
    func clearHeading() {
        guard let level = formatState?.active.headingLevel else { return }
        toggleHeading(level: level)
    }

    private func wrap(with marker: String) {
        apply { MarkdownFormatter.toggleWrap(in: $0, selection: $1, marker: marker) }
    }

    private func linePrefix(_ prefix: String) {
        apply { MarkdownFormatter.toggleLinePrefix(in: $0, selection: $1, prefix: prefix) }
    }

    private func apply(_ edit: (NSString, NSRange) -> TextEdit) {
        guard let textView else { return }
        MarkdownFormatter.apply(
            edit(textView.string as NSString, textView.selectedRange()),
            to: textView
        )
        refreshActiveFormats()
    }

    // MARK: - Context

    /// Recomputes what the formatting bar should show. Called on every cursor
    /// move, so it stays a single-line scan.
    func refreshActiveFormats() {
        guard let formatState else { return }
        guard let textView else {
            formatState.active = ActiveFormats()
            return
        }
        formatState.active = MarkdownContext.active(
            in: textView.string as NSString,
            selection: textView.selectedRange()
        )
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

/// The formatting bar's own state, kept apart from EditorBridge so that a
/// cursor move doesn't invalidate every view that reaches for the bridge.
final class FormatState: ObservableObject {
    @Published var active = ActiveFormats()
}
