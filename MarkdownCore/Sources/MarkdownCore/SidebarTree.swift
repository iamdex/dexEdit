import Foundation

/// One row of the folder view: a folder that can be opened, or a note.
public struct SidebarNode: Identifiable, Equatable {
    public enum Kind: Equatable {
        case folder(URL)
        case note(UUID)
    }

    public let id: String
    public let kind: Kind
    public let name: String
    public let children: [SidebarNode]

    public var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }
}

/// Builds the folder view's tree.
///
/// Folders come from the filesystem rather than from the notes' paths, so a
/// folder you just made shows up while it is still empty. Folders sort by name;
/// notes inside a folder stay newest-first, so structure guides you to the
/// place and recency guides you within it.
public enum SidebarTree {

    /// - Parameter directoryOf: where a note lives. A note that has never been
    ///   written has no file yet, and the caller knows where it is destined.
    public static func build(
        root: URL,
        folders: [URL],
        notes: [Note],
        directoryOf: (Note) -> URL
    ) -> [SidebarNode] {
        var foldersByParent: [String: [URL]] = [:]
        for folder in folders {
            let standardized = folder.standardizedFileURL
            foldersByParent[standardized.deletingLastPathComponent().path, default: []]
                .append(standardized)
        }

        var notesByDirectory: [String: [Note]] = [:]
        for note in notes {
            notesByDirectory[directoryOf(note).standardizedFileURL.path, default: []].append(note)
        }

        return children(
            of: root.standardizedFileURL.path,
            foldersByParent: foldersByParent,
            notesByDirectory: notesByDirectory
        )
    }

    private static func children(
        of path: String,
        foldersByParent: [String: [URL]],
        notesByDirectory: [String: [Note]]
    ) -> [SidebarNode] {
        let folders = (foldersByParent[path] ?? []).sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        var nodes = folders.map { url in
            SidebarNode(
                id: "folder:" + url.path,
                kind: .folder(url),
                name: url.lastPathComponent,
                children: children(
                    of: url.path,
                    foldersByParent: foldersByParent,
                    notesByDirectory: notesByDirectory
                )
            )
        }

        let notes = (notesByDirectory[path] ?? []).sorted { $0.modified > $1.modified }
        nodes.append(contentsOf: notes.map { note in
            SidebarNode(
                id: "note:" + note.id.uuidString,
                kind: .note(note.id),
                name: note.summary.title,
                children: []
            )
        })

        return nodes
    }
}
