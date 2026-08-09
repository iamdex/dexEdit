import SwiftUI

@main
struct dexEditApp: App {
    @StateObject private var folderStore = NotesFolderStore()
    @StateObject private var library = NotesLibrary()
    @StateObject private var bridge = EditorBridge()
    @AppStorage("editorMode") private var mode: EditorMode = .styled

    init() {
        LaunchTimer.mark("app init")
        // The window is the note; a tab bar is chrome this app has no use for.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(folderStore)
                .environmentObject(library)
                .environmentObject(bridge)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    // The new editor is created after this state change, and
                    // consumes the flag when it appears.
                    bridge.wantsEditorFocus = true
                    library.newNote()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Choose Notes Folder…") {
                    folderStore.chooseFolder()
                }
            }
            CommandGroup(replacing: .saveItem) {
                // Deliberately empty: there is no save command in this app.
            }

            CommandGroup(after: .sidebar) {
                Divider()
                Button("Search Notes") {
                    bridge.focus(.search)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Note List") {
                    bridge.focus(.list)
                }
                .keyboardShortcut("l", modifiers: .command)
            }

            CommandMenu("Format") {
                Button("Bold") { bridge.toggleBold() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italic") { bridge.toggleItalic() }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Link") { bridge.insertLink() }
                    .keyboardShortcut("k", modifiers: .command)

                Divider()

                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") { bridge.toggleHeading(level: level) }
                        .keyboardShortcut(
                            KeyEquivalent(Character("\(level)")),
                            modifiers: .command
                        )
                }
            }

            CommandMenu("Note") {
                Button(mode == .styled ? "Show Raw Markdown" : "Show Styled Markdown") {
                    mode.toggle()
                }
                .keyboardShortcut("/", modifiers: .command)

                Divider()

                Button("Delete Note…") {
                    library.requestDeleteSelected()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(library.selection == nil)
            }
        }
    }
}
