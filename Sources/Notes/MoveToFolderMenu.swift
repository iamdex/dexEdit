import AppKit
import MarkdownCore
import SwiftUI

/// The Move to Folder submenu. Folders are a filing decision made after the
/// fact — capture stays at the top level, and moving is deliberate.
struct MoveToFolderMenu: View {
    @ObservedObject var library: NotesLibrary

    var body: some View {
        Menu("Move to Folder") {
            if let root = library.folderURL {
                Button("Notes (top level)") {
                    library.moveSelection(to: root)
                }
                .disabled(currentFolderIsRoot)

                let subfolders = library.folders
                if !subfolders.isEmpty {
                    Divider()
                    ForEach(subfolders, id: \.self) { folder in
                        Button(label(for: folder, root: root)) {
                            library.moveSelection(to: folder)
                        }
                    }
                }

                Divider()
                Button("New Folder…") { promptForNewFolder() }
            }
        }
        .disabled(library.selection == nil)
    }

    private var currentFolderIsRoot: Bool {
        guard let note = library.note(library.selection) else { return true }
        return library.folderLabel(for: note) == nil
    }

    /// Nested folders read as "parent/child", matching the sidebar badge.
    private func label(for folder: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = folder.standardizedFileURL.pathComponents
        guard components.count > rootComponents.count else { return folder.lastPathComponent }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func promptForNewFolder() {
        guard let name = FolderNamePrompt.run(inside: nil),
              let created = library.createFolder(named: name)
        else { return }
        library.moveSelection(to: created)
    }
}
