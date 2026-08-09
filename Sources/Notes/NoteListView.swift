import SwiftUI

/// The sidebar: every note, newest first, filtered by the search field.
struct NoteListView: View {
    @EnvironmentObject private var library: NotesLibrary

    var body: some View {
        List(selection: $library.selection) {
            ForEach(library.filteredNotes) { note in
                NoteRow(summary: note.summary)
                    .tag(note.id)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $library.searchText, placement: .sidebar, prompt: "Search")
        .overlay {
            if library.filteredNotes.isEmpty {
                Text(library.searchText.isEmpty ? "No notes yet" : "No matches")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NoteRow: View {
    let summary: Note.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.title)
                .lineLimit(1)
            Text(summary.preview.isEmpty ? "No additional text" : summary.preview)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
