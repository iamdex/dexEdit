import AppKit
import Foundation

/// Holds the text of one note and keeps the file on disk in step with it.
///
/// There is no save command anywhere in the app: writes happen 500ms after
/// typing stops, and are flushed when the window loses key or the app quits.
/// Writes are atomic, so a crash mid-write can never truncate a note.
final class NoteStore: ObservableObject {
    private static let autosaveDelay: TimeInterval = 0.5

    let fileURL: URL

    @Published var text: String {
        didSet {
            guard !isLoading, text != oldValue else { return }
            scheduleSave()
        }
    }

    @Published private(set) var errorMessage: String?

    /// What is currently on disk, so an unchanged buffer never rewrites the file.
    private var savedText: String
    private var pendingSave: DispatchWorkItem?
    private var isLoading = false
    private var observers: [NSObjectProtocol] = []

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.text = ""
        self.savedText = ""
        load()
        observeFlushEvents()
    }

    deinit {
        // `flush()` touches @Published state, which deinit must not do; write
        // straight through instead.
        pendingSave?.cancel()
        if text != savedText {
            try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Reads the file into the buffer. A file that does not exist yet is simply
    /// an empty note — it gets created on the first save.
    func load() {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            text = ""
            savedText = ""
            return
        }

        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            text = contents
            savedText = contents
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t open \(fileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Writes any pending change immediately.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        writeIfNeeded()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSave = nil
            self?.writeIfNeeded()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autosaveDelay, execute: work)
    }

    private func writeIfNeeded() {
        let snapshot = text
        guard snapshot != savedText else { return }
        do {
            try snapshot.write(to: fileURL, atomically: true, encoding: .utf8)
            savedText = snapshot
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t save \(fileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func observeFlushEvents() {
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSApplication.willTerminateNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.flush()
                }
            )
        }
    }
}
