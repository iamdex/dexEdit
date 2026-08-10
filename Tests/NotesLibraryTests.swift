import MarkdownCore
import XCTest

/// The file side of the app: loading a folder, autosaving, renaming a file to
/// follow its title, deleting, and picking up changes made by other tools.
///
/// Fixtures live in a unique subfolder of the scratch notes directory and are
/// removed afterwards, so nothing here can touch real notes.
final class NotesLibraryTests: XCTestCase {

    /// A throwaway directory per run. Not a real notes folder: these tests
    /// create and delete files, and must run on any machine.
    private static let scratchRoot = FileManager.default.temporaryDirectory
        .appending(path: "dexedit-tests", directoryHint: .isDirectory)

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

    // MARK: - Renaming, moving and deleting folders

    func testRenamingAFolderCarriesItsNotesWithIt() throws {
        let work = try makeSubfolder("Work")
        try "# Inside".write(to: work.appending(path: "inside.md"), atomically: true, encoding: .utf8)
        library.setFolder(folder)
        let id = try XCTUnwrap(library.notes.first?.id)

        library.renameFolder(work, to: "Business")

        XCTAssertEqual(library.folderLabel(for: try XCTUnwrap(library.note(id))), "Business")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: folder.appending(path: "Business/inside.md").path)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path))
    }

    func testRenamingAFolderUpdatesDeeplyNestedNotesToo() throws {
        let deep = try makeSubfolder("Work/Clients/Acme")
        try "# Brief".write(to: deep.appending(path: "brief.md"), atomically: true, encoding: .utf8)
        library.setFolder(folder)
        let id = try XCTUnwrap(library.notes.first?.id)

        library.renameFolder(folder.appending(path: "Work"), to: "Business")

        XCTAssertEqual(
            library.folderLabel(for: try XCTUnwrap(library.note(id))), "Business/Clients/Acme"
        )
    }

    func testRenamingOntoAnExistingNameIsRefused() throws {
        let work = try makeSubfolder("Work")
        _ = try makeSubfolder("Archive")
        library.setFolder(folder)

        let result = library.renameFolder(work, to: "Archive")

        XCTAssertNil(result, "merging two folders silently would be the wrong answer")
        XCTAssertTrue(FileManager.default.fileExists(atPath: work.path))
    }

    func testMovingAFolderIntoAnotherOne() throws {
        let work = try makeSubfolder("Work")
        let archive = try makeSubfolder("Archive")
        try "# Inside".write(to: work.appending(path: "inside.md"), atomically: true, encoding: .utf8)
        library.setFolder(folder)
        let id = try XCTUnwrap(library.notes.first?.id)

        library.moveFolder(work, into: archive)

        XCTAssertEqual(library.folderLabel(for: try XCTUnwrap(library.note(id))), "Archive/Work")
    }

    func testAFolderCannotBeMovedInsideItself() throws {
        let work = try makeSubfolder("Work")
        let clients = try makeSubfolder("Work/Clients")
        library.setFolder(folder)

        XCTAssertNil(library.moveFolder(work, into: clients), "that would delete the tree")
        XCTAssertTrue(FileManager.default.fileExists(atPath: clients.path))
    }

    func testTheNotesFolderItselfCannotBeMoved() throws {
        let archive = try makeSubfolder("Archive")
        library.setFolder(folder)

        XCTAssertNil(library.moveFolder(folder, into: archive))
    }

    func testDeletingAFolderTakesItsNotesWithIt() throws {
        let work = try makeSubfolder("Work/Clients")
        try "# Doomed".write(to: work.appending(path: "doomed.md"), atomically: true, encoding: .utf8)
        try write("# Survivor", to: "survivor.md")
        library.setFolder(folder)

        library.deleteFolder(folder.appending(path: "Work"))

        XCTAssertEqual(library.notes.map(\.summary.title), ["Survivor"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: "Work").path))
        XCTAssertNotNil(library.selection, "selection moves to what's left")
    }

    func testNoteCountReportsWhatADeleteWouldTake() throws {
        let deep = try makeSubfolder("Work/Clients")
        try "# One".write(to: deep.appending(path: "one.md"), atomically: true, encoding: .utf8)
        try "# Two".write(
            to: folder.appending(path: "Work/two.md"), atomically: true, encoding: .utf8
        )
        try write("# Outside", to: "outside.md")
        library.setFolder(folder)

        XCTAssertEqual(library.noteCount(in: folder.appending(path: "Work")), 2)
    }

    func testRenamingCommitsPendingEditsFirst() throws {
        let work = try makeSubfolder("Work")
        try "# Inside\nbody".write(
            to: work.appending(path: "inside.md"), atomically: true, encoding: .utf8
        )
        library.setFolder(folder)
        let id = try XCTUnwrap(library.notes.first?.id)

        library.updateText("# Inside\nedited", for: id)
        library.renameFolder(work, to: "Business")

        XCTAssertEqual(
            try String(
                contentsOf: folder.appending(path: "Business/inside.md"), encoding: .utf8
            ),
            "# Inside\nedited"
        )
    }

    // MARK: - External changes

    func testSyncPicksUpAFileCreatedElsewhere() throws {
        try write("# First", to: "first.md")
        library.setFolder(folder)

        try write("# Added Outside", to: "added.md")
        library.syncWithDisk()

        XCTAssertTrue(library.notes.contains { $0.summary.title == "Added Outside" })
    }

    /// Every window becoming key asks for a sync, and the first ask lands right
    /// after the launch read. The throttle drops those without touching an
    /// explicit sync.
    func testSyncIfStaleSkipsAnAskThatFollowsAReadImmediately() throws {
        try write("# First", to: "first.md")
        library.setFolder(folder)

        try write("# Added Outside", to: "added.md")
        library.syncIfStale()

        XCTAssertEqual(library.notes.count, 1, "the redundant ask was dropped")

        library.syncWithDisk()
        XCTAssertEqual(library.notes.count, 2, "an explicit sync still reads the folder")
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

    // MARK: - Folders

    private func makeSubfolder(_ name: String) throws -> URL {
        let url = folder.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testNotesInSubfoldersAreLoaded() throws {
        try write("# Top", to: "top.md")
        let projects = try makeSubfolder("Projects")
        try "# Nested".write(to: projects.appending(path: "nested.md"), atomically: true, encoding: .utf8)

        library.setFolder(folder)

        XCTAssertEqual(Set(library.notes.map(\.summary.title)), ["Top", "Nested"])
    }

    func testFolderLabelIsOnlySetForNotesBelowTheTopLevel() throws {
        try write("# Top", to: "top.md")
        let projects = try makeSubfolder("Projects")
        try "# Nested".write(to: projects.appending(path: "nested.md"), atomically: true, encoding: .utf8)
        library.setFolder(folder)

        let top = try XCTUnwrap(library.notes.first { $0.summary.title == "Top" })
        let nested = try XCTUnwrap(library.notes.first { $0.summary.title == "Nested" })

        XCTAssertNil(library.folderLabel(for: top))
        XCTAssertEqual(library.folderLabel(for: nested), "Projects")
    }

    func testNestedFolderLabelReadsAsAPath() throws {
        let deep = try makeSubfolder("Work/Clients")
        try "# Deep".write(to: deep.appending(path: "deep.md"), atomically: true, encoding: .utf8)
        library.setFolder(folder)

        let note = try XCTUnwrap(library.notes.first)
        XCTAssertEqual(library.folderLabel(for: note), "Work/Clients")
    }

    func testMovingANoteRelocatesTheFileAndKeepsTheNote() throws {
        try write("# Movable\nbody", to: "movable.md")
        let archive = try makeSubfolder("Archive")
        library.setFolder(folder)
        let id = try XCTUnwrap(library.selection)

        library.move(id, to: archive)

        XCTAssertEqual(filenames, [], "nothing left at the top level")
        XCTAssertEqual(
            try String(contentsOf: archive.appending(path: "movable.md"), encoding: .utf8),
            "# Movable\nbody"
        )
        XCTAssertEqual(library.selection, id, "the note itself is untouched")
        XCTAssertEqual(library.folderLabel(for: try XCTUnwrap(library.note(id))), "Archive")
    }

    func testMovingCommitsAPendingEditFirst() throws {
        try write("# Movable\nbody", to: "movable.md")
        let archive = try makeSubfolder("Archive")
        library.setFolder(folder)
        let id = try XCTUnwrap(library.selection)

        library.updateText("# Movable\nedited", for: id)
        library.move(id, to: archive)

        XCTAssertEqual(
            try String(contentsOf: archive.appending(path: "movable.md"), encoding: .utf8),
            "# Movable\nedited"
        )
    }

    func testMovingIntoAFolderThatAlreadyHasThatFilenameGetsASuffix() throws {
        try write("# Notes", to: "notes.md")
        let archive = try makeSubfolder("Archive")
        try "# Older notes".write(
            to: archive.appending(path: "notes.md"), atomically: true, encoding: .utf8
        )
        library.setFolder(folder)
        let id = try XCTUnwrap(library.notes.first { $0.summary.title == "Notes" }?.id)

        library.move(id, to: archive)

        XCTAssertEqual(
            library.note(id)?.fileURL?.lastPathComponent, "notes-2.md",
            "the existing file in the target folder is not overwritten"
        )
    }

    func testRenamingKeepsANoteInItsOwnFolder() throws {
        let archive = try makeSubfolder("Archive")
        try "# Old\nbody".write(
            to: archive.appending(path: "old.md"), atomically: true, encoding: .utf8
        )
        library.setFolder(folder)
        let id = try XCTUnwrap(library.selection)

        library.updateText("# Renamed\nbody", for: id)
        library.flushPending()

        XCTAssertEqual(library.folderLabel(for: try XCTUnwrap(library.note(id))), "Archive")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: archive.appending(path: "renamed.md").path)
        )
        XCTAssertEqual(filenames, [], "the rename did not escape to the top level")
    }

    func testNewNotesAreBornAtTheTopLevel() throws {
        _ = try makeSubfolder("Archive")
        library.setFolder(folder)
        library.newNote()
        let id = try XCTUnwrap(library.selection)

        library.updateText("# Fresh", for: id)
        library.flushPending()

        XCTAssertNil(library.folderLabel(for: try XCTUnwrap(library.note(id))))
    }

    func testANewNoteLandsBesideTheSelectedOne() throws {
        let work = try makeSubfolder("Work")
        try "# Existing".write(
            to: work.appending(path: "existing.md"), atomically: true, encoding: .utf8
        )
        library.setFolder(folder)

        library.newNote()
        let id = try XCTUnwrap(library.selection)
        library.updateText("# Fresh", for: id)
        library.flushPending()

        XCTAssertEqual(
            library.folderLabel(for: try XCTUnwrap(library.note(id))), "Work",
            "it follows the note you were reading"
        )
    }

    func testANewNoteCanBeAimedAtAFolderExplicitly() throws {
        let archive = try makeSubfolder("Archive")
        try write("# Top", to: "top.md")
        library.setFolder(folder)

        library.newNote(in: archive)
        let id = try XCTUnwrap(library.selection)
        library.updateText("# Filed", for: id)
        library.flushPending()

        XCTAssertEqual(library.folderLabel(for: try XCTUnwrap(library.note(id))), "Archive")
    }

    func testEmptyFoldersAreKnownToTheLibrary() throws {
        let empty = try makeSubfolder("Empty")
        library.setFolder(folder)

        XCTAssertTrue(library.folders.map(\.path).contains(empty.path))
    }

    func testACreatedFolderAppearsImmediately() throws {
        library.setFolder(folder)

        let created = try XCTUnwrap(library.createFolder(named: "Fresh"))

        XCTAssertTrue(
            library.folders.map(\.path).contains(created.path),
            "the folder view must show it before anything is moved into it"
        )
    }

    func testFoldersCanBeCreatedInsideAnotherFolder() throws {
        let work = try makeSubfolder("Work")
        library.setFolder(folder)

        let nested = try XCTUnwrap(library.createFolder(named: "Clients", in: work))

        XCTAssertEqual(nested.deletingLastPathComponent().path, work.path)
    }

    func testTheTreeShowsAnUnsavedNoteWhereItIsDestined() throws {
        let work = try makeSubfolder("Work")
        library.setFolder(folder)

        library.newNote(in: work)

        let workNode = try XCTUnwrap(library.sidebarTree.first { $0.name == "Work" })
        XCTAssertEqual(workNode.children.count, 1, "a note with no file yet still has a home")
    }

    func testCreateFolderRejectsPathSeparators() throws {
        library.setFolder(folder)

        let created = try XCTUnwrap(library.createFolder(named: "Work/Secret"))

        XCTAssertEqual(created.lastPathComponent, "Work-Secret", "a name is one folder, not a path")
        // Compared as paths: deletingLastPathComponent leaves a trailing slash.
        XCTAssertEqual(created.deletingLastPathComponent().path, folder.path)
    }

    func testCreateFolderRefusesEmptyAndHiddenNames() {
        library.setFolder(folder)

        XCTAssertNil(library.createFolder(named: "   "))
        XCTAssertNil(library.createFolder(named: ".hidden"))
    }

    func testSyncFollowsANoteMovedBetweenFoldersOutsideTheApp() throws {
        try write("# Wanderer\nbody", to: "wanderer.md")
        let archive = try makeSubfolder("Archive")
        library.setFolder(folder)
        let id = try XCTUnwrap(library.selection)

        try FileManager.default.moveItem(
            at: folder.appending(path: "wanderer.md"),
            to: archive.appending(path: "wanderer.md")
        )
        library.syncWithDisk()

        XCTAssertEqual(library.notes.count, 1, "not treated as a delete plus an add")
        XCTAssertEqual(library.selection, id, "the selection survives the move")
        XCTAssertEqual(library.folderLabel(for: try XCTUnwrap(library.note(id))), "Archive")
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
