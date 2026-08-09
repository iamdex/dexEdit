import AppKit
import SwiftUI

/// The editor: an `NSTextView` inside an `NSScrollView`, built by hand so the
/// text storage stays reachable for the live styling layer in M4.
///
/// The buffer holds markdown plain text and nothing else. Nothing here converts
/// between formats — there is only one format.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
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
        textView.font = EditorTheme.bodyFont
        textView.typingAttributes = EditorTheme.baseAttributes
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.textView = textView

        context.coordinator.replaceText(with: text)

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Only ever driven by an external change (note switch, reload from disk).
        // Typing round-trips through the coordinator, which leaves these equal.
        guard context.coordinator.textView?.string != text else { return }
        context.coordinator.replaceText(with: text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            _text = text
        }

        /// Replaces the whole buffer and restores the base attributes, which
        /// setting `string` throws away.
        func replaceText(with newText: String) {
            guard let textView else { return }
            let previousSelection = textView.selectedRange()
            textView.string = newText

            let full = NSRange(location: 0, length: (newText as NSString).length)
            textView.textStorage?.setAttributes(EditorTheme.baseAttributes, range: full)
            textView.typingAttributes = EditorTheme.baseAttributes

            let location = min(previousSelection.location, full.length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
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
