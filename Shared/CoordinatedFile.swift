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
    /// Reads every one of `urls` under a single claim, instead of one each.
    ///
    /// Taking a claim costs about 1.7ms. That is nothing for one note and most
    /// of the launch budget for a folder of two hundred — 350ms measured. One
    /// claim over the whole batch costs a sixth of that, and the reads inside
    /// it are then nearly free. The saving only arrives if the reads go through
    /// the *same* coordinator, which is what `batch` is for.
    ///
    /// For reads only, and for the folder scan in particular. A write inside
    /// this would be a write inside a read claim.
    static func batchReading(_ urls: [URL], _ work: () -> Void) {
        guard !urls.isEmpty else { return work() }

        let coordinator = NSFileCoordinator()
        var error: NSError?
        var ran = false

        coordinator.prepare(
            forReadingItemsAt: urls, options: [],
            writingItemsAt: [], options: [],
            error: &error
        ) { done in
            ran = true
            batch = coordinator
            work()
            batch = nil
            done()
        }

        // A claim that couldn't be taken is a slower read, not a failed one.
        if !ran { work() }
    }

    /// The claim currently in progress, if any. Written only by `batchReading`,
    /// on the main thread, for the length of one folder scan — everything in
    /// this app that touches files does so from the main thread.
    private static var batch: NSFileCoordinator?

    /// Reads a file, after anyone else editing it has been asked to save.
    static func read(_ url: URL) throws -> String {
        var text: String?
        var failure: Error?
        var coordinationError: NSError?

        (batch ?? NSFileCoordinator()).coordinate(
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

    /// Turns the losing side of an iCloud clash into a note of its own.
    ///
    /// Two devices editing the same note while one of them was offline leaves
    /// iCloud holding both versions and showing one. The other is something the
    /// user actually wrote and can no longer see anywhere — so each one is
    /// written out beside the original as a normal `.md` file, and the conflict
    /// marked resolved. Nothing is merged and nothing is chosen: both are notes.
    ///
    /// Returns the files it created, so the caller can list them.
    static func resolveConflicts(at url: URL) -> [URL] {
        guard state(of: url).hasConflicts,
              let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url)
        else { return [] }

        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        var created: [URL] = []

        for version in versions {
            let stamp = conflictStamp.string(from: version.modificationDate ?? .now)
            var target = directory.appending(path: "\(base)-conflict-\(stamp).md")
            var suffix = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = directory.appending(path: "\(base)-conflict-\(stamp)-\(suffix).md")
                suffix += 1
            }

            var wrote = false
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(
                writingItemAt: target, options: .forReplacing, error: &coordinationError
            ) { actual in
                wrote = (try? version.replaceItem(at: actual)) != nil
            }

            // Only ever resolved once the other side is safely on disk under a
            // name of its own. A failure here leaves the conflict standing, to
            // be tried again on the next sync.
            guard coordinationError == nil, wrote else { continue }
            version.isResolved = true
            created.append(target)
        }

        return created
    }

    /// Fixed and sortable, and the same on every machine — this ends up in a
    /// filename, not on screen.
    private static let conflictStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()

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
