import AppIntents
import SwiftUI
import WidgetKit

/// The extension exists for one button, and is likely to keep existing for one
/// button. A notes app's job is to be open before you have finished having the
/// thought; anything more elaborate than that belongs in the app itself.
@main
struct dexEditControls: WidgetBundle {
    var body: some Widget {
        NewNoteControl()
    }
}

/// One control, offered to Control Center, the Lock Screen and the Action
/// button. It knows nothing about any note — only how to ask for a new one.
struct NewNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.espertini.dexEdit.newNote") {
            ControlWidgetButton(action: NewNoteIntent()) {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
        .displayName("New Note")
        .description("Start writing in dexEdit.")
    }
}
