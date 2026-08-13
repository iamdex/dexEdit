import Foundation
import MarkdownCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

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

    /// Every folder under the notes folder, empty ones included.
    @Published private(set) var folders: [URL] = []

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

    /// The folder the user has asked to delete, pending confirmation. Deleting
    /// a folder takes its notes with it, so it always asks.
    @Published var folderDeletionRequest: URL?

    private(set) var folderURL: URL?

    /// When the folder was last read. Every window becoming key asks for a
    /// sync — including About and Help — and the first one arrives moments
    /// after the launch read. Re-walking the tree that often is pure waste.
    private var lastReadFromDisk = Date.distantPast
    private static let syncCooldown: TimeInterval = 1.0

    /// Runs only while a note is waiting on iCloud. See `watchForDownloads`.
    private var downloadWatcher: Timer?
    private static let downloadPollInterval: TimeInterval = 2.0

    /// Tells the app when someone else changes the folder, so a note written on
    /// another device turns up without the app being brought to the front.
    private var watcher: FolderWatcher?

    /// What is currently on disk for each note, so an untouched note is never
    /// rewritten.
    private var savedText: [Note.ID: String] = [:]

    /// Where a note that has never been written is destined to go. A new note
    /// has no file, but the folder view still has to draw it somewhere.
    private var destinations: [Note.ID: URL] = [:]
    private var pendingSaves: [Note.ID: DispatchWorkItem] = [:]
    private var pendingRenames: [Note.ID: DispatchWorkItem] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        observeFlushEvents()
    }

    deinit {
        watcher?.stop()
        downloadWatcher?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Folder

    func setFolder(_ url: URL?) {
        guard url != folderURL else { return }
        flushPending()

        // Resolved, not merely standardized: a notes folder reached through a
        // symlink hands back paths from the other side of it, and every folder
        // comparison here is a string comparison.
        folderURL = url?.resolvingSymlinksInPath()
        notes = []
        savedText = [:]
        selection = nil
        errorMessage = nil
        // Nothing left to wait for; the notes it was waiting on are gone.
        watchForDownloads()

        watcher?.stop()
        watcher = nil
        CoordinatedFile.presenter = nil

        guard url != nil else { return }
        LaunchTimer.mark("folder load start")
        loadFromDisk()
        LaunchTimer.mark("folder loaded (\(notes.count) notes)")
        selection = notes.first?.id

        // After the first read, not before: registering a presenter on a folder
        // the app is in the middle of reading only invites it to announce that
        // very read back to us.
        if let folderURL {
            let watcher = FolderWatcher(folder: folderURL) { [weak self] changed in
                self?.syncWithDisk(reReading: changed)
            }
            self.watcher = watcher
            CoordinatedFile.presenter = watcher
        }
    }

    private func loadFromDisk() {
        guard folderURL != nil else { return }

        guard let files = markdownFiles() else { return }
        let urls = splittingConflicts(files)
        var loaded: [Note] = []

        CoordinatedFile.batchReading(urls) {
            for url in urls {
                let note = fetch(url)
                loaded.append(note)
                savedText[note.id] = note.text
            }
        }

        notes = loaded
        folders = scanFolders()
        sortNotes()
        lastReadFromDisk = .now
        watchForDownloads()
    }

    /// Reads a note, or records why it couldn't be read. Never returns nothing:
    /// a file that exists is a note, and a note quietly missing from the list is
    /// indistinguishable from a note that was lost.
    private func fetch(_ url: URL, id: Note.ID? = nil) -> Note {
        let state = CoordinatedFile.state(of: url)

        func note(_ text: String, _ availability: Note.Availability) -> Note {
            Note(
                id: id ?? UUID(),
                fileURL: url,
                text: text,
                modified: state.modified,
                availability: availability
            )
        }

        // Never coordinate a read of a file that isn't here: that call blocks
        // until the download finishes, which with no connection is forever.
        guard state.isDownloaded else {
            CoordinatedFile.startDownload(url)
            return note("", .notDownloaded)
        }

        do {
            return note(try CoordinatedFile.read(url), .ready)
        } catch {
            return note("", .unreadable(error.localizedDescription))
        }
    }

    /// Every .md file under the notes folder, at any depth. Notes sitting in a
    /// subfolder used to be invisible to the app rather than merely unsorted.
    /// nil when the folder could not be read at all — which is not the same
    /// answer as "there are no notes in it", and must never be confused with
    /// it. A folder in iCloud is briefly unreadable more often than you would
    /// think: right after launch, while the provider is still waking up.
    private func markdownFiles() -> [URL]? {
        guard let folderURL else { return nil }

        // Under a claim on the folder, so the file provider reconciles before
        // being asked what's in there. Without it the listing is whatever it
        // last cached, and a note from another device never appears at all.
        var found: [URL]?
        CoordinatedFile.readingDirectory(folderURL) {
            found = enumerateMarkdown(in: folderURL)
        }
        return found
    }

    private func enumerateMarkdown(in folderURL: URL) -> [URL]? {
        var failed = false
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in
                // The load-bearing part. An unreadable folder does not make
                // FileManager hand back nil — it hands back an enumerator that
                // politely yields nothing, which reads as "no notes here" and
                // is how the list came to be emptied. This is the only place
                // the difference is visible.
                failed = true
                return false
            }
        ) else {
            errorMessage = "Couldn’t read the notes folder."
            return nil
        }

        let found = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { $0.resolvingSymlinksInPath() }

        if failed {
            errorMessage = "Couldn’t read the notes folder."
            return nil
        }
        return found
    }

    /// The same files, plus a file for every side of an iCloud clash that was
    /// being kept out of sight. Run before anything is read, so a conflicting
    /// version becomes an ordinary note in the same pass that found it.
    private func splittingConflicts(_ urls: [URL]) -> [URL] {
        var out = urls
        for url in urls {
            out += CoordinatedFile.resolveConflicts(at: url)
        }
        return out
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    // MARK: - Folders

    /// Every subfolder of the notes folder, empty ones included — the folder
    /// view has to show a folder the moment it exists, not once it has a note
    /// in it. Read from disk, not derived from note paths.
    /// Keeps the folders it already knows about when the tree can't be read,
    /// for the same reason the notes are kept: an unanswerable question is not
    /// an answer of "none".
    private func scanFolders() -> [URL] {
        guard let folderURL else { return [] }

        var found: [URL]?
        CoordinatedFile.readingDirectory(folderURL) {
            found = enumerateFolders(in: folderURL)
        }
        return found ?? folders
    }

    private func enumerateFolders(in folderURL: URL) -> [URL]? {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map { $0.resolvingSymlinksInPath() }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// The folder view's rows, folders and notes together.
    var sidebarTree: [SidebarNode] {
        guard let folderURL else { return [] }
        return SidebarTree.build(
            root: folderURL,
            folders: folders,
            notes: notes,
            directoryOf: { [weak self] note in
                note.fileURL?.deletingLastPathComponent()
                    ?? self?.destinations[note.id]
                    ?? folderURL
            }
        )
    }

    /// Where a note lives, relative to the notes folder. nil when it sits at the
    /// top level, which is the common case and needs no badge.
    func folderLabel(for note: Note) -> String? {
        guard let folderURL, let fileURL = note.fileURL else { return nil }

        let root = folderURL.standardizedFileURL.pathComponents
        let directory = fileURL.deletingLastPathComponent().standardizedFileURL.pathComponents
        guard directory.count > root.count, Array(directory.prefix(root.count)) == root else {
            return nil
        }
        return directory.dropFirst(root.count).joined(separator: "/")
    }

    /// Creates a subfolder of the notes folder. Returns nil if the name is
    /// unusable or the folder couldn't be created.
    @discardableResult
    func createFolder(named name: String, in parent: URL? = nil) -> URL? {
        guard let folderURL else { return nil }
        let parent = parent ?? folderURL

        guard let cleaned = sanitizedFolderName(name) else { return nil }

        let target = parent.appending(path: cleaned)
        do {
            try CoordinatedFile.createDirectory(at: target)
            folders = scanFolders()
            return target
        } catch {
            errorMessage = "Couldn’t create the folder: \(error.localizedDescription)"
            return nil
        }
    }

    /// How many notes a folder holds, its subfolders included. The confirmation
    /// before deleting a folder has to say what it is about to take with it.
    func noteCount(in folder: URL) -> Int {
        let prefix = folder.standardizedFileURL.path + "/"
        return notes.count { ($0.fileURL?.standardizedFileURL.path ?? "").hasPrefix(prefix) }
    }

    /// Renames a folder in place. Everything inside it moves with it.
    @discardableResult
    func renameFolder(_ folder: URL, to newName: String) -> URL? {
        guard let cleaned = sanitizedFolderName(newName) else { return nil }
        let destination = folder.deletingLastPathComponent().appending(path: cleaned)
        return relocateFolder(folder, to: destination)
    }

    /// Moves a folder inside another one.
    @discardableResult
    func moveFolder(_ folder: URL, into parent: URL) -> URL? {
        relocateFolder(folder, to: parent.appending(path: folder.lastPathComponent))
    }

    /// Moves a folder and everything under it to the Trash.
    func deleteFolder(_ folder: URL) {
        guard let folderURL,
              folder.standardizedFileURL != folderURL.standardizedFileURL
        else { return }

        flushPending()

        do {
            try CoordinatedFile.trash(folder)
        } catch {
            errorMessage = "Couldn’t delete \(folder.lastPathComponent): \(error.localizedDescription)"
            return
        }

        let prefix = folder.standardizedFileURL.path + "/"
        let doomed = notes.filter {
            ($0.fileURL?.standardizedFileURL.path ?? "").hasPrefix(prefix)
        }
        for note in doomed {
            savedText.removeValue(forKey: note.id)
            destinations.removeValue(forKey: note.id)
            pendingSaves.removeValue(forKey: note.id)?.cancel()
            pendingRenames.removeValue(forKey: note.id)?.cancel()
        }
        let doomedIDs = Set(doomed.map(\.id))
        notes.removeAll { doomedIDs.contains($0.id) }

        folders = scanFolders()
        if selection == nil || !notes.contains(where: { $0.id == selection }) {
            selection = notes.first?.id
        }
    }

    /// The one move that rename and drag-and-drop both go through, so the
    /// guards are written once.
    @discardableResult
    private func relocateFolder(_ source: URL, to destination: URL) -> URL? {
        guard let folderURL else { return nil }

        let from = source.standardizedFileURL
        let to = destination.standardizedFileURL

        guard from != folderURL.standardizedFileURL else {
            errorMessage = "The notes folder itself can’t be moved."
            return nil
        }
        guard from != to else { return from }
        // A folder cannot be filed inside itself, however you drag it.
        guard !isDescendant(to, of: from) else {
            errorMessage = "A folder can’t be moved inside itself."
            return nil
        }
        guard !FileManager.default.fileExists(atPath: to.path) else {
            errorMessage = "There’s already something called “\(to.lastPathComponent)” there."
            return nil
        }

        flushPending()

        do {
            try CoordinatedFile.move(from, to: to)
        } catch {
            errorMessage = "Couldn’t move \(from.lastPathComponent): \(error.localizedDescription)"
            return nil
        }

        // Every note underneath now lives somewhere else.
        let prefix = from.path + "/"
        for index in notes.indices {
            guard let path = notes[index].fileURL?.standardizedFileURL.path,
                  path.hasPrefix(prefix)
            else { continue }
            notes[index].fileURL = to.appending(path: String(path.dropFirst(prefix.count)))
        }
        // Including the ones still waiting to be written for the first time.
        for (id, directory) in destinations {
            let path = directory.standardizedFileURL.path
            if path == from.path {
                destinations[id] = to
            } else if path.hasPrefix(prefix) {
                destinations[id] = to.appending(path: String(path.dropFirst(prefix.count)))
            }
        }

        folders = scanFolders()
        errorMessage = nil
        return to
    }

    /// A name is a single folder, never a path — slashes and colons would
    /// otherwise smuggle in a hierarchy or break the filesystem.
    private func sanitizedFolderName(_ name: String) -> String? {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !cleaned.isEmpty, !cleaned.hasPrefix(".") else { return nil }
        return cleaned
    }

    private func isDescendant(_ url: URL, of ancestor: URL) -> Bool {
        let ancestorPath = ancestor.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == ancestorPath || path.hasPrefix(ancestorPath + "/")
    }

    /// Moves a note's file into `directory`, keeping the note itself — and the
    /// selection, and the editor's undo stack — exactly where they were.
    func move(_ id: Note.ID, to directory: URL) {
        // Commit text and any pending rename first, so the file being moved is
        // the current one and nothing is left addressed to the old location.
        flushPending()

        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

        guard let current = notes[index].fileURL else {
            // Never written: give it a home now, unless it is still empty.
            let text = notes[index].text
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            destinations[id] = directory
            let target = uniqueURL(slug: notes[index].slug, in: directory, excluding: id)
            writeNote(at: index, to: target, text: text)
            return
        }

        guard current.deletingLastPathComponent().standardizedFileURL
            != directory.standardizedFileURL else { return }

        let slug = current.deletingPathExtension().lastPathComponent
        let target = uniqueURL(slug: slug, in: directory, excluding: id)
        do {
            try CoordinatedFile.move(current, to: target)
            notes[index].fileURL = target
        } catch {
            errorMessage = "Couldn’t move \(current.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func moveSelection(to directory: URL) {
        guard let selection else { return }
        move(selection, to: directory)
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
              // A note whose file we couldn't read has no text to change, and
              // an empty editor must never become the file's new contents.
              notes[index].isReady,
              notes[index].text != newText
        else { return }

        notes[index].text = newText
        scheduleSave(id)
        scheduleRename(id)
    }

    /// Adds an empty note and selects it. Nothing hits disk until it has content,
    /// so a new note abandoned immediately leaves no file behind.
    ///
    /// It lands beside the note you were reading, which is nearly always the
    /// folder you meant. Pass `directory` to say otherwise.
    func newNote(in directory: URL? = nil) {
        guard let folderURL else { return }

        let target = directory
            ?? note(selection)?.fileURL?.deletingLastPathComponent()
            ?? folderURL

        let note = Note(fileURL: nil, text: "")
        notes.insert(note, at: 0)
        savedText[note.id] = ""
        destinations[note.id] = target
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
                try CoordinatedFile.trash(url)
            } catch {
                errorMessage = "Couldn’t delete \(url.lastPathComponent): \(error.localizedDescription)"
                return
            }
        }

        notes.remove(at: index)
        savedText.removeValue(forKey: id)
        destinations.removeValue(forKey: id)

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
        guard let folderURL, let index = notes.firstIndex(where: { $0.id == id }) else { return }
        // Whatever is in that file, it is not what we are holding. Leave it.
        guard notes[index].isReady else { return }

        let text = notes[index].text
        guard savedText[id] != text else { return }

        // An empty note that has never been saved stays out of the folder.
        let url: URL
        if let existing = notes[index].fileURL {
            url = existing
        } else {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let directory = destinations[id] ?? folderURL
            url = uniqueURL(slug: notes[index].slug, in: directory, excluding: id)
        }

        writeNote(at: index, to: url, text: text)
    }

    private func writeNote(at index: Int, to url: URL, text: String) {
        do {
            try CoordinatedFile.write(text, to: url)
            notes[index].fileURL = url
            destinations.removeValue(forKey: notes[index].id)
            // The file's own date, not the clock. Recording a moment slightly
            // later than the one the filesystem recorded left the app believing
            // it held something newer than the file did — and an edit arriving
            // from another device with an honest, earlier date was discarded
            // as stale.
            notes[index].modified = CoordinatedFile.state(of: url).modified
            savedText[notes[index].id] = text
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
              // The title comes from the text, so a note we couldn't read would
              // rename a real file to "untitled".
              notes[index].isReady,
              let currentURL = notes[index].fileURL
        else { return }

        let wanted = notes[index].slug
        let currentBase = currentURL.deletingPathExtension().lastPathComponent
        // Already right, or already right with a dedupe suffix ("note-2").
        guard currentBase != wanted, !currentBase.hasPrefix(wanted + "-") else { return }

        // A rename keeps the note in its own folder; only Move changes that.
        let target = uniqueURL(
            slug: wanted,
            in: currentURL.deletingLastPathComponent(),
            excluding: id
        )
        do {
            try CoordinatedFile.move(currentURL, to: target)
            notes[index].fileURL = target
        } catch {
            errorMessage = "Couldn’t rename \(currentURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: - External changes

    /// Picks up edits made by other tools — Obsidian, a sync client, `vim`.
    /// Runs when the window becomes key, which is when the user could have been
    /// somewhere else. Real FSEvents watching is a later problem.
    /// The throttled entry point, for the flood of didBecomeKey notifications:
    /// every window sends one, About and Help included, and the first arrives
    /// moments after the launch read. Asking to sync is not the same as needing
    /// to, so the throttle lives here and not in the work itself.
    func syncIfStale() {
        guard Date.now.timeIntervalSince(lastReadFromDisk) > Self.syncCooldown else { return }
        syncWithDisk()
    }

    /// - Parameter reReading: files the file provider named as changed. These
    ///   are re-read whatever their modification date says. The date is a poor
    ///   witness across devices — it is written by whichever one made the edit,
    ///   and compared against a value this app partly made up — whereas being
    ///   told the file changed is not a guess at all.
    func syncWithDisk(reReading forced: Set<URL> = []) {
        guard folderURL != nil else { return }
        LaunchTimer.mark("sync start")
        defer {
            lastReadFromDisk = .now
            LaunchTimer.mark("sync done")
        }

        // Commit our own work first, so "newer on disk" means what it says.
        flushPending()

        // A folder we couldn't read tells us nothing, so we conclude nothing.
        // Reading an empty answer as "every note was deleted" would empty the
        // list over a folder that is merely busy.
        guard let files = markdownFiles() else { return }
        let onDisk = splittingConflicts(files)
        let present = Set(onDisk.map(\.standardizedFileURL))
        var changed = false

        // A note whose file is no longer where we left it. Before concluding it
        // was deleted, look for the same filename elsewhere in the tree: someone
        // dragging a note between folders in Finder must not reset its identity,
        // its selection or the editor's undo stack.
        let unclaimed = onDisk.filter { url in
            !notes.contains { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }
        }
        for index in notes.indices {
            guard let url = notes[index].fileURL?.standardizedFileURL,
                  !present.contains(url)
            else { continue }

            let sameName = unclaimed.filter { $0.lastPathComponent == url.lastPathComponent }
            // Only when it is unambiguous.
            if sameName.count == 1 {
                notes[index].fileURL = sameName[0]
                changed = true
            }
        }

        // Whatever is still missing might really be gone — but ask the file
        // itself before saying so. A listing can omit a file that is sitting
        // right there, and forgetting a note on the strength of one bad answer
        // is the one mistake that looks exactly like losing it.
        let stillPresent = Set(onDisk.map(\.standardizedFileURL))
        for note in notes {
            guard let url = note.fileURL?.standardizedFileURL,
                  !stillPresent.contains(url),
                  !FileManager.default.fileExists(atPath: url.path)
            else { continue }
            notes.removeAll { $0.id == note.id }
            savedText.removeValue(forKey: note.id)
            changed = true
        }

        let known = Set(notes.compactMap { $0.fileURL?.standardizedFileURL })

        for url in onDisk {
            let modified = modificationDate(of: url)

            if let index = notes.firstIndex(
                where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }
            ) {
                // Three reasons to look again, and only the first is a guess:
                // a newer date; a note we couldn't read last time, since a
                // download landing doesn't touch the date; and the provider
                // having told us in so many words that this file changed.
                guard forced.contains(url.standardizedFileURL)
                        || modified > notes[index].modified
                        || !notes[index].isReady
                else { continue }

                let fresh = fetch(url, id: notes[index].id)
                guard fresh.text != notes[index].text
                        || fresh.availability != notes[index].availability
                else { continue }

                notes[index] = fresh
                savedText[fresh.id] = fresh.text
                changed = true
            } else if !known.contains(url.standardizedFileURL) {
                // A note created outside the app.
                let note = fetch(url)
                notes.append(note)
                savedText[note.id] = note.text
                changed = true
            }
        }

        folders = scanFolders()
        watchForDownloads()

        guard changed else { return }
        sortNotes()
        if selection == nil || !notes.contains(where: { $0.id == selection }) {
            selection = notes.first?.id
        }
    }

    // MARK: - Downloads

    /// Keeps asking, while anything is still on its way down.
    ///
    /// A file arriving from iCloud changes nothing the app would otherwise
    /// notice — no notification, and not even a new modification date — so the
    /// only way a pending note becomes a real one is by looking again. The
    /// timer exists only while there is something to wait for, so an ordinary
    /// local folder never starts one.
    private func watchForDownloads() {
        let waiting = notes.contains { $0.availability == .notDownloaded }

        guard waiting else {
            downloadWatcher?.invalidate()
            downloadWatcher = nil
            return
        }
        guard downloadWatcher == nil else { return }

        downloadWatcher = Timer.scheduledTimer(
            withTimeInterval: Self.downloadPollInterval, repeats: true
        ) { [weak self] _ in
            self?.syncWithDisk()
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

    /// A free filename for `slug` inside `directory`, adding "-2", "-3"… when
    /// one is taken. Names only have to be unique within their own folder.
    private func uniqueURL(slug: String, in directory: URL, excluding id: Note.ID?) -> URL {
        var candidate = directory.appending(path: slug + ".md")
        var suffix = 2
        while isTaken(candidate, excluding: id) {
            candidate = directory.appending(path: "\(slug)-\(suffix).md")
            suffix += 1
        }
        return candidate
    }

    private func isTaken(_ url: URL, excluding id: Note.ID?) -> Bool {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        return notes.contains { $0.id != id && $0.fileURL == url }
    }

    /// The moments worth committing work at, and the moments worth checking
    /// whether someone else changed the folder. Same idea on both platforms,
    /// different names for it.
    #if os(macOS)
    private static let commitTriggers: [Notification.Name] = [
        NSWindow.didResignKeyNotification,
        NSApplication.willTerminateNotification,
    ]
    private static let refreshTriggers: [Notification.Name] = [
        NSWindow.didBecomeKeyNotification
    ]
    #else
    private static let commitTriggers: [Notification.Name] = [
        UIApplication.willResignActiveNotification,
        UIApplication.didEnterBackgroundNotification,
    ]
    private static let refreshTriggers: [Notification.Name] = [
        UIApplication.didBecomeActiveNotification
    ]
    #endif

    private func observeFlushEvents() {
        let center = NotificationCenter.default
        for name in Self.commitTriggers {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.flushPending()
                }
            )
        }
        for name in Self.refreshTriggers {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.syncIfStale()
                }
            )
        }
    }
}
