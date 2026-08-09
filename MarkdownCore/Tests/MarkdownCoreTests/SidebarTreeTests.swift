import MarkdownCore
import XCTest

final class SidebarTreeTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/vault", isDirectory: true)

    private func note(_ title: String, at path: String, modified: Date = .now) -> Note {
        Note(fileURL: root.appending(path: path), text: "# \(title)", modified: modified)
    }

    private func build(folders: [String], notes: [Note]) -> [SidebarNode] {
        SidebarTree.build(
            root: root,
            folders: folders.map { root.appending(path: $0) },
            notes: notes,
            directoryOf: { $0.fileURL?.deletingLastPathComponent() ?? root }
        )
    }

    func testEmptyFolderStillAppears() {
        let tree = build(folders: ["Empty"], notes: [])

        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree.first?.name, "Empty")
        XCTAssertTrue(tree.first?.isFolder == true)
        XCTAssertEqual(tree.first?.children, [])
    }

    func testNotesNestUnderTheirFolder() {
        let tree = build(
            folders: ["Work"],
            notes: [note("Top", at: "top.md"), note("Nested", at: "Work/nested.md")]
        )

        XCTAssertEqual(tree.map(\.name), ["Work", "Top"], "folders come before loose notes")
        XCTAssertEqual(tree.first?.children.map(\.name), ["Nested"])
    }

    func testNestingGoesAsDeepAsTheVault() {
        let tree = build(
            folders: ["Work", "Work/Clients", "Work/Clients/Acme"],
            notes: [note("Brief", at: "Work/Clients/Acme/brief.md")]
        )

        let work = try? XCTUnwrap(tree.first)
        let clients = try? XCTUnwrap(work?.children.first)
        let acme = try? XCTUnwrap(clients?.children.first)

        XCTAssertEqual(work?.name, "Work")
        XCTAssertEqual(clients?.name, "Clients")
        XCTAssertEqual(acme?.name, "Acme")
        XCTAssertEqual(acme?.children.map(\.name), ["Brief"])
    }

    func testFoldersSortByNameAndNotesByDateWithinAFolder() {
        let older = note("Older", at: "older.md", modified: Date(timeIntervalSince1970: 1))
        let newer = note("Newer", at: "newer.md", modified: Date(timeIntervalSince1970: 2))

        let tree = build(folders: ["Zebra", "Apple"], notes: [older, newer])

        XCTAssertEqual(tree.map(\.name), ["Apple", "Zebra", "Newer", "Older"])
    }

    func testAnUnsavedNoteIsPlacedWhereItIsDestined() {
        let unsaved = Note(fileURL: nil, text: "# Draft")
        let tree = SidebarTree.build(
            root: root,
            folders: [root.appending(path: "Work")],
            notes: [unsaved],
            directoryOf: { _ in self.root.appending(path: "Work") }
        )

        XCTAssertEqual(tree.first?.children.map(\.name), ["Draft"])
    }

    func testFoldersOutsideTheRootAreIgnored() {
        let tree = SidebarTree.build(
            root: root,
            folders: [URL(fileURLWithPath: "/elsewhere/Stray")],
            notes: [],
            directoryOf: { $0.fileURL?.deletingLastPathComponent() ?? self.root }
        )

        XCTAssertEqual(tree, [])
    }
}
