import SwiftUI

/// The About window. Says what this is, which version, and where the notes are —
/// the last of which is the only thing here anyone is likely to look up twice.
struct AboutView: View {
    @EnvironmentObject private var folderStore: NotesFolderStore

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            VStack(spacing: 4) {
                Text("dexEdit")
                    .font(.system(size: 24, weight: .semibold))
                Text(version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("A fast place to put notes. Every note is a plain .md file you can open with anything else.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let folder = folderStore.folderURL {
                VStack(spacing: 4) {
                    Text("Notes folder")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    } label: {
                        Text(folder.path)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.link)
                    .help("Show in Finder")
                }
            }
        }
        .padding(28)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
