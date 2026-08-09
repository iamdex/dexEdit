import AppKit
import Foundation

/// Owns every note in the folder, in memory, and keeps the folder in step.
///
/// There is no save command: content is written 500ms after typing stops, and
/// the file is renamed to follow the title on a much lazier 2s timer so it
/// doesn't thrash while a heading is being typed. Everything is flushed on note
/// switch, on window resign-key and at termination.
final class NotesLibrary: ObservableObject {
    private static let saveDelay: TimeInterval = 0.5
    private static let renameDelay: TimeInterval = 2.0

    /// Sorted by modified date, newest first.
    @Published private(set) var notes: [Note] = []

    @Published var selection: Note.ID? {
        didSet {
            guard oldValue != selection else { return }
            // Leaving a note commits it; nothing is ever half-written.
            flushPending()
        }
    }

    @Published var searchText: String = ""
    @Published private(set) var errorMessage: String?

    /// The note the user has asked to delete, pending confirmation.
    @Published var deletionRequest: Note.ID?

    private(set) var folderURL: URL?

    /// What is currently on disk for each note, so an untouched note is never
    /// rewritten.
    private var savedText: [Note.ID: String] = [:]
    private var pendingSaves: [Note.ID: DispatchWorkItem] = [:]
    private var pendingRenames: [Note.ID: DispatchWorkItem] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        observeFlushEvents()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Folder

    func setFolder(_ url: URL?) {
        guard url != folderURL else { return }
        flushPending()

        folderURL = url
        notes = []
        savedText = [:]
        selection = nil
        errorMessage = nil

        guard url != nil else { return }
        LaunchTimer.mark("folder load start")
        loadFromDisk()
        LaunchTimer.mark("folder loaded (\(notes.count) notes)")
        selection = notes.first?.id
    }

    private func loadFromDisk() {
        guard let folderURL else { return }

        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            errorMessage = "Couldn’t read the notes folder: \(error.localizedDescription)"
            return
        }

