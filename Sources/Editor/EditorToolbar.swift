import SwiftUI

/// The formatting bar. Every button inserts or removes markdown characters —
/// exactly what the keyboard shortcuts do, and nothing the shortcuts can't.
///
/// It can be switched off in the View menu, which gives back the bare window
/// the app is designed around.
struct EditorToolbar: View {
    @EnvironmentObject private var bridge: EditorBridge
    @EnvironmentObject private var formatState: FormatState
    @AppStorage("editorMode") private var mode: EditorMode = .styled

    let isEnabled: Bool

    private var active: ActiveFormats { formatState.active }

    var body: some View {
        headingMenu
        FormatToggle(symbol: "bold", help: "Bold", isOn: active.bold) { bridge.toggleBold() }
        FormatToggle(symbol: "italic", help: "Italic", isOn: active.italic) { bridge.toggleItalic() }
        FormatToggle(symbol: "strikethrough", help: "Strikethrough", isOn: active.strike) {
            bridge.toggleStrike()
        }
        FormatToggle(
            symbol: "chevron.left.forwardslash.chevron.right",
            help: "Inline Code",
            isOn: active.code
        ) {
            bridge.toggleCode()
        }

        FormatToggle(symbol: "list.bullet", help: "Bullet List", isOn: active.bulletList) {
            bridge.toggleBulletList()
        }
        FormatToggle(symbol: "text.quote", help: "Blockquote", isOn: active.quote) {
            bridge.toggleQuote()
        }

        FormatToggle(symbol: "link", help: "Link", isOn: active.link) { bridge.insertLink() }

        overflowMenu
    }

    /// An explicit overflow, rather than trusting the toolbar to fold items away
    /// on its own — past a certain width it draws them but stops hit-testing them.
    private var overflowMenu: some View {
        Menu {
            // Inserting an image is an action, not a state to be in.
            Button("Insert Image") { bridge.insertImage() }
            Divider()
            Toggle("Raw Markdown", isOn: Binding(
                get: { mode == .raw },
                set: { _ in mode.toggle() }
            ))
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .disabled(!isEnabled)
        .help("More formatting")
    }

    private var headingMenu: some View {
        Menu {
            ForEach(1...6, id: \.self) { level in
                Button {
                    bridge.toggleHeading(level: level)
                } label: {
                    if active.headingLevel == level {
                        Label("Heading \(level)", systemImage: "checkmark")
                    } else {
                        Text("Heading \(level)")
                    }
                }
            }
            Divider()
            Button("Body Text") { bridge.clearHeading() }
                .disabled(active.headingLevel == nil)
        } label: {
            Label(
                active.headingLevel.map { "H\($0)" } ?? "Body",
                systemImage: "textformat.size"
            )
            // A toolbar Label is icon-only unless told otherwise, and the icon
            // alone can't say which level the cursor is on.
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .disabled(!isEnabled)
        .help("Heading level")
    }
}

/// A plain toolbar action, for things you do rather than things you are in.
private struct FormatButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(help, systemImage: symbol)
                .labelStyle(.iconOnly)
        }
        .help(help)
    }
}

/// A toolbar button that looks pressed while the cursor sits inside that
/// formatting.
private struct FormatToggle: View {
    let symbol: String
    let help: String
    let isOn: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in action() })) {
            Label(help, systemImage: symbol)
                .labelStyle(.iconOnly)
        }
        .toggleStyle(.button)
        .help(help)
    }
}
