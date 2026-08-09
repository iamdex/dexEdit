import AppKit

/// Asks for a folder name. Shared by the Move to Folder menu and the folder
/// tree's context menu, so both ask the same way.
enum FolderNamePrompt {
    /// Returns nil when cancelled or left blank.
    static func run(inside parent: String?) -> String? {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = parent.map { "Create a folder inside “\($0)”." }
            ?? "Create a folder inside your notes folder."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Folder name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
