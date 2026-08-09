import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var folderStore: NotesFolderStore
    @EnvironmentObject private var library: NotesLibrary

    var body: some View {
        Group {
            if folderStore.folderURL != nil {
                NavigationSplitView {
                    NoteListView()
                        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
                } detail: {
                    EditorPane()
                }
            } else {
                FolderPickerPrompt()
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
    @AppStorage("editorMode") private var mode: EditorMode = .styled

    var body: some View {
        Group {
            if let id = library.selection, library.note(id) != nil {
                MarkdownTextView(
                    text: Binding(
                        get: { library.text(for: id) },
                        set: { library.updateText($0, for: id) }
                    ),
                    mode: mode
                )
                // A fresh text view per note: focus lands in it, and undo never
                // reaches back into the note you just left.
                .id(id)
            } else {
                Text("No note selected")
                    .foregroundStyle(.secondary)
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

private struct FolderPickerPrompt: View {
    @EnvironmentObject private var folderStore: NotesFolderStore

    var body: some View {
        VStack(spacing: 12) {
            Text("Choose a notes folder")
                .font(.title2)
            Text("Your notes are plain .md files kept in a folder you pick.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let error = folderStore.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Button("Choose Folder…") {
                folderStore.chooseFolder()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
