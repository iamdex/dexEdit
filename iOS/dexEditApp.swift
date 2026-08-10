import SwiftUI

@main
struct dexEditApp: App {
    @StateObject private var folderStore = NotesFolderStore()
    @StateObject private var library = NotesLibrary()
    @StateObject private var bridge = EditorBridge()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(folderStore)
                .environmentObject(library)
                .environmentObject(bridge)
        }
    }
}
