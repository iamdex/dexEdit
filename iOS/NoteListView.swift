import MarkdownCore
import SwiftUI

/// The sidebar. Flat and newest-first, which is the half of the Mac app that
/// suits a device you pick up to capture something.
struct NoteListView: View {
    @EnvironmentObject private var library: NotesLibrary
    @EnvironmentObject private var folderStore: NotesFolderStore
    @EnvironmentObject private var bridge: EditorBridge

    var body: some View {
        List(selection: $library.selection) {
            ForEach(library.filteredNotes) { note in
                NoteRow(summary: note.summary, folder: library.folderLabel(for: note))
                    .tag(note.id)
            }
        }
        .searchable(text: $library.searchText, prompt: "Search")
        .navigationTitle("Notes")
        .overlay {
            if library.filteredNotes.isEmpty {
                ContentUnavailableView(
                    library.searchText.isEmpty ? "No notes yet" : "No matches",
                    systemImage: library.searchText.isEmpty ? "note.text" : "magnifyingglass"
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // A new note is one you mean to type in, so the editor
                    // takes the keyboard rather than waiting to be tapped.
                    bridge.wantsFocus = true
                    library.newNote()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Choose Notes Folder…") {
                        folderStore.isPickingFolder = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}

private struct NoteRow: View {
    let summary: Note.Summary
    let folder: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summary.title)
                .lineLimit(1)
            HStack(spacing: 5) {
                if let folder {
                    Label(folder, systemImage: "folder")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                Text(summary.preview.isEmpty ? "No additional text" : summary.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
