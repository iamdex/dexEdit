import SwiftUI

/// What the app shows before a notes folder has been chosen — the only moment
/// there is nothing to type into, and so the only place a welcome screen
/// belongs. Once a folder is picked this never appears again, and launch goes
/// straight to the cursor.
struct WelcomeView: View {
    @EnvironmentObject private var folderStore: NotesFolderStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 104, height: 104)
                    .padding(.bottom, 18)
            }

            Text("dexEdit")
                .font(.system(size: 30, weight: .semibold))
            Text("A fast place to put notes.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(spacing: 10) {
                point("Every note is a plain .md file in a folder you choose.")
                point("Nothing to save. Typing stops, the file is written.")
                point("Open the same notes in any other editor, any time.")
            }
            .padding(.top, 28)

            Button("Choose Notes Folder…") {
                folderStore.chooseFolder()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .padding(.top, 30)

            if let error = folderStore.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(.tertiary)
                .frame(width: 5, height: 5)
                .offset(y: -3)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(width: 380, alignment: .leading)
    }
}
