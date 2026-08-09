import XCTest

/// The scanner behind the live styling layer. It runs on every keystroke, so
/// what it does with awkward input matters more than what it does with clean
/// input.
final class MarkdownScannerTests: XCTestCase {

    private func spans(_ source: String, line: Int = 0) -> [MarkdownSpan] {
        let text = source as NSString
        var location = 0
        for _ in 0..<line {
            location = NSMaxRange(text.lineRange(for: NSRange(location: location, length: 0)))
        }
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        return MarkdownScanner.spans(
            in: text, lineRange: lineRange, fences: MarkdownScanner.FenceMap(text: text)
        )
    }

    private func firstRange(_ spans: [MarkdownSpan], _ kind: MarkdownSpan.Kind) -> NSRange? {
        spans.first { $0.kind == kind }?.range
    }

    // MARK: - Headings

    func testHeadingProducesADimmedMarkerAndStyledText() {
        let result = spans("## Title")

        XCTAssertEqual(firstRange(result, .marker), NSRange(location: 0, length: 3))
        XCTAssertEqual(
            firstRange(result, .headingText(level: 2)),
            NSRange(location: 3, length: 5)
        )
    }

    func testHashWithoutASpaceIsNotAHeading() {
        let result = spans("#tag is not a heading")

        XCTAssertNil(result.first { if case .headingText = $0.kind { return true } else { return false } })
    }

    func testHeadingsStopAtSixLevels() {
        let result = spans("####### seven")

        XCTAssertNil(
            firstRange(result, .headingText(level: 6)),
            "seven hashes is not a heading, the seventh breaks the run"
        )
    }

    func testHeadingsDoNotGetAnInlinePass() {
        let result = spans("# A **bold** title")

        XCTAssertNil(firstRange(result, .bold), "bold inside a heading would undo the heading font")
    }

    // MARK: - Inline

    func testBoldItalicStrikeAndCode() {
        XCTAssertEqual(firstRange(spans("**b**"), .bold), NSRange(location: 2, length: 1))
        XCTAssertEqual(firstRange(spans("*i*"), .italic), NSRange(location: 1, length: 1))
        XCTAssertEqual(firstRange(spans("~~s~~"), .strike), NSRange(location: 2, length: 1))
        XCTAssertEqual(firstRange(spans("`c`"), .code), NSRange(location: 1, length: 1))
    }

    func testBoldWinsOverItalicForADoubleAsterisk() {
        let result = spans("**both**")

        XCTAssertNotNil(firstRange(result, .bold))
        XCTAssertNil(firstRange(result, .italic))
    }

    func testUnterminatedEmphasisIsPlainText() {
        XCTAssertTrue(spans("**never closed").isEmpty)
        XCTAssertTrue(spans("a * lonely asterisk").isEmpty)
    }

    func testEmphasisDoesNotSpanLines() {
        // The closing ** is on the next line, so neither line is bold.
        XCTAssertNil(firstRange(spans("**open\nclose**", line: 0), .bold))
    }

    func testLinkSplitsIntoTextAndURL() {
        let result = spans("[t](u)")

        XCTAssertEqual(firstRange(result, .linkText), NSRange(location: 1, length: 1))
        XCTAssertEqual(firstRange(result, .linkURL), NSRange(location: 4, length: 1))
    }

    func testBracketsWithoutParensAreNotALink() {
        XCTAssertNil(firstRange(spans("[not a link] here"), .linkText))
    }

    // MARK: - Block constructs

    func testBulletAndOrderedListMarkers() {
        XCTAssertEqual(firstRange(spans("- item"), .marker), NSRange(location: 0, length: 2))
        XCTAssertEqual(firstRange(spans("1. item"), .marker), NSRange(location: 0, length: 3))
    }

    func testDashWithoutASpaceIsNotAList() {
        XCTAssertNil(firstRange(spans("-notalist"), .marker))
    }

    func testBlockquoteMarksTheMarkerAndTheText() {
        let result = spans("> quoted")

        XCTAssertEqual(firstRange(result, .marker), NSRange(location: 0, length: 2))
        XCTAssertEqual(firstRange(result, .quoteText), NSRange(location: 2, length: 6))
    }

    func testHorizontalRuleTakesTheWholeLine() {
        XCTAssertEqual(firstRange(spans("---"), .rule), NSRange(location: 0, length: 3))
        XCTAssertNil(firstRange(spans("--"), .rule), "two dashes is not a rule")
        XCTAssertNil(firstRange(spans("-- text"), .rule))
    }

    // MARK: - Fenced blocks

    func testFenceMapKnowsWhichLinesAreInsideABlock() {
        let source = "before\n```\ncode\n```\nafter" as NSString
        let fences = MarkdownScanner.FenceMap(text: source)

        let lineStart: (Int) -> Int = { index in
            var location = 0
            for _ in 0..<index {
                location = NSMaxRange(source.lineRange(for: NSRange(location: location, length: 0)))
            }
            return location
        }

        XCTAssertFalse(fences.isInsideFence(lineStart: lineStart(0)), "before the fence")
        XCTAssertTrue(fences.isDelimiter(lineStart: lineStart(1)))
        XCTAssertTrue(fences.isInsideFence(lineStart: lineStart(2)), "the code line")
        XCTAssertFalse(fences.isInsideFence(lineStart: lineStart(4)), "after the closing fence")
    }

    func testCodeInsideAFenceIsNotParsedAsMarkdown() {
        let source = "```\n# not a heading **not bold**\n```" as NSString
        let fences = MarkdownScanner.FenceMap(text: source)
        let lineRange = source.lineRange(for: NSRange(location: 4, length: 0))

        let result = MarkdownScanner.spans(in: source, lineRange: lineRange, fences: fences)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.kind, .codeBlock)
    }
}
