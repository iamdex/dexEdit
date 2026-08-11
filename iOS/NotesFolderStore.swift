import SwiftUI
import UniformTypeIdentifiers

/// Owns the chosen notes folder and the sandbox access to it.
///
/// Same shape as the Mac's store, but iOS picks folders through a document
/// picker and its bookmarks have no `.withSecurityScope` option — the scope
/// comes from the picker itself and is re-established on resolve.
@MainActor
final class NotesFolderStore: ObservableObject {
    private static let bookmarkKey = "notesFolderBookmark"

    @Published private(set) var folderURL: URL?
    @Published private(set) var errorMessage: String?

    /// Shows the folder picker.
    @Published var isPickingFolder = false

    private var accessedURL: URL?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restoreFromBookmark()
    }

    /// Called with whatever the document picker handed back.
    func adopt(_ url: URL) {
        stopAccessing()

        // The picker hands back a security-scoped URL, and the scope has to be
        // open even to ask for a bookmark. Without it the sandbox can't so much
        // as stat the folder, and reports it as missing — which is what every
        // iCloud Drive folder did, since those live outside the sandbox and
        // come from the file provider. A folder on the device could get away
        // without this; one in iCloud never could.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: Self.bookmarkKey)
            errorMessage = nil
            restoreFromBookmark()
        } catch {
            folderURL = nil
            errorMessage = "Couldn’t remember that folder: \(error.localizedDescription)"
        }
    }

    private func restoreFromBookmark() {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            defaults.removeObject(forKey: Self.bookmarkKey)
            folderURL = nil
            errorMessage = "Your notes folder couldn’t be reopened. Choose it again."
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            folderURL = nil
            errorMessage = "Your notes folder couldn’t be reopened. Choose it again."
            return
        }
        accessedURL = url

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            stopAccessing()
            defaults.removeObject(forKey: Self.bookmarkKey)
            folderURL = nil
            errorMessage = "Your notes folder is missing. Choose it again."
            return
        }

        folderURL = url
        errorMessage = nil

        if isStale, let fresh = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
    }

    private func stopAccessing() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }
}
