import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var folderStore: NotesFolderStore

    var body: some View {
        Group {
            if let folder = folderStore.folderURL {
                // M2 edits one fixed file; M3 replaces this with the note list.
                EditorScreen(fileURL: folder.appending(path: "scratch.md"))
                    .id(folder)
            } else {
                FolderPickerPrompt()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct EditorScreen: View {
    @StateObject private var note: NoteStore

    init(fileURL: URL) {
        _note = StateObject(wrappedValue: NoteStore(fileURL: fileURL))
    }

    var body: some View {
        MarkdownTextView(text: $note.text)
            .overlay(alignment: .bottom) {
                if let error = note.errorMessage {
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
    }
}
