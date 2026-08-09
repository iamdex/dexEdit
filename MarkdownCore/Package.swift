// swift-tools-version: 5.9
import PackageDescription

/// The parts of dexEdit that are only text and ranges: the markdown scanner
/// behind live styling, the formatting operations, the cursor-context reader,
/// and note title/preview/filename derivation.
///
/// Nothing here touches AppKit, so it compiles unchanged for iOS — which is the
/// point. The app's own layer holds everything platform-shaped.
let package = Package(
    name: "MarkdownCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
    ],
    targets: [
        .target(name: "MarkdownCore"),
        .testTarget(name: "MarkdownCoreTests", dependencies: ["MarkdownCore"]),
    ]
)