        var loaded: [Note] = []
        for url in contents where url.pathExtension.lowercased() == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let note = Note(
                fileURL: url,
                text: text,
                modified: values?.contentModificationDate ?? .distantPast
            )
            loaded.append(note)
            savedText[note.id] = text
        }

        notes = loaded
        sortNotes()
    }

    // MARK: - Reading

    var filteredNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return notes }
        return notes.filter { note in
            note.text.localizedCaseInsensitiveContains(query)
                || note.summary.title.localizedCaseInsensitiveContains(query)
        }
    }

    func note(_ id: Note.ID?) -> Note? {
        guard let id else { return nil }
        return notes.first { $0.id == id }
    }

    func text(for id: Note.ID) -> String {
        note(id)?.text ?? ""
    }

    // MARK: - Editing

    func updateText(_ newText: String, for id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].text != newText
        else { return }

        notes[index].text = newText
        scheduleSave(id)
        scheduleRename(id)
    }

    /// Adds an empty note and selects it. Nothing hits disk until it has content,
    /// so a new note abandoned immediately leaves no file behind.
    func newNote() {
        guard folderURL != nil else { return }
        let note = Note(fileURL: nil, text: "")
        notes.insert(note, at: 0)
        savedText[note.id] = ""
        selection = note.id
    }

    /// Asks for confirmation before deleting the selected note.
    func requestDeleteSelected() {
        guard let selection else { return }
        deletionRequest = selection
    }

    func confirmDeletion() {
        guard let id = deletionRequest else { return }
        deletionRequest = nil
        delete(id)
    }

    /// Moves the note's file to the Trash — recoverable, unlike unlinking it.
    func delete(_ id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

        pendingSaves.removeValue(forKey: id)?.cancel()
        pendingRenames.removeValue(forKey: id)?.cancel()

        if let url = notes[index].fileURL {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                errorMessage = "Couldn’t delete \(url.lastPathComponent): \(error.localizedDescription)"
                return
            }
        }

        notes.remove(at: index)
        savedText.removeValue(forKey: id)

        if selection == id {
            selection = notes.first?.id
        }
    }

    // MARK: - Saving

    private func scheduleSave(_ id: Note.ID) {
        pendingSaves.removeValue(forKey: id)?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSaves.removeValue(forKey: id)
            self?.writeIfNeeded(id)
        }
        pendingSaves[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    private func scheduleRename(_ id: Note.ID) {
        pendingRenames.removeValue(forKey: id)?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingRenames.removeValue(forKey: id)
            self?.renameIfNeeded(id)
        }
        pendingRenames[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.renameDelay, execute: work)
    }

    private func writeIfNeeded(_ id: Note.ID) {
        guard folderURL != nil, let index = notes.firstIndex(where: { $0.id == id }) else { return }

        let text = notes[index].text
        guard savedText[id] != text else { return }

        // An empty note that has never been saved stays out of the folder.
        let url: URL
        if let existing = notes[index].fileURL {
            url = existing
        } else {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            url = uniqueURL(slug: notes[index].slug, excluding: id)
        }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            notes[index].fileURL = url
            notes[index].modified = .now
            savedText[id] = text
            errorMessage = nil
            sortNotes()
        } catch {
            errorMessage = "Couldn’t save \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Renames the file to follow the note's title. Content is committed first so
    /// the move never leaves an unsaved edit pointing at the old name.
    private func renameIfNeeded(_ id: Note.ID) {
        writeIfNeeded(id)

        guard let index = notes.firstIndex(where: { $0.id == id }),
              let currentURL = notes[index].fileURL
        else { return }

        let wanted = notes[index].slug
        let currentBase = currentURL.deletingPathExtension().lastPathComponent
        // Already right, or already right with a dedupe suffix ("note-2").
        guard currentBase != wanted, !currentBase.hasPrefix(wanted + "-") else { return }

        let target = uniqueURL(slug: wanted, excluding: id)
        do {
            try FileManager.default.moveItem(at: currentURL, to: target)
            notes[index].fileURL = target
        } catch {
            errorMessage = "Couldn’t rename \(currentURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: - External changes

    /// Picks up edits made by other tools — Obsidian, a sync client, `vim`.
    /// Runs when the window becomes key, which is when the user could have been
    /// somewhere else. Real FSEvents watching is a later problem.
    func syncWithDisk() {
        guard let folderURL else { return }

        // Commit our own work first, so "newer on disk" means what it says.
        flushPending()

        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }

        let onDisk = contents.filter { $0.pathExtension.lowercased() == "md" }
        let known = Set(notes.compactMap(\.fileURL))
        var changed = false

        // Files that vanished while we weren't looking.
        for note in notes where note.fileURL != nil {
            guard let url = note.fileURL, !onDisk.contains(url) else { continue }
            notes.removeAll { $0.id == note.id }
            savedText.removeValue(forKey: note.id)
            changed = true
        }

        for url in onDisk {
            let modified = (try? url.resourceValues(forKeys: Set(keys)))?
                .contentModificationDate ?? .distantPast

            if let index = notes.firstIndex(where: { $0.fileURL == url }) {
                guard modified > notes[index].modified,
                      let text = try? String(contentsOf: url, encoding: .utf8),
                      text != notes[index].text
                else { continue }
                notes[index].text = text
                notes[index].modified = modified
                savedText[notes[index].id] = text
                changed = true
            } else if !known.contains(url) {
                // A note created outside the app.
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let note = Note(fileURL: url, text: text, modified: modified)
                notes.append(note)
                savedText[note.id] = text
                changed = true
            }
        }

        guard changed else { return }
        sortNotes()
        if selection == nil || !notes.contains(where: { $0.id == selection }) {
            selection = notes.first?.id
        }
    }

    /// Writes and renames everything outstanding, right now.
    func flushPending() {
        let saving = pendingSaves.keys
        let renaming = pendingRenames.keys

        pendingSaves.values.forEach { $0.cancel() }
        pendingSaves.removeAll()
        pendingRenames.values.forEach { $0.cancel() }
        pendingRenames.removeAll()

        for id in saving { writeIfNeeded(id) }
        for id in renaming { renameIfNeeded(id) }
    }

    // MARK: - Helpers

    private func sortNotes() {
        notes.sort { $0.modified > $1.modified }
    }

    /// A free filename for `slug`, adding "-2", "-3"… when one is taken.
    private func uniqueURL(slug: String, excluding id: Note.ID?) -> URL {
        guard let folderURL else { preconditionFailure("no notes folder") }

        var candidate = folderURL.appending(path: slug + ".md")
        var suffix = 2
        while isTaken(candidate, excluding: id) {
            candidate = folderURL.appending(path: "\(slug)-\(suffix).md")
            suffix += 1
        }
        return candidate
    }

    private func isTaken(_ url: URL, excluding id: Note.ID?) -> Bool {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        return notes.contains { $0.id != id && $0.fileURL == url }
    }

    private func observeFlushEvents() {
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSApplication.willTerminateNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.flushPending()
                }
            )
        }
        observers.append(
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.syncWithDisk()
            }
        )
    }
}
