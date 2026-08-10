import MarkdownCore
import SwiftUI
import UIKit

/// The editor: a `UITextView` built by hand on TextKit 1, so the same
/// paragraph-scoped styling the Mac uses works unchanged here.
///
/// The buffer holds markdown plain text and nothing else.
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    var mode: EditorMode = .styled
    var bridge: EditorBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, mode: mode)
    }

    func makeUIView(context: Context) -> UITextView {
        // TextKit 1, explicitly: the styling layer needs NSTextStorageDelegate,
        // and the TextKit 2 path does not offer one.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: CGSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        ))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = CenteredTextView(frame: .zero, textContainer: container)
        textView.backgroundColor = .systemBackground
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainerInset = UIEdgeInsets(
            top: EditorTheme.verticalInset,
            left: EditorTheme.minHorizontalInset,
            bottom: EditorTheme.verticalInset,
            right: EditorTheme.minHorizontalInset
        )
        textView.typingAttributes = EditorTheme.baseAttributes(for: mode)
        textView.delegate = context.coordinator
        textStorage.delegate = context.coordinator

        context.coordinator.textView = textView
        context.coordinator.replaceText(with: text)

        // The formatting bar reaches the editor through here.
        bridge.textView = textView
        context.coordinator.onSelectionChanged = { [weak bridge] in
            bridge?.refreshActiveFormats()
        }
        bridge.refreshActiveFormats()

        if bridge.wantsFocus {
            bridge.wantsFocus = false
            DispatchQueue.main.async { textView.becomeFirstResponder() }
        }

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if context.coordinator.mode != mode {
            context.coordinator.mode = mode
            context.coordinator.restyleEverything()
        }

        // Only ever driven by an external change; typing round-trips through
        // the coordinator, which leaves these equal.
        guard textView.text != text else { return }
        context.coordinator.replaceText(with: text)
    }

    final class Coordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate {
        @Binding private var text: String
        var mode: EditorMode
        weak var textView: UITextView?

        /// Tells the formatting bar the cursor moved.
        var onSelectionChanged: (() -> Void)?

        init(text: Binding<String>, mode: EditorMode) {
            _text = text
            self.mode = mode
        }

        func replaceText(with newText: String) {
            guard let textView else { return }
            let previousSelection = textView.selectedRange
            textView.text = newText
            textView.typingAttributes = EditorTheme.baseAttributes(for: mode)

            let location = min(previousSelection.location, (newText as NSString).length)
            textView.selectedRange = NSRange(location: location, length: 0)
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

        // MARK: - UITextViewDelegate

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            onSelectionChanged?()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            onSelectionChanged?()
        }

        // MARK: - NSTextStorageDelegate

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }

            let text = textStorage.string as NSString
            let paragraph = text.paragraphRange(for: editedRange)

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

/// Keeps the text column centred and capped at a readable width — the iPad is
/// wide enough for that to matter.
private final class CenteredTextView: UITextView {
    override func layoutSubviews() {
        let inset = max(
            EditorTheme.minHorizontalInset,
            (bounds.width - EditorTheme.maxLineWidth) / 2
        )
        if abs(textContainerInset.left - inset) > 0.5 {
            textContainerInset = UIEdgeInsets(
                top: EditorTheme.verticalInset,
                left: inset,
                bottom: EditorTheme.verticalInset,
                right: inset
            )
        }
        super.layoutSubviews()
    }
}
