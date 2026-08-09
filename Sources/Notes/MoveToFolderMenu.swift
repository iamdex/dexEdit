import AppKit
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

                let subfolders = library.subfolders
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
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Create a folder inside your notes folder and move this note into it."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Folder name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let created = library.createFolder(named: field.stringValue) else { return }
        library.moveSelection(to: created)
    }
}
