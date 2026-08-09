import Foundation

/// One note. The markdown text is the whole truth — the title, the preview and
/// the filename are all derived from it and never stored alongside it.
public struct Note: Identifiable, Equatable {
    /// Stable for the lifetime of the process, so the list and the editor keep
    /// pointing at the same note across a rename.
    public let id: UUID

    /// nil until the note has been written to disk for the first time.
    public var fileURL: URL?
    public var text: String
    public var modified: Date

    public init(id: UUID = UUID(), fileURL: URL?, text: String, modified: Date = .now) {
        self.id = id
        self.fileURL = fileURL
        self.text = text
        self.modified = modified
    }

    /// What the sidebar shows: a title and a one-line taste of the body.
    public struct Summary: Equatable {
        public var title: String
        public var preview: String
    }

    /// Derived on demand. Only the head of the note is scanned, so this stays
    /// cheap even when it is called once per row per redraw.
    public var summary: Summary {
        let lines = Self.headLines(of: text)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return Summary(title: "Untitled", preview: "") }

        // The first heading is the title wherever it sits; failing that, the
        // first non-empty line is.
        let headingIndex = lines.firstIndex { Self.headingText(of: $0) != nil }
        let titleIndex = headingIndex ?? 0
        let title = headingIndex.flatMap { Self.headingText(of: lines[$0]) } ?? lines[0]

        // The preview is the first line that isn't the one used as the title,
        // with its own heading markers stripped so the sidebar stays readable.
        let previewLine = lines.enumerated().first { $0.offset != titleIndex }?.element ?? ""
        let preview = Self.headingText(of: previewLine) ?? previewLine

        return Summary(
            title: String(title.prefix(120)),
            preview: String(preview.prefix(160))
        )
    }

    /// The filename this note wants, without the extension.
    public var slug: String { Self.slug(for: summary.title) }

    // MARK: - Derivation

    private static let scanLineLimit = 50

    private static func headLines(of text: String) -> [Substring] {
        Array(text.split(separator: "\n", omittingEmptySubsequences: false).prefix(scanLineLimit))
    }

    /// The text of an ATX heading, or nil if the line is not one.
    private static func headingText(of line: String) -> String? {
        var hashes = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", hashes < 6 {
            hashes += 1
            index = line.index(after: index)
        }
        guard hashes > 0 else { return nil }
        // "#hashtag" is not a heading; a heading needs a space after the hashes.
        guard index < line.endIndex, line[index] == " " else { return nil }

        let text = line[index...].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// Filename-safe form of a title: lowercase, words joined by hyphens.
    public static func slug(for title: String) -> String {
        var out = ""
        var lastWasDash = true

        for character in title.lowercased() {
            if character.isLetter || character.isNumber {
                out.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }

        var trimmed = String(out.prefix(60))
        while trimmed.hasSuffix("-") { trimmed.removeLast() }
        return trimmed.isEmpty ? "untitled" : trimmed
    }
}
