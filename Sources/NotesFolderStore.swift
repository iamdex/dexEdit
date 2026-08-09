import AppKit
import Foundation

/// Owns the user's chosen notes folder and the sandbox access to it.
///
/// The folder is picked once with `NSOpenPanel` and remembered as an app-scoped
/// security-scoped bookmark in `UserDefaults`. Every launch resolves that
/// bookmark and holds access open for the lifetime of the process — all file
/// work in the app happens inside that window.
final class NotesFolderStore: ObservableObject {
    private static let bookmarkKey = "notesFolderBookmark"

    /// The folder to read and write notes in, or nil until one is chosen.
    @Published private(set) var folderURL: URL?

    /// Set when the folder could not be restored or adopted, for display in the UI.
    @Published private(set) var errorMessage: String?

    /// The URL currently held open by `startAccessingSecurityScopedResource()`.
    private var accessedURL: URL?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restoreFromBookmark()
    }

    deinit {
        accessedURL?.stopAccessingSecurityScopedResource()
    }

    /// Shows the folder picker and adopts the result. Returns when the user is done.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder where your notes live."
        panel.directoryURL = folderURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        adopt(url)
    }

    /// Forgets the current folder. The files themselves are untouched.
    func forgetFolder() {
        stopAccessing()
        defaults.removeObject(forKey: Self.bookmarkKey)
        folderURL = nil
        errorMessage = nil
    }

    // MARK: - Bookmarks

    /// Stores a bookmark for a freshly picked folder, then goes through the same
    /// resolve path as a relaunch so there is only one way access is ever opened.
    private func adopt(_ url: URL) {
        stopAccessing()
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
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
                options: [.withSecurityScope],
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

        // The folder moved or was renamed; the resolved URL is still good, but the
        // stored bookmark needs rewriting so the next launch resolves cleanly.
        if isStale, let fresh = try? url.bookmarkData(
            options: [.withSecurityScope],
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
