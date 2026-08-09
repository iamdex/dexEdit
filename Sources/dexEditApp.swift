import SwiftUI

@main
struct dexEditApp: App {
    @StateObject private var folderStore = NotesFolderStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(folderStore)
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Choose Notes Folder…") {
                    folderStore.chooseFolder()
                }
            }
        }
    }
}
