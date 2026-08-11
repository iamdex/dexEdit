import AppIntents
import Foundation

/// A request to start writing that arrived from outside the app: the control in
/// Control Center, on the Lock Screen, or bound to the Action button.
///
/// The intent runs in the app's own process, so there is nothing to send
/// anywhere — it raises a flag the app is watching. A flag rather than a direct
/// call, because the request usually arrives while the app is still launching,
/// before there is a notes folder to put a note in. The app picks it up as soon
/// as it has one.
@MainActor
final class QuickCapture: ObservableObject {
    static let shared = QuickCapture()

    @Published var isPending = false

    private init() {}
}

/// "New Note", as the rest of the system sees it.
///
/// `openAppWhenRun` is what makes the whole thing worth having: the app comes
/// to the front with an empty note and the cursor already in it, which is one
/// press of the Action button away from a thought being written down.
struct NewNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "New Note"
    static var description = IntentDescription("Opens dexEdit with an empty note, ready to type.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCapture.shared.isPending = true
        return .result()
    }
}
