import MarkdownCore
import SwiftUI

/// How the sidebar lists notes.
enum SidebarMode: String, CaseIterable {
    /// Flat, newest first. What the app was built around: you come back to what
    /// you were just doing.
    case recent
    /// The folder tree, for a vault someone deliberately organised.
    case folders
}

/// The sidebar: either the recent list or the folder tree, filtered by the
/// search field. A search always flattens to results — the query beats the
/// structure, as it does in Obsidian.
struct NoteListView: View {
    @EnvironmentObject private var library: NotesLibrary
    @EnvironmentObject private var bridge: EditorBridge

    @AppStorage("sidebarMode") private var mode: SidebarMode = .recent
    @AppStorage("expandedFolders") private var expandedPaths = ""

    private enum Field: Hashable {
        case search
        case list
    }

    @FocusState private var focus: Field?

    private var isSearching: Bool {
        !library.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        list
            // An inset rather than a VStack, so the list's scroll content stops
            // at the search field instead of sliding under it.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    searchField
                    modePicker
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

    private var modePicker: some View {
        Picker("", selection: $mode) {
            Text("Recent").tag(SidebarMode.recent)
            Text("Folders").tag(SidebarMode.folders)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .disabled(isSearching)
        .help(isSearching ? "Search shows every match, wherever it lives" : "")
    }

    @ViewBuilder
    private var list: some View {
        List(selection: $library.selection) {
            if mode == .folders && !isSearching {
                FolderRows(
                    nodes: library.sidebarTree,
                    expanded: expandedBinding
                )
            } else {
                // Whenever the list is flat the badge is the only thing saying
                // where a note lives — including search results reached from
                // the folder view.
                ForEach(library.filteredNotes) { note in
                    NoteRow(summary: note.summary, availability: note.availability, isOnline: library.isOnline, folder: library.folderLabel(for: note))
                        .tag(note.id)
                }
            }
        }
        .listStyle(.sidebar)
        .focused($focus, equals: .list)
        .overlay {
            if isEmpty {
                emptyState
            }
        }
    }

    private var isEmpty: Bool {
        mode == .folders && !isSearching ? library.sidebarTree.isEmpty : library.filteredNotes.isEmpty
    }

    /// Which folders are open, remembered by path so the tree comes back the
    /// way you left it.
    private var expandedBinding: Binding<Set<String>> {
        Binding(
            get: { Set(expandedPaths.split(separator: "\n").map(String.init)) },
            set: { expandedPaths = $0.sorted().joined(separator: "\n") }
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        if isSearching {
            Text("No matches")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            VStack(spacing: 10) {
                Text("No notes yet")
                    .foregroundStyle(.secondary)
                Button("New Note") {
                    bridge.wantsEditorFocus = true
                    library.newNote()
                }
            }
            .padding()
        }
    }
}

/// The folder tree, drawn one level at a time.
private struct FolderRows: View {
    @EnvironmentObject private var library: NotesLibrary
    @EnvironmentObject private var bridge: EditorBridge

    let nodes: [SidebarNode]
    @Binding var expanded: Set<String>

    var body: some View {
        ForEach(nodes) { node in
            switch node.kind {
            case .folder(let url):
                DisclosureGroup(isExpanded: isExpanded(node.id)) {
                    FolderRows(nodes: node.children, expanded: $expanded)
                } label: {
                    FolderLabel(
                        name: node.name,
                        folder: url,
                        reveal: { expanded.insert(node.id) }
                    )
                }

            case .note(let id):
                if let note = library.note(id) {
                    NoteRow(summary: note.summary, availability: note.availability, isOnline: library.isOnline, folder: nil)
                        .tag(id)
                        .draggable(SidebarDrop.note(id))
                }
            }
        }
    }

    private func isExpanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
}

/// A folder row: the drop target, and the thing you can drag onto another one.
private struct FolderLabel: View {
    @EnvironmentObject private var library: NotesLibrary

    let name: String
    let folder: URL
    let reveal: () -> Void

    @State private var isTargeted = false

    var body: some View {
        Label(name, systemImage: "folder")
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isTargeted ? Color.accentColor.opacity(0.25) : .clear)
            )
            .contextMenu { FolderActions(folder: folder, reveal: reveal) }
            .draggable(SidebarDrop.folder(folder))
            .dropDestination(for: SidebarDrop.self) { items, _ in
                reveal()
                return accept(items)
            } isTargeted: { isTargeted = $0 }
    }

    private func accept(_ items: [SidebarDrop]) -> Bool {
        var moved = false
        for item in items {
            switch item {
            case .note(let id):
                library.move(id, to: folder)
                moved = true
            case .folder(let url):
                moved = library.moveFolder(url, into: folder) != nil || moved
            }
        }
        return moved
    }
}

private struct FolderActions: View {
    @EnvironmentObject private var library: NotesLibrary
    @EnvironmentObject private var bridge: EditorBridge

    let folder: URL
    /// Opens the folder, so whatever is created inside it is visible rather
    /// than filed away behind a closed disclosure triangle.
    let reveal: () -> Void

    var body: some View {
        Button("New Note Here") {
            reveal()
            bridge.wantsEditorFocus = true
            library.newNote(in: folder)
        }
        Button("New Folder…") {
            guard let name = FolderNamePrompt.run(inside: folder.lastPathComponent) else { return }
            reveal()
            library.createFolder(named: name, in: folder)
        }

        Divider()

        Button("Rename…") {
            guard let name = FolderNamePrompt.rename(folder.lastPathComponent) else { return }
            library.renameFolder(folder, to: name)
        }
        Button("Move to Trash") {
            library.folderDeletionRequest = folder
        }
    }
}

private struct NoteRow: View {
    let summary: Note.Summary
    let availability: Note.Availability
    let isOnline: Bool
    /// Only set for notes that live in a subfolder; most rows show no badge.
    let folder: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if let statusSymbol {
                    Image(systemName: statusSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(summary.title)
                    .lineLimit(1)
            }
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

    /// Nothing at all for a normal note. Only a note the app is holding but
    /// couldn't open needs to say so — it is still listed, and still there.
    ///
    /// A note waiting on iCloud says which kind of waiting it is doing: coming
    /// down, or unable to until there's a connection.
    private var statusSymbol: String? {
        switch availability {
        case .ready: nil
        case .notDownloaded: isOnline ? "arrow.down.circle" : "icloud.slash"
        case .unreadable: "exclamationmark.triangle"
        }
    }
}
