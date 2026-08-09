import Foundation

/// How the markdown in the buffer is drawn. Both modes show the same
/// characters — there is one storage format and no conversion between them.
enum EditorMode: String, CaseIterable {
    /// Syntax markers dimmed, surrounding text carrying the formatting.
    case styled
    /// Uniform monospace, no styling at all.
    case raw

    mutating func toggle() {
        self = self == .styled ? .raw : .styled
    }
}
