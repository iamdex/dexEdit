import MarkdownCore
import XCTest

/// What the formatting bar shows as active. Runs on every cursor move.
final class MarkdownContextTests: XCTestCase {

    private func active(_ source: String, caret: Int) -> ActiveFormats {
        MarkdownContext.active(in: source as NSString, selection: NSRange(location: caret, length: 0))
    }

    func testCursorInsideBoldReportsBold() {
        XCTAssertTrue(active("**bold** text", caret: 4).bold)
        XCTAssertFalse(active("**bold** text", caret: 11).bold)
    }

    func testCursorInsideALinkReportsLink() {
        XCTAssertTrue(active("[text](url)", caret: 3).link)
    }

    func testHeadingLevelIsReportedFromInsideTheMarker() {
        // The caret sits in the "## " marker, which is not part of the text span.
        XCTAssertEqual(active("## Title", caret: 1).headingLevel, 2)
        XCTAssertEqual(active("## Title", caret: 5).headingLevel, 2)
        XCTAssertNil(active("plain line", caret: 3).headingLevel)
    }

    func testListAndQuoteAreReported() {
        XCTAssertTrue(active("- item", caret: 3).bulletList)
        XCTAssertTrue(active("> quoted", caret: 4).quote)
        XCTAssertFalse(active("plain", caret: 2).bulletList)
    }

    func testEmptyDocumentReportsNothing() {
        XCTAssertEqual(active("", caret: 0), ActiveFormats())
    }

    func testCaretBeyondTheTextDoesNotCrash() {
        XCTAssertEqual(active("abc", caret: 99), ActiveFormats())
    }

    func testFormatsAreReadFromTheCursorsOwnLine() {
        let source = "**bold line**\nplain line"
        XCTAssertFalse(active(source, caret: 20).bold, "the second line carries no bold")
    }
}
