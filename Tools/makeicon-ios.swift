import AppKit

// Draws the dexEdit app icon at any size and writes the macOS icon set.
// Pure CoreGraphics, no assets, so the mark stays crisp at 16pt.

let canvas: CGFloat = 1024          // Apple's icon grid
// iOS masks the corners itself and forbids transparency, so the artwork runs
// edge to edge instead of sitting inside a drawn squircle.
let bodyInset: CGFloat = 0
let outputRoot = CommandLine.arguments[1]

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha
    )
}

/// A slanted bar with rounded ends, the building block of the hash mark.
func barPath(from start: CGPoint, to end: CGPoint, width: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = (dx * dx + dy * dy).squareRoot()
    let angle = atan2(dy, dx)

    var transform = CGAffineTransform(translationX: start.x, y: start.y)
        .rotated(by: angle)
    let rect = CGRect(x: 0, y: -width / 2, width: length, height: width)
    path.addRoundedRect(in: rect, cornerWidth: width / 2, cornerHeight: width / 2, transform: transform)
    return path
}

func drawIcon(in context: CGContext, size: CGFloat) {
    let s = size / canvas                        // everything below is in 1024 space
    context.saveGState()
    context.scaleBy(x: s, y: s)

    // Squircle body
    let body = CGRect(
        x: bodyInset, y: bodyInset,
        width: canvas - bodyInset * 2,
        height: canvas - bodyInset * 2
    )
    context.saveGState()
    context.addRect(body)
    context.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [hex(0x6D6BF5), hex(0x4F46E5), hex(0x312B94)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: body.minX, y: body.maxY),
        end: CGPoint(x: body.maxX, y: body.minY),
        options: []
    )

    // Soft light across the top edge, so the surface reads as lit from above.
    let sheen = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [hex(0xFFFFFF, 0.22), hex(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        sheen,
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.midY),
        options: []
    )
    context.restoreGState()

    // The mark: a markdown hash, with a text caret where the next word goes.
    let stroke: CGFloat = 70
    let reach: CGFloat = 186                    // half-length of each bar
    let spread: CGFloat = 97                    // gap between the paired bars
    let slant: CGFloat = 37                     // lean of the vertical bars
    let caretWidth: CGFloat = 57
    let caretGap: CGFloat = 107

    // Centre the hash-and-caret group as a whole, not the hash alone.
    let halfLeft = reach + 26 + stroke / 2
    let halfRight = reach + caretGap + caretWidth
    let centre = CGPoint(x: body.midX - (halfRight - halfLeft) / 2, y: body.midY)

    context.setFillColor(hex(0xFFFFFF))
    for offset in [-spread, spread] {
        // verticals, leaning right like italic text
        context.addPath(barPath(
            from: CGPoint(x: centre.x + offset - slant, y: centre.y - reach),
            to: CGPoint(x: centre.x + offset + slant, y: centre.y + reach),
            width: stroke
        ))
    }
    for offset in [-spread + 16, spread - 16] {
        // horizontals
        context.addPath(barPath(
            from: CGPoint(x: centre.x - reach - 26, y: centre.y + offset),
            to: CGPoint(x: centre.x + reach + 26, y: centre.y + offset),
            width: stroke
        ))
    }
    context.fillPath()

    // The caret — amber, the one warm thing in the icon.
    let caret = CGRect(
        x: centre.x + reach + caretGap,
        y: centre.y - reach - 10,
        width: caretWidth,
        height: reach * 2 + 20
    )
    context.setFillColor(hex(0xFFB224))
    context.addPath(CGPath(
        roundedRect: caret, cornerWidth: caretWidth / 2, cornerHeight: caretWidth / 2, transform: nil
    ))
    context.fillPath()

    context.restoreGState()
}

func writePNG(size: CGFloat, to url: URL) {
    let pixels = Int(size)
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("no context") }

    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    drawIcon(in: context, size: size)

    guard let image = context.makeImage() else { fatalError("no image") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
    try! data.write(to: url)
}

// macOS wants every size at 1x and 2x.
let entries: [(size: Int, scale: Int)] = [(1024, 1)]

let setURL = URL(fileURLWithPath: outputRoot)
try! FileManager.default.createDirectory(at: setURL, withIntermediateDirectories: true)

var images: [[String: String]] = []
for entry in entries {
    let pixels = entry.size * entry.scale
    let name = "icon_\(entry.size)x\(entry.size)\(entry.scale == 2 ? "@2x" : "").png"
    writePNG(size: CGFloat(pixels), to: setURL.appendingPathComponent(name))
    images.append([
        "size": "\(entry.size)x\(entry.size)",
        "idiom": "universal",
        "platform": "ios",
        "filename": name,
    ])
}

let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "xcode"],
]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: setURL.appendingPathComponent("Contents.json"))

print("wrote the iOS app icon")
