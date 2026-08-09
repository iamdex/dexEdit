import SwiftUI

@main
struct dexEditApp: App {
    @StateObject private var folderStore = NotesFolderStore()
    @StateObject private var library = NotesLibrary()

    init() {
        // The window is the note; a tab bar is chrome this app has no use for.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(folderStore)
                .environmentObject(library)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
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
            CommandMenu("Note") {
                Button("Delete Note…") {
                    library.requestDeleteSelected()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(library.selection == nil)
            }
        }
    }
}
