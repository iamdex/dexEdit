import MarkdownCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var folderStore: NotesFolderStore
    @EnvironmentObject private var library: NotesLibrary
    @EnvironmentObject private var bridge: EditorBridge
    @AppStorage("editorMode") private var mode: EditorMode = .styled
    @ObservedObject private var capture = QuickCapture.shared

    var body: some View {
        Group {
            if folderStore.folderURL != nil {
                NavigationSplitView {
                    NoteListView()
                } detail: {
                    EditorPane()
                }
            } else {
                WelcomeView()
            }
        }
        .onAppear {
            library.setFolder(folderStore.folderURL)
            library.adoptSharedCaptures()
            startQuickCaptureIfAsked()
        }
        .onChange(of: folderStore.folderURL) { _, newValue in
            library.setFolder(newValue)
            library.adoptSharedCaptures()
            startQuickCaptureIfAsked()
        }
        // Both, because the control can arrive either way round: a cold launch
        // raises the flag before there is a folder to write into, and a warm
        // one finds the app already sitting there.
        .onChange(of: capture.isPending) { _, _ in startQuickCaptureIfAsked() }
        .fileImporter(
            isPresented: $folderStore.isPickingFolder,
            allowedContentTypes: [.folder]
        ) { result in
            guard case .success(let url) = result else { return }
            folderStore.adopt(url)
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { library.deletionRequest != nil },
                set: { if !$0 { library.deletionRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { library.confirmDeletion() }
            Button("Cancel", role: .cancel) { library.deletionRequest = nil }
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
            Button("Cancel", role: .cancel) { library.folderDeletionRequest = nil }
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
        // With a Magic Keyboard attached — half the time, on an iPad — these
        // are the same shortcuts as the Mac. They are declared once here rather
        // than on the editor, so they work wherever focus happens to be.
        .background {
            Group {
                Button("New Note") {
                    bridge.wantsFocus = true
                    library.newNote()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Bold") { bridge.toggleBold() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italic") { bridge.toggleItalic() }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Link") { bridge.insertLink() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Toggle Raw") { mode.toggle() }
                    .keyboardShortcut("/", modifiers: .command)

                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") { bridge.toggleHeading(level: level) }
                        .keyboardShortcut(KeyEquivalent(Character("\(level)")), modifiers: .command)
                }
            }
            .hidden()
        }
    }

    /// Turns a request from the control into the note it asked for.
    ///
    /// Held until there is a folder open: a control pressed on a cold launch
    /// runs before the app has read one, and a new note with nowhere to go
    /// would simply be dropped.
    private func startQuickCaptureIfAsked() {
        guard capture.isPending, library.folderURL != nil else { return }
        capture.isPending = false
        bridge.wantsFocus = true
        library.newNote()
    }
}

private struct EditorPane: View {
    @EnvironmentObject private var library: NotesLibrary
    @EnvironmentObject private var bridge: EditorBridge
    @AppStorage("editorMode") private var mode: EditorMode = .styled

    var body: some View {
        Group {
            if let id = library.selection, let note = library.note(id), !note.isReady {
                UnopenedNoteView(note: note, isOnline: library.isOnline)
                    .navigationTitle(note.summary.title)
                    .navigationBarTitleDisplayMode(.inline)
                    // No formatting bar — there is nothing to format — but the
                    // trash stays: a note you can't open is one of the few you
                    // might actually want to get rid of.
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                library.deletionRequest = id
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
            } else if let id = library.selection, library.note(id) != nil {
                MarkdownTextView(
                    text: Binding(
                        get: { library.text(for: id) },
                        set: { library.updateText($0, for: id) }
                    ),
                    mode: mode,
                    bridge: bridge
                )
                .id(id)
                // Part of the view, not of the navigation bar's toolbar.
                //
                // A bottom bar is a UIToolbar, and UIKit never lifts one out of
                // the keyboard's way, so the keyboard simply buried it. A safe
                // area inset is moved by the keyboard and stays put when there
                // isn't one — which is the whole requirement: reachable while
                // typing, and still there once the keyboard is dismissed or a
                // hardware one is attached.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    EditorToolbar()
                }
                .navigationTitle(library.note(id)?.summary.title ?? "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            library.deletionRequest = id
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Text("No note selected")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Tap + to start one.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
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
    let isOnline: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(note.summary.title)
                .font(.title3)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    private var symbol: String {
        switch note.availability {
        case .notDownloaded: isOnline ? "icloud.and.arrow.down" : "icloud.slash"
        default: "exclamationmark.triangle"
        }
    }

    /// Waiting for something on its way and waiting for something that cannot
    /// come are different situations, and saying so is the difference between
    /// patience and worry.
    private var message: String {
        switch note.availability {
        case .notDownloaded where !isOnline:
            "This note is in iCloud and hasn’t reached this device. "
                + "There’s no connection at the moment, so it can’t arrive until there is one. "
                + "Nothing is lost — it’s waiting."
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

private struct WelcomeView: View {
    @EnvironmentObject private var folderStore: NotesFolderStore

    var body: some View {
        VStack(spacing: 16) {
            // The real app icon, not a stand-in symbol.
            Image("AppMark")
                .resizable()
                .frame(width: 108, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 12, y: 4)

            Text("dexEdit")
                .font(.largeTitle.weight(.semibold))
            Text("A fast place to put notes.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Choose the folder your notes live in. Put it in iCloud Drive and the Mac app reads the very same files.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.top, 8)

            if let error = folderStore.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Button("Choose Notes Folder…") {
                folderStore.isPickingFolder = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.tint)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
