import MarkdownCore
import SwiftUI

/// How the sidebar lists notes.
enum SidebarMode: String, CaseIterable {
    /// Flat, newest first — the half of the app that suits a device you pick up
    /// to capture something.
    case recent
    /// The folder tree, for a vault someone deliberately organised.
    case folders
}

/// The sidebar: the recent list or the folder tree, filtered by search. A
/// search always flattens to results, as it does on the Mac.
struct NoteListView: View {
    @EnvironmentObject private var library: NotesLibrary
    @EnvironmentObject private var folderStore: NotesFolderStore
    @EnvironmentObject private var bridge: EditorBridge

    @AppStorage("sidebarMode") private var mode: SidebarMode = .recent
    @AppStorage("expandedFolders") private var expandedPaths = ""

    @State private var namePrompt: NoteListPrompt?

    private var isSearching: Bool {
        !library.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        list
            .navigationTitle("Notes")
            .searchable(text: $library.searchText, prompt: "Search")
            .toolbar { toolbarContent }
            .sheet(item: $namePrompt) { prompt in
                switch prompt {
                case .newFolder(let parent):
                    FolderNamePrompt(
                        title: "New Folder",
                        message: "Created inside “\(folderName(parent))”.",
                        confirm: "Create",
                        name: ""
                    ) { name in
                        library.createFolder(named: name, in: parent)
                    }
                case .rename(let folder):
                    FolderNamePrompt(
                        title: "Rename Folder",
                        message: "Everything inside “\(folder.lastPathComponent)” moves with it.",
                        confirm: "Rename",
                        name: folder.lastPathComponent
                    ) { name in
                        library.renameFolder(folder, to: name)
                    }
                }
            }
    }

    @ViewBuilder
    private var list: some View {
        List(selection: $library.selection) {
            if mode == .folders && !isSearching {
                FolderRows(nodes: library.sidebarTree, expanded: expandedBinding) { prompt in
                    namePrompt = prompt
                }
            } else {
                ForEach(library.filteredNotes) { note in
                    NoteRow(summary: note.summary, folder: library.folderLabel(for: note))
                        .tag(note.id)
                        .draggable(SidebarDrop.note(note.id))
                }
            }
        }
        .overlay {
            if isEmpty {
                ContentUnavailableView(
                    isSearching ? "No matches" : "No notes yet",
                    systemImage: isSearching ? "magnifyingglass" : "note.text"
                )
            }
        }
    }

    private var isEmpty: Bool {
        mode == .folders && !isSearching
            ? library.sidebarTree.isEmpty
            : library.filteredNotes.isEmpty
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                bridge.wantsFocus = true
                library.newNote()
            } label: {
                Image(systemName: "square.and.pencil")
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("View", selection: $mode) {
                    Label("Recent", systemImage: "clock").tag(SidebarMode.recent)
                    Label("Folders", systemImage: "folder").tag(SidebarMode.folders)
                }
                .pickerStyle(.inline)
                .disabled(isSearching)

                Divider()

                if let root = library.folderURL {
                    Button {
                        namePrompt = .newFolder(parent: root)
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                }
                Button {
                    folderStore.isPickingFolder = true
                } label: {
                    Label("Choose Notes Folder…", systemImage: "folder")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func folderName(_ url: URL) -> String {
        url == library.folderURL ? "Notes" : url.lastPathComponent
    }

    /// Which folders are open, remembered by path.
    private var expandedBinding: Binding<Set<String>> {
        Binding(
            get: { Set(expandedPaths.split(separator: "\n").map(String.init)) },
            set: { expandedPaths = $0.sorted().joined(separator: "\n") }
        )
    }
}

/// The folder tree, drawn one level at a time.
private struct FolderRows: View {
    @EnvironmentObject private var library: NotesLibrary
    @EnvironmentObject private var bridge: EditorBridge

    let nodes: [SidebarNode]
    @Binding var expanded: Set<String>
    let prompt: (NoteListPrompt) -> Void

    var body: some View {
        ForEach(nodes) { node in
            switch node.kind {
            case .folder(let url):
                DisclosureGroup(isExpanded: isExpanded(node.id)) {
                    FolderRows(nodes: node.children, expanded: $expanded, prompt: prompt)
                } label: {
                    FolderLabel(
                        name: node.name,
                        folder: url,
                        reveal: { expanded.insert(node.id) },
                        prompt: prompt
                    )
                }

            case .note(let id):
                if let note = library.note(id) {
                    NoteRow(summary: note.summary, folder: nil)
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

/// What the sidebar wants a name for. Declared outside the view so the tree can
/// pass it back up.
enum NoteListPrompt: Identifiable {
    case newFolder(parent: URL)
    case rename(folder: URL)

    var id: String {
        switch self {
        case .newFolder(let parent): "new:" + parent.path
        case .rename(let folder): "rename:" + folder.path
        }
    }
}

/// A folder row: the drop target, and the thing you can drag onto another one.
private struct FolderLabel: View {
    @EnvironmentObject private var library: NotesLibrary
    @EnvironmentObject private var bridge: EditorBridge

    let name: String
    let folder: URL
    let reveal: () -> Void
    let prompt: (NoteListPrompt) -> Void

    @State private var isTargeted = false

    var body: some View {
        Label(name, systemImage: "folder")
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isTargeted ? Color.accentColor.opacity(0.25) : .clear)
            )
            .contextMenu {
                Button {
                    reveal()
                    bridge.wantsFocus = true
                    library.newNote(in: folder)
                } label: {
                    Label("New Note Here", systemImage: "square.and.pencil")
                }
                Button {
                    reveal()
                    prompt(.newFolder(parent: folder))
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }

                Divider()

                Button {
                    prompt(.rename(folder: folder))
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    library.folderDeletionRequest = folder
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
            }
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
