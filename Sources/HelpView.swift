import SwiftUI

/// The keyboard reference. This app has almost no buttons on purpose, so this
/// window is where the app explains itself.
struct HelpView: View {
    private struct Shortcut: Identifiable {
        let keys: String
        let action: String
        var id: String { keys + action }
    }

    private struct Section: Identifiable {
        let title: String
        let shortcuts: [Shortcut]
        var id: String { title }
    }

    private let sections: [Section] = [
        Section(title: "Notes", shortcuts: [
            Shortcut(keys: "⌘N", action: "New note, ready to type"),
            Shortcut(keys: "⌘⌫", action: "Delete the current note"),
            Shortcut(keys: "⌘L", action: "Jump to the note list"),
            Shortcut(keys: "⇧⌘F", action: "Jump to search"),
        ]),
        Section(title: "Formatting", shortcuts: [
            Shortcut(keys: "⌘B", action: "Bold — wraps or unwraps **"),
            Shortcut(keys: "⌘I", action: "Italic — wraps or unwraps *"),
            Shortcut(keys: "⌘K", action: "Link, cursor waiting in the parens"),
            Shortcut(keys: "⌘1…⌘6", action: "Set the heading level, or clear it"),
        ]),
        Section(title: "View", shortcuts: [
            Shortcut(keys: "⌘/", action: "Switch between styled and raw markdown"),
        ]),
    ]

    private let menuOnly = [
        "Strikethrough", "Inline code", "Bullet list", "Blockquote", "Image",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes save themselves")
                        .font(.headline)
                    Text("There is no save command. Typing stops, the file is written. "
                         + "Each note is a plain .md file named after its own first heading.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                        ForEach(section.shortcuts) { shortcut in
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text(shortcut.keys)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 78, alignment: .leading)
                                Text(shortcut.action)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("If a shortcut doesn't respond")
                        .font(.headline)
                    Text("On keyboard layouts where a key needs Shift — ⌘/ on an Italian layout, "
                         + "for one — macOS moves the shortcut to a reachable key. The menu always "
                         + "shows the key it picked.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("On the Format menu and the formatting bar")
                        .font(.headline)
                    Text(menuOnly.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    Text("The formatting bar can be hidden from the View menu.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
