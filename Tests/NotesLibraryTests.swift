import XCTest

/// The file side of the app: loading a folder, autosaving, renaming a file to
/// follow its title, deleting, and picking up changes made by other tools.
///
/// Fixtures live in a unique subfolder of the scratch notes directory and are
/// removed afterwards, so nothing here can touch real notes.
final class NotesLibraryTests: XCTestCase {

    private static let scratchRoot = URL(
        fileURLWithPath: "/Users/iamdex/Documents/test_md/.dexedit-tests",
        isDirectory: true
    )

    private var folder: URL!
    private var library: NotesLibrary!

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = Self.scratchRoot.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        library = NotesLibrary()
    }

    override func tearDownWithError() throws {
        library = nil
        try? FileManager.default.removeItem(at: folder)
        // Leaves the root behind only if other runs are using it.
        try? FileManager.default.removeItem(at: Self.scratchRoot)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func write(_ text: String, to name: String) throws {
        try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
    }

    private func read(_ name: String) throws -> String {
        try String(contentsOf: folder.appending(path: name), encoding: .utf8)
    }

    private var filenames: [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return contents.filter { $0.hasSuffix(".md") }.sorted()
    }

    // MARK: - Loading

    func testLoadsMarkdownFilesAndIgnoresEverythingElse() throws {
        try write("# One\nbody", to: "one.md")
        try write("# Two\nbody", to: "two.md")
        try write("not a note", to: "notes.txt")

        library.setFolder(folder)

        XCTAssertEqual(library.notes.count, 2)
        XCTAssertEqual(Set(library.notes.map(\.summary.title)), ["One", "Two"])
    }

    func testSortsNewestFirst() throws {
        try write("# Older", to: "older.md")
        let older = folder.appending(path: "older.md")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: older.path
        )
        try write("# Newer", to: "newer.md")

        library.setFolder(folder)

        XCTAssertEqual(library.notes.first?.summary.title, "Newer")
    }

    func testSelectsTheFirstNoteOnOpen() throws {
        try write("# One", to: "one.md")
        library.setFolder(folder)

        XCTAssertEqual(library.selection, library.notes.first?.id)
    }

    // MARK: - Saving

    func testEditsAreWrittenWhenFlushed() throws {
        try write("# Title\nbody", to: "title.md")
        library.setFolder(folder)
        let id = try XCTUnwrap(library.selection)

        library.updateText("# Title\nchanged", for: id)
        library.flushPending()

        XCTAssertEqual(try read("title.md"), "# Title\nchanged")
    }

    /// No explicit flush: this is the 500ms debounce doing its job.
    func testEditsAreWrittenAfterTheDebounceWithNoFlush() throws {
        try write("# Title\nbody", to: "title.md")
        library.setFolder(folder)
        let id = try XCTUnwrap(library.selection)

        library.updateText("# Title\ndebounced", for: id)
        XCTAssertEqual(try read("title.md"), "# Title\nbody", "not written yet")

        let written = expectation(description: "autosave")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { written.fulfill() }
        wait(for: [written], timeout: 3)

        XCTAssertEqual(try read("title.md"), "# Title\ndebounced")
    }

    func testAnEmptyNewNoteNeverReachesTheFolder() {
        library.setFolder(folder)
        library.newNote()
        library.flushPending()

        XCTAssertEqual(filenames, [], "an abandoned Cmd+N leaves nothing behind")
        XCTAssertEqual(library.notes.count, 1, "but it is still in the list")
    }

    func testANewNoteIsFiledUnderItsDerivedTitle() throws {
        library.setFolder(folder)
        library.newNote()
        let id = try XCTUnwrap(library.selection)

        library.updateText("# Shopping List\nmilk", for: id)
        library.flushPending()

        XCTAssertEqual(filenames, ["shopping-list.md"])
    }

    func testDuplicateTitlesGetANumberedFilename() throws {
        try write("# Notes", to: "notes.md")
        library.setFolder(folder)
        library.newNote()
        let id = try XCTUnwrap(library.selection)

        library.updateText("# Notes\nsecond one", for: id)
        library.flushPending()

        XCTAssertEqual(filenames, ["notes-2.md", "notes.md"])
    }

    // MARK: - Renaming

    func testRenamingTheTitleRenamesTheFileAndLeavesNoOrphan() throws {
        try write("# Old Title\nbody", to: "old-title.md")
        library.setFolder(folder)
        let id = try XCTUnwrap(library.selection)

        library.updateText("# New Title\nbody", for: id)
        library.flushPending()

        XCTAssertEqual(filenames, ["new-title.md"])
        XCTAssertEqual(try read("new-title.md"), "# New Title\nbody")
    }

    func testRenameCarriesTheLatestTextWithIt() throws {
        try write("# Old\nbody", to: "old.md")
        library.setFolder(folder)
        let id = try XCTUnwrap(library.selection)

        library.updateText("# Renamed\nedited body", for: id)
        library.flushPending()

        XCTAssertEqual(try read("renamed.md"), "# Renamed\nedited body")
    }

    // MARK: - Deleting

    func testDeletingRemovesTheNoteAndItsFile() throws {
        try write("# Doomed", to: "doomed.md")
        try write("# Survivor", to: "survivor.md")
        library.setFolder(folder)
        let doomed = try XCTUnwrap(library.notes.first { $0.summary.title == "Doomed" })

        library.delete(doomed.id)

        XCTAssertEqual(filenames, ["survivor.md"])
        XCTAssertEqual(library.notes.map(\.summary.title), ["Survivor"])
        XCTAssertNotNil(library.selection, "selection moves to what's left")
    }

    // MARK: - External changes

    func testSyncPicksUpAFileCreatedElsewhere() throws {
        try write("# First", to: "first.md")
        library.setFolder(folder)

        try write("# Added Outside", to: "added.md")
        library.syncWithDisk()

        XCTAssertTrue(library.notes.contains { $0.summary.title == "Added Outside" })
    }

    func testSyncReloadsAFileChangedElsewhere() throws {
        try write("# Title\nbefore", to: "title.md")
        library.setFolder(folder)
        let id = try XCTUnwrap(library.selection)

        try write("# Title\nafter", to: "title.md")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 5)],
            ofItemAtPath: folder.appending(path: "title.md").path
        )
        library.syncWithDisk()

        XCTAssertEqual(library.text(for: id), "# Title\nafter")
    }

    func testSyncDropsAFileDeletedElsewhere() throws {
        try write("# Gone", to: "gone.md")
        try write("# Stays", to: "stays.md")
        library.setFolder(folder)

        try FileManager.default.removeItem(at: folder.appending(path: "gone.md"))
        library.syncWithDisk()

        XCTAssertEqual(library.notes.map(\.summary.title), ["Stays"])
    }

    func testSyncCommitsLocalEditsBeforeReadingDisk() throws {
        try write("# Title\nbody", to: "title.md")
        library.setFolder(folder)
        let id = try XCTUnwrap(library.selection)

        // An edit is pending when the window regains focus.
        library.updateText("# Title\nlocal edit", for: id)
        library.syncWithDisk()

        XCTAssertEqual(
            try read("title.md"), "# Title\nlocal edit",
            "the pending edit is written, not discarded by the reload"
        )
    }

    // MARK: - Search

    func testSearchMatchesTitleAndBody() throws {
        try write("# Groceries\nmilk and coffee", to: "groceries.md")
        try write("# Recipes\nbread", to: "recipes.md")
        library.setFolder(folder)

        library.searchText = "coffee"
        XCTAssertEqual(library.filteredNotes.map(\.summary.title), ["Groceries"])

        library.searchText = "RECIPES"
        XCTAssertEqual(library.filteredNotes.map(\.summary.title), ["Recipes"], "case-insensitive")

        library.searchText = ""
        XCTAssertEqual(library.filteredNotes.count, 2)
    }
}
