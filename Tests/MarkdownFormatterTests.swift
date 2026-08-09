import XCTest

/// The formatting shortcuts. These are the functions behind Cmd+B, Cmd+I,
/// Cmd+K and the toolbar, and they are pure, so they are tested directly.
final class MarkdownFormatterTests: XCTestCase {

    // MARK: - Wrapping

    func testWrapsSelectionAndKeepsItSelected() {
        let text = "hello world" as NSString
        let edit = MarkdownFormatter.toggleWrap(
            in: text, selection: NSRange(location: 0, length: 5), marker: "**"
        )

        XCTAssertEqual(edit.replacement, "**hello**")
        XCTAssertEqual(edit.range, NSRange(location: 0, length: 5))
        // The selection lands on the text, not on the markers.
        XCTAssertEqual(edit.selection, NSRange(location: 2, length: 5))
    }

    func testUnwrapsWhenMarkersAreInsideTheSelection() {
        let text = "**hello** world" as NSString
        let edit = MarkdownFormatter.toggleWrap(
            in: text, selection: NSRange(location: 0, length: 9), marker: "**"
        )

        XCTAssertEqual(edit.replacement, "hello")
        XCTAssertEqual(edit.range, NSRange(location: 0, length: 9))
        XCTAssertEqual(edit.selection, NSRange(location: 0, length: 5))
    }

    func testUnwrapsWhenMarkersSitJustOutsideTheSelection() {
        let text = "**hello** world" as NSString
        let edit = MarkdownFormatter.toggleWrap(
            in: text, selection: NSRange(location: 2, length: 5), marker: "**"
        )

        XCTAssertEqual(edit.replacement, "hello")
        XCTAssertEqual(edit.range, NSRange(location: 0, length: 9))
        XCTAssertEqual(edit.selection, NSRange(location: 0, length: 5))
    }

    func testEmptySelectionInsertsAPairWithTheCursorBetween() {
        let text = "" as NSString
        let edit = MarkdownFormatter.toggleWrap(
            in: text, selection: NSRange(location: 0, length: 0), marker: "**"
        )

        XCTAssertEqual(edit.replacement, "****")
        XCTAssertEqual(edit.selection, NSRange(location: 2, length: 0))
    }

    /// The guard that stops Cmd+I from turning bold into italic by stealing one
    /// asterisk from each side.
    func testItalicDoesNotStripAsterisksOffABoldPair() {
        let text = "**bold**" as NSString
        let edit = MarkdownFormatter.toggleWrap(
            in: text, selection: NSRange(location: 2, length: 4), marker: "*"
        )

        XCTAssertEqual(edit.replacement, "*bold*", "should wrap, not unwrap the bold markers")
        XCTAssertEqual(edit.range, NSRange(location: 2, length: 4))
    }

    func testItalicStillUnwrapsAGenuineItalicPair() {
        let text = "*soft*" as NSString
        let edit = MarkdownFormatter.toggleWrap(
            in: text, selection: NSRange(location: 1, length: 4), marker: "*"
        )

        XCTAssertEqual(edit.replacement, "soft")
        XCTAssertEqual(edit.range, NSRange(location: 0, length: 6))
    }

    // MARK: - Links and images

    func testLinkLeavesTheCursorInsideTheParens() {
        let text = "abc" as NSString
        let edit = MarkdownFormatter.link(in: text, selection: NSRange(location: 0, length: 3))

        XCTAssertEqual(edit.replacement, "[abc]()")
        // "[abc]()" — index 6 is the closing paren, so the cursor precedes it.
        XCTAssertEqual(edit.selection, NSRange(location: 6, length: 0))
    }

    func testImageWritesMarkdownAndLeavesTheCursorInsideTheParens() {
        let text = "abc" as NSString
        let edit = MarkdownFormatter.image(in: text, selection: NSRange(location: 0, length: 3))

        XCTAssertEqual(edit.replacement, "![abc]()")
        XCTAssertEqual(edit.selection, NSRange(location: 7, length: 0))
    }

    // MARK: - Headings

    func testAddsAHeadingToAPlainLine() {
        let text = "hello" as NSString
        let edit = MarkdownFormatter.toggleHeading(
            in: text, selection: NSRange(location: 2, length: 0), level: 1
        )

        XCTAssertEqual(edit.replacement, "# ")
        XCTAssertEqual(edit.range, NSRange(location: 0, length: 0))
        XCTAssertEqual(edit.selection, NSRange(location: 4, length: 0))
    }

    func testTogglingTheSameLevelStripsTheHeading() {
        let text = "# hello" as NSString
        let edit = MarkdownFormatter.toggleHeading(
            in: text, selection: NSRange(location: 3, length: 0), level: 1
        )

        XCTAssertEqual(edit.replacement, "")
        XCTAssertEqual(edit.range, NSRange(location: 0, length: 2))
        XCTAssertEqual(edit.selection, NSRange(location: 1, length: 0))
    }

    func testHeadingLevelsReplaceRatherThanStack() {
        let text = "# hello" as NSString
        let edit = MarkdownFormatter.toggleHeading(
            in: text, selection: NSRange(location: 3, length: 0), level: 3
        )

        XCTAssertEqual(edit.replacement, "### ")
        XCTAssertEqual(edit.range, NSRange(location: 0, length: 2), "the old marker is replaced")
    }

    func testHashWithoutASpaceIsNotTreatedAsAnExistingHeading() {
        let text = "#tag" as NSString
        let edit = MarkdownFormatter.toggleHeading(
            in: text, selection: NSRange(location: 0, length: 0), level: 1
        )

        XCTAssertEqual(edit.range, NSRange(location: 0, length: 0), "nothing to replace")
        XCTAssertEqual(edit.replacement, "# ")
    }

    func testHeadingWorksOnTheLineContainingTheCursorNotTheFirstLine() {
        let text = "first\nsecond" as NSString
        let edit = MarkdownFormatter.toggleHeading(
            in: text, selection: NSRange(location: 8, length: 0), level: 2
        )

        XCTAssertEqual(edit.range, NSRange(location: 6, length: 0))
        XCTAssertEqual(edit.replacement, "## ")
    }

    // MARK: - Line prefixes

    func testAddsAndRemovesABulletPrefix() {
        let plain = "hello" as NSString
        let added = MarkdownFormatter.toggleLinePrefix(
            in: plain, selection: NSRange(location: 0, length: 0), prefix: "- "
        )
        XCTAssertEqual(added.replacement, "- ")
        XCTAssertEqual(added.range, NSRange(location: 0, length: 0))

        let bulleted = "- hello" as NSString
        let removed = MarkdownFormatter.toggleLinePrefix(
            in: bulleted, selection: NSRange(location: 4, length: 0), prefix: "- "
        )
        XCTAssertEqual(removed.replacement, "")
        XCTAssertEqual(removed.range, NSRange(location: 0, length: 2))
        XCTAssertEqual(removed.selection, NSRange(location: 2, length: 0))
    }

    func testLinePrefixGoesAfterAnyIndent() {
        let text = "    hello" as NSString
        let edit = MarkdownFormatter.toggleLinePrefix(
            in: text, selection: NSRange(location: 6, length: 0), prefix: "> "
        )

        XCTAssertEqual(edit.range, NSRange(location: 4, length: 0))
        XCTAssertEqual(edit.replacement, "> ")
    }
}
