import AppKit
import SwiftUI

/// The editor: an `NSTextView` inside an `NSScrollView`, built by hand so the
/// text storage stays reachable for the live styling layer.
///
/// The buffer holds markdown plain text and nothing else. "Styled" and "raw" are
/// two renderings of the same characters — nothing here converts between formats.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var mode: EditorMode

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, mode: mode)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        // TextKit 1, explicitly: the styling layer needs NSTextStorageDelegate
        // and paragraph-scoped attribute fixes on a layout manager we own.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let contentSize = scrollView.contentSize
        let container = NSTextContainer(
            size: NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)

        let textView = CenteredTextView(
            frame: NSRect(origin: .zero, size: contentSize),
            textContainer: container
        )
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .textColor
        textView.textContainerInset = NSSize(
            width: EditorTheme.minHorizontalInset,
            height: EditorTheme.verticalInset
        )
        textView.typingAttributes = EditorTheme.baseAttributes(for: mode)
        textView.delegate = context.coordinator
        textStorage.delegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.replaceText(with: text)

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if context.coordinator.mode != mode {
            context.coordinator.mode = mode
            context.coordinator.restyleEverything()
        }

        // Only ever driven by an external change (note switch, reload from disk).
        // Typing round-trips through the coordinator, which leaves these equal.
        guard context.coordinator.textView?.string != text else { return }
        context.coordinator.replaceText(with: text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        @Binding private var text: String
        var mode: EditorMode
        weak var textView: NSTextView?

        init(text: Binding<String>, mode: EditorMode) {
            _text = text
            self.mode = mode
        }

        /// Replaces the whole buffer. Styling follows from the storage delegate,
        /// which sees this as one large edit.
        func replaceText(with newText: String) {
            guard let textView else { return }
            let previousSelection = textView.selectedRange()
            textView.string = newText
            textView.typingAttributes = EditorTheme.baseAttributes(for: mode)

            let location = min(previousSelection.location, (newText as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }

        func restyleEverything() {
            guard let storage = textView?.textStorage else { return }
            MarkdownStyler.apply(
                to: storage,
                range: NSRange(location: 0, length: storage.length),
                mode: mode
            )
            textView?.typingAttributes = EditorTheme.baseAttributes(for: mode)
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        // MARK: - NSTextStorageDelegate

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            // Attribute-only edits are our own work coming back around.
            guard editedMask.contains(.editedCharacters) else { return }

            let text = textStorage.string as NSString
            let paragraph = text.paragraphRange(for: editedRange)

            // A fence delimiter changes what every line below it means, so that
            // one edit — and only that one — pays for a full restyle.
            if MarkdownStyler.affectsFences(text, range: paragraph) {
                MarkdownStyler.apply(
                    to: textStorage,
                    range: NSRange(location: 0, length: text.length),
                    mode: mode
                )
                return
            }

            MarkdownStyler.apply(to: textStorage, range: paragraph, mode: mode)
        }
    }
}

/// Keeps the text column centred and capped at a readable width by growing the
/// horizontal container inset as the window widens.
private final class CenteredTextView: NSTextView {
    override func layout() {
        let available = enclosingScrollView?.contentSize.width ?? bounds.width
        let inset = max(
            EditorTheme.minHorizontalInset,
            (available - EditorTheme.maxLineWidth) / 2
        )
        // Guarded: assigning textContainerInset invalidates layout, so an
        // unconditional write here would recurse.
        if abs(textContainerInset.width - inset) > 0.5 {
            textContainerInset = NSSize(width: inset, height: EditorTheme.verticalInset)
        }
        super.layout()
    }
}
