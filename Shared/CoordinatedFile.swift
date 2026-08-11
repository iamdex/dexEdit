import Foundation

/// Every touch of a note file goes through here.
///
/// A notes folder in iCloud Drive — or Dropbox, or anything else with a file
/// provider — has a second writer the app knows nothing about. Reading a file
/// while the provider is halfway through replacing it gives torn text; writing
/// one while it is being downloaded throws the download away. `NSFileCoordinator`
/// is how the two sides take turns.
///
/// Every call here blocks until the other side yields, so nothing in this file
/// may be handed a file that isn't on the device yet: coordinating a read of an
/// evicted iCloud file waits for the whole download. Check ``isDownloaded(_:)``
/// first — that check is a cheap local lookup.
enum CoordinatedFile {
    /// Reads a file, after anyone else editing it has been asked to save.
    static func read(_ url: URL) throws -> String {
        var text: String?
        var failure: Error?
        var coordinationError: NSError?

        NSFileCoordinator().coordinate(
            readingItemAt: url, options: [], error: &coordinationError
        ) { actual in
            do {
                text = try String(contentsOf: actual, encoding: .utf8)
            } catch {
                failure = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let failure { throw failure }
        guard let text else { throw CocoaError(.fileReadUnknown) }
        return text
    }

    /// Writes a file atomically, holding off the file provider while it happens.
    ///
    /// `.forReplacing` because an atomic write swaps a new file into place
    /// rather than editing the old one — the coordinator has to know the
    /// identity of the item is about to change.
    static func write(_ text: String, to url: URL) throws {
        var failure: Error?
        var coordinationError: NSError?

        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError
        ) { actual in
            do {
                try text.write(to: actual, atomically: true, encoding: .utf8)
            } catch {
                failure = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let failure { throw failure }
    }

    /// Moves a file or folder. Both ends are coordinated: the provider has to
    /// stop writing the source and stop populating the destination.
    static func move(_ source: URL, to destination: URL) throws {
        var failure: Error?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(
            writingItemAt: source, options: .forMoving,
            writingItemAt: destination, options: .forReplacing,
            error: &coordinationError
        ) { from, to in
            do {
                try FileManager.default.moveItem(at: from, to: to)
                // Tells the coordinator the item kept its identity, so any
                // presenter following it goes with it instead of thinking it
                // was deleted and a stranger appeared.
                coordinator.item(at: source, didMoveTo: destination)
            } catch {
                failure = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let failure { throw failure }
    }

    /// Moves a file or folder to the Trash — recoverable, unlike unlinking it.
    static func trash(_ url: URL) throws {
        var failure: Error?
        var coordinationError: NSError?

        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forDeleting, error: &coordinationError
        ) { actual in
            do {
                try FileManager.default.trashItem(at: actual, resultingItemURL: nil)
            } catch {
                failure = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let failure { throw failure }
    }

    /// What the filesystem knows about a note file, in one lookup.
    struct State {
        var modified: Date
        /// Whether the contents are actually on this device. A file with no
        /// iCloud status isn't in iCloud, and is therefore here.
        var isDownloaded: Bool
        var hasConflicts: Bool
    }

    /// A cheap, purely local question — unlike reading the file, which for an
    /// evicted iCloud file means waiting for the network.
    static func state(of url: URL) -> State {
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemHasUnresolvedConflictsKey,
        ])

        return State(
            modified: values?.contentModificationDate ?? .distantPast,
            isDownloaded: values?.ubiquitousItemDownloadingStatus != .notDownloaded,
            hasConflicts: values?.ubiquitousItemHasUnresolvedConflicts ?? false
        )
    }

    /// Asks iCloud for a file's contents. Returns immediately; the file arrives
    /// when it arrives, or not at all if there is no connection.
    static func startDownload(_ url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// Creates a directory. Coordinated for the same reason a write is: the
    /// provider may be about to create something by that very name.
    static func createDirectory(at url: URL) throws {
        var failure: Error?
        var coordinationError: NSError?

        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError
        ) { actual in
            do {
                try FileManager.default.createDirectory(
                    at: actual, withIntermediateDirectories: true
                )
            } catch {
                failure = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let failure { throw failure }
    }
}
