import MarkdownCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var folderStore: NotesFolderStore
    @EnvironmentObject private var library: NotesLibrary

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
        .onAppear { library.setFolder(folderStore.folderURL) }
        .onChange(of: folderStore.folderURL) { _, newValue in
            library.setFolder(newValue)
        }
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
    }
}

private struct EditorPane: View {
    @EnvironmentObject private var library: NotesLibrary

    var body: some View {
        Group {
            if let id = library.selection, library.note(id) != nil {
                MarkdownTextView(
                    text: Binding(
                        get: { library.text(for: id) },
                        set: { library.updateText($0, for: id) }
                    )
                )
                .id(id)
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

private struct WelcomeView: View {
    @EnvironmentObject private var folderStore: NotesFolderStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "number.square.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)

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
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
