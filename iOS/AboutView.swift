import SwiftUI

/// About and the keyboard reference, in one sheet with two tabs.
///
/// Two separate windows made sense on the Mac, where they are two menu items.
/// On iPad they are one thing you open, look at, and close.
struct AboutView: View {
    @EnvironmentObject private var folderStore: NotesFolderStore
    @Environment(\.dismiss) private var dismiss

    @State private var tab = Tab.about

    private enum Tab: String, CaseIterable {
        case about = "About"
        case help = "Keyboard"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()

                Divider()

                ScrollView {
                    switch tab {
                    case .about: about
                    case .help: help
                    }
                }
            }
            .navigationTitle("dexEdit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    private var about: some View {
        VStack(spacing: 14) {
            Image("AppMark")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                .padding(.top, 24)

            Text("dexEdit")
                .font(.title2.weight(.semibold))
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("A fast place to put notes. Every note is a plain .md file you can open with anything else.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let folder = folderStore.folderURL {
                VStack(spacing: 4) {
                    Text("Notes folder")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(folder.lastPathComponent)
                        .font(.callout)
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes save themselves")
                    .font(.headline)
                Text("There is no save button. Typing stops, the file is written. "
                     + "Each note is a plain .md file named after its own first heading.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("With a hardware keyboard")
                    .font(.headline)
                shortcut("⌘N", "New note, ready to type")
                shortcut("⌘B", "Bold — wraps or unwraps **")
                shortcut("⌘I", "Italic — wraps or unwraps *")
                shortcut("⌘K", "Link, cursor waiting in the parens")
                shortcut("⌘1…⌘6", "Set the heading level, or clear it")
                shortcut("⌘/", "Switch between styled and raw markdown")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Without one")
                    .font(.headline)
                Text("Everything above is on the formatting bar under the editor. "
                     + "Long-press a folder for New Note Here, New Folder, Rename and "
                     + "Move to Trash, and drag notes onto folders to file them.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortcut(_ keys: String, _ action: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .frame(width: 78, alignment: .leading)
            Text(action)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
