import Foundation

/// The hand-off between the share extension and the app.
///
/// The extension cannot reach your notes folder. That access belongs to the
/// app — it came from a folder you picked yourself — and lending it out to an
/// extension is the part of this whole idea that isn't guaranteed to work.
/// So the extension never tries: it writes what you shared into a container
/// both sides can see, and the app, which does have the folder, turns it into a
/// real note the next time it runs.
///
/// This is not a second place your notes live. Nothing written here is ever
/// read back once it has become a note, and an item that has been adopted is
/// deleted on the spot. If the app never runs again, what is in here is one
/// plain markdown file, readable by anything.
enum SharedInbox {
    static let groupID = "group.com.espertini.dexEdit"

    private static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appending(path: "Inbox", directoryHint: .isDirectory)
    }

    /// The extension's half. Throws rather than failing quietly, because the
    /// one thing worse than not capturing a thought is telling someone you did.
    static func write(_ text: String) throws {
        guard let directory else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        // Milliseconds, zero-padded: these want to come out in the order they
        // went in, and the order is a plain sort of the names.
        let stamp = String(format: "%015.0f", Date().timeIntervalSince1970 * 1000)
        let url = directory.appending(path: "\(stamp)-\(UUID().uuidString).md")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The app's half: everything waiting, oldest first.
    static func waiting() -> [URL] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: nil
              )
        else { return [] }

        return files
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Reads one and removes it. Only ever called once the text is safely a
    /// note, so nothing is dropped between the two.
    static func take(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return text
    }
}
