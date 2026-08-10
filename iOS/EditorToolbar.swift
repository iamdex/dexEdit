import MarkdownCore
import SwiftUI

/// The formatting bar, sitting above the keyboard.
///
/// On the Mac this was an optional convenience; here it is the only way to
/// reach most of these, because a touch keyboard has no shortcuts.
struct EditorToolbar: View {
    @EnvironmentObject private var bridge: EditorBridge
    @AppStorage("editorMode") private var mode: EditorMode = .styled

    private var active: ActiveFormats { bridge.active }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                headingMenu

                Divider().frame(height: 22)

                button("bold", active: active.bold) { bridge.toggleBold() }
                button("italic", active: active.italic) { bridge.toggleItalic() }
                button("strikethrough", active: active.strike) { bridge.toggleStrike() }
                button(
                    "chevron.left.forwardslash.chevron.right",
                    active: active.code
                ) { bridge.toggleCode() }

                Divider().frame(height: 22)

                button("list.bullet", active: active.bulletList) { bridge.toggleBulletList() }
                button("text.quote", active: active.quote) { bridge.toggleQuote() }

                Divider().frame(height: 22)

                button("link", active: active.link) { bridge.insertLink() }
                button("photo", active: false) { bridge.insertImage() }

                Divider().frame(height: 22)

                button("curlybraces", active: mode == .raw) { mode.toggle() }
            }
            .padding(.horizontal, 4)
        }
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
            HStack(spacing: 2) {
                Image(systemName: "textformat.size")
                Text(active.headingLevel.map { "H\($0)" } ?? "Body")
                    .font(.subheadline)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
        }
    }

    private func button(
        _ symbol: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 38, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? Color.accentColor.opacity(0.22) : .clear)
                )
        }
    }
}
