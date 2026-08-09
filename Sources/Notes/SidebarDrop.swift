import CoreTransferable
import UniformTypeIdentifiers

/// What a sidebar drag carries.
///
/// Deliberately a private type rather than a file URL: a file-URL payload would
/// also let the Finder accept the drop and move a note clean out of the vault,
/// which is a lot of destruction to hang on a slipped mouse.
enum SidebarDrop: Codable, Transferable {
    case note(UUID)
    case folder(URL)

    /// Carried as plain data rather than a custom UTI: an exported type has to
    /// be declared in an Info.plist, and this app generates its own. Anything
    /// else dropped here simply fails to decode and is refused.
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}
