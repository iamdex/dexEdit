import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var folderStore: NotesFolderStore

    var body: some View {
        Group {
            if let url = folderStore.folderURL {
                // Placeholder until M2 puts the editor here.
                VStack(spacing: 8) {
                    Text(url.lastPathComponent)
                        .font(.title2)
                    Text(url.path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button("Choose a Different Folder…") {
                        folderStore.chooseFolder()
                    }
                    .padding(.top, 8)
                }
            } else {
                FolderPickerPrompt()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
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
