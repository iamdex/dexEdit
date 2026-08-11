import MarkdownCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var folderStore: NotesFolderStore
    @EnvironmentObject private var library: NotesLibrary
    @EnvironmentObject private var bridge: EditorBridge
    @AppStorage("showFormatBar") private var showFormatBar = true
    @ObservedObject private var capture = QuickCapture.shared

    var body: some View {
        Group {
            if folderStore.folderURL != nil {
                NavigationSplitView {
                    NoteListView()
                        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
                } detail: {
                    EditorPane()
                }
                .navigationTitle(library.note(library.selection)?.summary.title ?? "dexEdit")
                .toolbar {
                    if showFormatBar {
                        ToolbarItemGroup(placement: .automatic) {
                            EditorToolbar(isEnabled: library.selection != nil)
                                .disabled(library.selection == nil)
                        }
                    }
                }
            } else {
                WelcomeView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            library.setFolder(folderStore.folderURL)
            startQuickCaptureIfAsked()
        }
        .onChange(of: folderStore.folderURL) { _, newValue in
            library.setFolder(newValue)
            startQuickCaptureIfAsked()
        }
        // The Mac has no Control Center button of its own yet, but the intent
        // is in this target too, so "New Note" shows up in Shortcuts — and a
        // shortcut that quietly does nothing is worse than no shortcut.
        .onChange(of: capture.isPending) { _, _ in startQuickCaptureIfAsked() }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { library.deletionRequest != nil },
                set: { if !$0 { library.deletionRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                library.confirmDeletion()
            }
            Button("Cancel", role: .cancel) {
                library.deletionRequest = nil
            }
        } message: {
            Text(library.note(library.deletionRequest)?.summary.title ?? "")
        }
        .confirmationDialog(
            "Delete this folder?",
            isPresented: Binding(
                get: { library.folderDeletionRequest != nil },
                set: { if !$0 { library.folderDeletionRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let folder = library.folderDeletionRequest {
                    library.folderDeletionRequest = nil
                    library.deleteFolder(folder)
                }
            }
            Button("Cancel", role: .cancel) {
                library.folderDeletionRequest = nil
            }
        } message: {
            if let folder = library.folderDeletionRequest {
                let count = library.noteCount(in: folder)
                Text(
                    count == 0
                        ? "“\(folder.lastPathComponent)” is empty."
                        : "“\(folder.lastPathComponent)” and the \(count) note\(count == 1 ? "" : "s") inside it."
                )
            }
        }
    }

    /// Turns a request from outside the app into the note it asked for. Held
    /// until there is a folder open, since the request can arrive during launch.
    private func startQuickCaptureIfAsked() {
        guard capture.isPending, library.folderURL != nil else { return }
        capture.isPending = false
        bridge.wantsEditorFocus = true
        library.newNote()
    }
}

private struct EditorPane: View {
    @EnvironmentObject private var library: NotesLibrary
    @EnvironmentObject private var bridge: EditorBridge
    @AppStorage("editorMode") private var mode: EditorMode = .styled

    var body: some View {
        Group {
            if let id = library.selection, let note = library.note(id) {
                if note.isReady {
                    MarkdownTextView(
                        text: Binding(
                            get: { library.text(for: id) },
                            set: { library.updateText($0, for: id) }
                        ),
                        mode: mode,
                        bridge: bridge
                    )
                    // A fresh text view per note: focus lands in it, and undo
                    // never reaches back into the note you just left.
                    .id(id)
                } else {
                    UnopenedNoteView(note: note)
                }
            } else {
                VStack(spacing: 6) {
                    Text("No note selected")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Press ⌘N to start one.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .overlay(alignment: .bottom) {
            if let error = library.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.red, in: RoundedRectangle(cornerRadius: 6))
                    .padding(12)
            }
        }
    }
}

/// A note that is listed but couldn't be opened.
///
/// Deliberately not an empty editor. An empty editor invites a keystroke, and
/// one keystroke would write emptiness over a file whose real contents are
/// sitting in iCloud, perfectly intact.
private struct UnopenedNoteView: View {
    let note: Note

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(note.summary.title)
                .font(.title3)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var symbol: String {
        switch note.availability {
        case .notDownloaded: "icloud.and.arrow.down"
        default: "exclamationmark.triangle"
        }
    }

    private var message: String {
        switch note.availability {
        case .notDownloaded:
            "This note is in iCloud and hasn’t reached this device yet. "
                + "It will open by itself once it arrives."
        case .unreadable(let reason):
            reason
        case .ready:
            ""
        }
    }
}

