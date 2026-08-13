import AppIntents
import SwiftUI
import WidgetKit

/// The extension exists for one button, offered in every place iOS will take
/// one: Control Centre, the Lock Screen, the Action button, the Home Screen. A
/// notes app's job is to be open before you have finished having the thought;
/// anything more elaborate than that belongs in the app itself.
@main
struct dexEditControls: WidgetBundle {
    var body: some Widget {
        NewNoteControl()
        NewNoteWidget()
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
