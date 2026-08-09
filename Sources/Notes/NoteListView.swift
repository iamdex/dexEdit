import MarkdownCore
import SwiftUI

/// The sidebar: every note, newest first, filtered by the search field.
struct NoteListView: View {
    @EnvironmentObject private var library: NotesLibrary
    @EnvironmentObject private var bridge: EditorBridge

    private enum Field: Hashable {
        case search
        case list
    }

    @FocusState private var focus: Field?

    var body: some View {
        list
            // An inset rather than a VStack, so the list's scroll content stops
            // at the search field instead of sliding under it.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    searchField
                    Divider()
                }
                .background(.bar)
            }
            .onChange(of: bridge.focusRequest) { _, request in
                switch request?.target {
                case .search: focus = .search
                case .list: focus = .list
                default: break
                }
            }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $library.searchText)
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
                .onSubmit { focus = .list }
            if !library.searchText.isEmpty {
                Button {
                    library.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var list: some View {
        List(selection: $library.selection) {
            ForEach(library.filteredNotes) { note in
                NoteRow(summary: note.summary, folder: library.folderLabel(for: note))
                    .tag(note.id)
            }
        }
        .listStyle(.sidebar)
        .focused($focus, equals: .list)
        .overlay {
            if library.filteredNotes.isEmpty {
                emptyState
            }
        }
    }
}

private extension NoteListView {
    @ViewBuilder
    var emptyState: some View {
        if library.searchText.isEmpty {
            VStack(spacing: 10) {
                Text("No notes yet")
                    .foregroundStyle(.secondary)
                Button("New Note") {
                    bridge.wantsEditorFocus = true
                    library.newNote()
                }
            }
            .padding()
        } else {
            Text("No matches")
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

private struct NoteRow: View {
    let summary: Note.Summary
    /// Only set for notes that live in a subfolder; most rows show no badge.
    let folder: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
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
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
