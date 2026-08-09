import XCTest

/// Title, preview and filename are all derived from the text and never stored,
/// so these rules decide what the sidebar shows and what the file is called.
final class NoteTests: XCTestCase {

    private func note(_ text: String) -> Note {
        Note(fileURL: nil, text: text)
    }

    // MARK: - Titles

    func testTitleComesFromTheFirstHeading() {
        XCTAssertEqual(note("# Title\nbody").summary.title, "Title")
    }

    func testAHeadingWinsEvenWhenItIsNotTheFirstLine() {
        XCTAssertEqual(note("intro line\n# Real Title").summary.title, "Real Title")
    }

    func testFallsBackToTheFirstNonEmptyLine() {
        XCTAssertEqual(note("\n\n  first words  \nmore").summary.title, "first words")
    }

    func testEmptyNoteIsUntitled() {
        XCTAssertEqual(note("").summary.title, "Untitled")
        XCTAssertEqual(note("\n\n   \n").summary.title, "Untitled")
    }

    // MARK: - Previews

    func testPreviewIsTheFirstLineThatIsNotTheTitle() {
        XCTAssertEqual(note("# Title\nthe body").summary.preview, "the body")
    }

    func testPreviewStripsHeadingMarkers() {
        XCTAssertEqual(note("# Title\n## Subhead").summary.preview, "Subhead")
    }

    func testPreviewIsEmptyForASingleLineNote() {
        XCTAssertEqual(note("# Only a title").summary.preview, "")
    }

    func testPreviewSkipsTheTitleLineWhenTheTitleCameFromLaterInTheNote() {
        let summary = note("intro line\n# Real Title").summary
        XCTAssertEqual(summary.title, "Real Title")
        XCTAssertEqual(summary.preview, "intro line")
    }

    // MARK: - Slugs

    func testSlugIsLowercasedAndHyphenated() {
        XCTAssertEqual(Note.slug(for: "Hello, World!"), "hello-world")
    }

    func testSlugCollapsesRunsAndTrimsEdges() {
        XCTAssertEqual(Note.slug(for: "  ...spaced   out!!  "), "spaced-out")
    }

    func testSlugKeepsAccentedLetters() {
        XCTAssertEqual(Note.slug(for: "Città di Milano"), "città-di-milano")
    }

    func testSlugFallsBackWhenNothingSurvives() {
        XCTAssertEqual(Note.slug(for: "!!!"), "untitled")
        XCTAssertEqual(Note.slug(for: ""), "untitled")
    }

    func testSlugIsBoundedInLength() {
        let slug = Note.slug(for: String(repeating: "word ", count: 60))
        XCTAssertLessThanOrEqual(slug.count, 60)
        XCTAssertFalse(slug.hasSuffix("-"), "a truncated slug must not end on a hyphen")
    }

    func testNoteSlugFollowsTheDerivedTitle() {
        XCTAssertEqual(note("# Shopping List\nmilk").slug, "shopping-list")
    }
}
