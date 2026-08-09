import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var folderStore: NotesFolderStore
    @EnvironmentObject private var library: NotesLibrary
    @AppStorage("showFormatBar") private var showFormatBar = true

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
        .onAppear { library.setFolder(folderStore.folderURL) }
        .onChange(of: folderStore.folderURL) { _, newValue in
            library.setFolder(newValue)
        }
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
    }
}

private struct EditorPane: View {
    @EnvironmentObject private var library: NotesLibrary
    @EnvironmentObject private var bridge: EditorBridge
    @AppStorage("editorMode") private var mode: EditorMode = .styled

    var body: some View {
        Group {
            if let id = library.selection, library.note(id) != nil {
                MarkdownTextView(
                    text: Binding(
                        get: { library.text(for: id) },
                        set: { library.updateText($0, for: id) }
                    ),
                    mode: mode,
                    bridge: bridge
                )
                // A fresh text view per note: focus lands in it, and undo never
                // reaches back into the note you just left.
                .id(id)
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

