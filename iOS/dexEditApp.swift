import SwiftUI

@main
struct dexEditApp: App {
    @StateObject private var folderStore = NotesFolderStore()
    @StateObject private var library = NotesLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(folderStore)
                .environmentObject(library)
        }
    }
}
