import AppKit

/// Asks for a folder name. Shared by the Move to Folder menu and the folder
/// tree's context menu, so both ask the same way.
enum FolderNamePrompt {
    /// Returns nil when cancelled or left blank.
    static func run(inside parent: String?) -> String? {
        ask(
            title: "New Folder",
            message: parent.map { "Create a folder inside “\($0)”." }
                ?? "Create a folder inside your notes folder.",
            confirm: "Create",
            initial: ""
        )
    }

    static func rename(_ folder: String) -> String? {
        ask(
            title: "Rename Folder",
            message: "Everything inside “\(folder)” moves with it.",
            confirm: "Rename",
            initial: folder
        )
    }

    private static func ask(
        title: String,
        message: String,
        confirm: String,
        initial: String
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Folder name"
        field.stringValue = initial
        field.selectText(nil)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
