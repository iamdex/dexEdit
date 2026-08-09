import SwiftUI

@main
struct dexEditApp: App {
    @StateObject private var folderStore = NotesFolderStore()
    @StateObject private var library = NotesLibrary()
    @StateObject private var bridge = EditorBridge()
    @StateObject private var formatState = FormatState()
    @AppStorage("editorMode") private var mode: EditorMode = .styled
    @AppStorage("showFormatBar") private var showFormatBar = true

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
                .environmentObject(formatState)
                .onAppear { bridge.formatState = formatState }
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                OpenWindowButton(title: "About dexEdit", id: "about")
            }
            CommandGroup(replacing: .help) {
                OpenWindowButton(title: "dexEdit Help", id: "help")
                    .keyboardShortcut("?", modifiers: .command)
            }

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
                Toggle("Show Formatting Bar", isOn: $showFormatBar)

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
                Button("Strikethrough") { bridge.toggleStrike() }
                Button("Inline Code") { bridge.toggleCode() }

                Divider()

                Button("Bullet List") { bridge.toggleBulletList() }
                Button("Blockquote") { bridge.toggleQuote() }

                Divider()

                Button("Link") { bridge.insertLink() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Image") { bridge.insertImage() }

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

                MoveToFolderMenu(library: library)

                Divider()

                Button("Delete Note…") {
                    library.requestDeleteSelected()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(library.selection == nil)
            }
        }

        Window("About dexEdit", id: "about") {
            AboutView()
                .environmentObject(folderStore)
        }
        .windowResizability(.contentSize)

        Window("dexEdit Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }
}

/// Menu commands live at App scope, which has no environment of its own; a
/// one-line view does, and that is where openWindow can be reached.
private struct OpenWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    let title: String
    let id: String

    var body: some View {
        Button(title) { openWindow(id: id) }
    }
}
