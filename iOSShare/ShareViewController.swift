import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Add to dexEdit", from anywhere iOS offers a share sheet.
///
/// It shows what it is about to write and lets you say something about it
/// first, because a link with no sentence around it is a bookmark, not a note.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        Task { @MainActor in
            let text = await sharedText()
            show(text)
        }
    }

    private func show(_ text: String) {
        let editor = ShareEditor(
            text: text,
            onSave: { [weak self] final in self?.save(final) },
            onCancel: { [weak self] in self?.cancel() }
        )

        let host = UIHostingController(rootView: editor)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func save(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cancel() }

        do {
            try SharedInbox.write(trimmed)
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            // Saying nothing and dismissing would be a quiet lie about where
            // the thought went.
            let alert = UIAlertController(
                title: "Couldn’t save that",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.cancel()
            })
            present(alert, animated: true)
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    /// Whatever was shared, as markdown.
    ///
    /// A page arrives as a title and a URL, which is a markdown link waiting to
    /// happen; plain text arrives as itself.
    private func sharedText() async -> String {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return "" }

        var lines: [String] = []
        for item in items {
            let title = (item.attributedContentText?.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(
                       forTypeIdentifier: UTType.url.identifier
                   ) as? URL {
                    lines.append(title.isEmpty ? url.absoluteString : "[\(title)](\(url.absoluteString))")
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = try? await provider.loadItem(
                              forTypeIdentifier: UTType.plainText.identifier
                          ) as? String {
                    lines.append(text)
                }
            }

            // Some apps share only the text, with nothing attached at all.
            if (item.attachments ?? []).isEmpty, !title.isEmpty {
                lines.append(title)
            }
        }

        return lines.joined(separator: "\n\n")
    }
}

/// Deliberately plain: one text view, two buttons. The formatting bar, the
/// folders and the rest live in the app, and this is not the app.
private struct ShareEditor: View {
    @State var text: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body)
                .focused($focused)
                .padding(.horizontal, 12)
                .navigationTitle("New Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onCancel() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { onSave(text) }
                            .fontWeight(.semibold)
                    }
                }
                .onAppear {
                    // At the end, not the start: what was shared is context,
                    // and what you are about to type is the note.
                    if !text.isEmpty { text += "\n\n" }
                    focused = true
                }
        }
    }
}
