// Renders the ChessDesk app icon candidates and their contact sheets.
//
// The icon is drawn in code, like the rest of the brand: the vocabulary is
// that of the engraved emblems (`ChessDesk/UI/Emblems.swift`), redrawn at
// icon scale. Path data is read with the app's own `Path(svg:)`
// (`ChessDesk/UI/SVGPath.swift`), compiled in next to this file.
//
// Run `design/icon/render.sh` from the repository root.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: Tokens (ChessDesk/UI/Tokens.swift)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: white, green: white, blue: white, alpha: alpha)
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let side: CGFloat = 1024

/// The three appearances of an iOS 18 icon.
enum Appearance: String {
    /// Opaque, on the warm graphite ground.
    case standard
    /// The subject alone on a transparent ground: the system lays its own dark fill under it.
    case dark
    /// Grayscale, opaque: the system tints it.
    case tinted
}

enum Tone { case ink, muted, brass, cut }

// MARK: The pen

/// The gestures of `EmblemPen`, in CoreGraphics and on a 1024 grid, y down.
struct Pen {
    let context: CGContext
    let appearance: Appearance

    private func color(_ tone: Tone) -> CGColor {
        let tinted = appearance == .tinted
        switch tone {
        case .ink: return tinted ? gray(0.94) : rgb(0xEFEAE2)
        case .muted: return tinted ? gray(0.50) : rgb(0x857F78)
        case .brass: return tinted ? gray(0.72) : rgb(0xE0B676)
        case .cut: return gray(0)
        }
    }

    private func draw(_ tone: Tone, _ opacity: CGFloat, _ body: () -> Void) {
        context.saveGState()
        context.setBlendMode(tone == .cut ? .clear : .normal)
        context.setAlpha(opacity)
        context.setFillColor(color(tone))
        context.setStrokeColor(color(tone))
        body()
        context.restoreGState()
    }

    func fill(_ path: CGPath, _ tone: Tone, opacity: CGFloat = 1) {
        draw(tone, opacity) {
            context.addPath(path)
            context.fillPath()
        }
    }

    func stroke(
        _ path: CGPath, _ tone: Tone, _ width: CGFloat, cap: CGLineCap = .butt, join: CGLineJoin = .miter,
        opacity: CGFloat = 1
    ) {
        draw(tone, opacity) {
            context.setLineWidth(width)
            context.setLineCap(cap)
            context.setLineJoin(join)
            context.addPath(path)
            context.strokePath()
        }
    }

    /// A shape filled and outlined in one tone: the subject, or (in `cut`) the gap it opens around itself.
    func solid(_ path: CGPath, _ tone: Tone, _ width: CGFloat) {
        fill(path, tone)
        stroke(path, tone, width, join: .round)
    }

    /// The brass element, lit from the top left: strong brass to deep brass across its own box.
    func brass(_ path: CGPath) {
        let box = path.boundingBoxOfPath
        let stops: [CGColor] = appearance == .tinted
            ? [gray(0.80), gray(0.70), gray(0.60)]
            : [rgb(0xEDCC95), rgb(0xE0B676), rgb(0xCDA162)]
        let gradient = CGGradient(colorsSpace: sRGB, colors: stops as CFArray, locations: [0, 0.5, 1])!
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient, start: CGPoint(x: box.minX, y: box.minY), end: CGPoint(x: box.maxX, y: box.maxY), options: []
        )
        context.restoreGState()
    }

    /// 45° engraving hatch ("/" strokes) clipped to a shape.
    func hatch(_ clip: CGPath, pitch: CGFloat, width: CGFloat, _ tone: Tone = .muted, opacity: CGFloat = 1) {
        let box = clip.boundingBoxOfPath
        let lines = CGMutablePath()
        var c = ((box.minX + box.minY) / pitch).rounded(.up) * pitch
        while c < box.maxX + box.maxY {
            lines.move(to: CGPoint(x: c - box.maxY - width, y: box.maxY + width))
            lines.addLine(to: CGPoint(x: c - box.minY + width, y: box.minY - width))
            c += pitch
        }
        context.saveGState()
        context.addPath(clip)
        context.clip()
        stroke(lines, tone, width, opacity: opacity)
        context.restoreGState()
    }
}

// MARK: Shapes

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat = 0) -> CGPath {
    let rect = CGRect(x: x, y: y, width: width, height: height)
    return radius > 0 ? Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath : CGPath(rect: rect, transform: nil)
}

func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry), transform: nil)
}

/// SVG path data on an emblem's 32 grid, scaled and moved onto the icon's 1024 grid.
struct Grid {
    let scale: CGFloat
    let x: CGFloat
    let y: CGFloat

    func path(_ data: String) -> CGPath {
        var transform = CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale)
        return Path(svg: data).cgPath.copy(using: &transform)!
    }

    func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
        CGPoint(x: x + px * scale, y: y + py * scale)
    }
}

// MARK: The candidates

enum Candidate: String, CaseIterable {
    /// The knight of the puzzles emblem on its board fragment, its target square in brass.
    case knight
    /// The mark of the logo as an engraved board: one square in brass, one in paper, two hatched.
    case mark
    /// The cameo king of the account emblem, the frame in brass.
    case cameo

    func draw(_ p: Pen) {
        switch self {
        case .knight: knight(p)
        case .mark: mark(p)
        case .cameo: cameo(p)
        }
    }

    private func knight(_ p: Pen) {
        // A 2 × 2 board fragment laid out like the mark of the logo: the lit square in brass
        // (the one brass element), the dark squares hatched, the fourth under the knight.
        let origin: CGFloat = 112
        let square: CGFloat = 296
        func cell(_ column: Int, _ row: Int) -> CGPath {
            rect(origin + CGFloat(column) * square, origin + CGFloat(row) * square, square, square)
        }
        p.hatch(cell(1, 0), pitch: 62, width: 17, opacity: 0.8)
        p.hatch(cell(0, 1), pitch: 62, width: 17, opacity: 0.8)
        p.stroke(rect(origin, origin, 2 * square, 2 * square), .muted, 14)
        p.brass(cell(0, 0))

        // The knight of the puzzles emblem (Staunton profile, facing left), breaking the frame.
        let g = Grid(scale: 44, x: 268, y: -366)
        let body = g.path(
            "M5 26.9c.1-2 1.4-3.3 2.6-4.6-1.2.4-2.6.7-3.6.2-1-.5-1.3-1.5-.8-2.4l3.2-4.6.9-2.3 1 1.3c3 .2 5.4 2.7 5.7 6.4.2 2.2-.4 4.2-1 6Z"
        )
        let plinth = g.path("M3.6 29v-1.1c0-.6.4-1 1-1h8.2c.6 0 1 .4 1 1V29Z")
        let foot = g.path("M2.6 29.4h12.2")
        p.stroke(foot, .cut, 120, cap: .round)
        p.solid(body, .cut, 68)
        p.solid(plinth, .cut, 68)
        p.stroke(foot, .ink, 52, cap: .round)
        p.fill(plinth, .ink)
        p.solid(body, .ink, 20)
        // Engraved: the mane on the shaded side, the collar and the eye.
        p.stroke(g.path("M11.5 16.2 13.2 17.3M12.1 18.4l1.7.9M12.3 20.7l1.7.8M12.2 23l1.5.7"), .cut, 15, cap: .round)
        p.stroke(g.path("M5.3 26.95h7.6"), .cut, 10)
        p.fill(ellipse(g.point(8.1, 17.3).x, g.point(8.1, 17.3).y, 21, 21), .cut)
    }

    private func mark(_ p: Pen) {
        let size: CGFloat = 300
        let gap: CGFloat = 36
        let radius: CGFloat = 62
        let near = (side - 2 * size - gap) / 2
        let far = near + size + gap
        // Dark squares: hatched and ruled.
        for (x, y) in [(far, near), (near, far)] {
            let inset = rect(x + 8, y + 8, size - 16, size - 16, radius - 8)
            p.hatch(inset, pitch: 60, width: 17, opacity: 0.85)
            p.stroke(inset, .muted, 16)
        }
        // Light squares: brass, where the light falls, and paper.
        p.brass(rect(near, near, size, size, radius))
        let paper = rect(far, far, size, size, radius)
        p.fill(paper, .ink)
    }

    private func cameo(_ p: Pen) {
        // Drawn on the emblem's proportions, then enlarged about the centre to fill the icon.
        p.context.saveGState()
        defer { p.context.restoreGState() }
        p.context.translateBy(x: side / 2, y: side / 2)
        p.context.scaleBy(x: 1.12, y: 1.12)
        p.context.translateBy(x: -side / 2, y: -side / 2)
        let g = Grid(scale: 30, x: 32, y: 38)
        let centre = g.point(16, 15.8)
        let oval = ellipse(centre.x, centre.y, 288, 366)
        // The ground of the cameo, engraved.
        p.hatch(oval, pitch: 46, width: 9, opacity: 0.6)
        // The king, redrawn at icon scale: cross, crown, collar, body and foot, a gap between each.
        let cross = Grid(scale: 30, x: 32, y: 24).path("M16 6.2V9.4M14.4 7.6H17.6")
        let k = Grid(scale: 30, x: 32, y: 24)
        let pieces = [
            "M11.7 11C13 9.7 19 9.7 20.3 11L18.7 14.8H13.3Z",
            "M12.6 15.3H19.4V16.6H12.6Z",
            "M13.6 17.1H18.4C18.5 19.6 19 21.2 19.9 22.4H12.1C13 21.2 13.5 19.6 13.6 17.1Z",
            "M11.8 22.9H20.2V24.5H11.8Z",
        ].map(k.path)
        p.stroke(cross, .cut, 86, cap: .round)
        for piece in pieces { p.solid(piece, .cut, 52) }
        p.stroke(cross, .ink, 38, cap: .round)
        for piece in pieces { p.solid(piece, .ink, 8) }
        p.stroke(k.path("M18.7 11.6 18 13.9M17.4 17.9c.1 1.6.4 2.8 1 3.8"), .cut, 12, cap: .round)
        // The frame: the one brass element.
        p.fill(oval.copy(strokingWithWidth: 90, lineCap: .butt, lineJoin: .miter, miterLimit: 4), .cut)
        p.brass(oval.copy(strokingWithWidth: 54, lineCap: .butt, lineJoin: .miter, miterLimit: 4))
    }
}

// MARK: Rendering

func bitmap(_ width: Int, _ height: Int) -> CGContext {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // y down, like SwiftUI and SVG.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    return context
}

/// Draws an image upright in a y-down context.
func place(_ image: CGImage, in rect: CGRect, on context: CGContext) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(origin: .zero, size: rect.size))
    context.restoreGState()
}

func icon(_ candidate: Candidate, _ appearance: Appearance) -> CGImage {
    // The subject on its own layer, so its knock-outs open onto whatever ground lies under it.
    let subject = bitmap(Int(side), Int(side))
    candidate.draw(Pen(context: subject, appearance: appearance))

    let context = bitmap(Int(side), Int(side))
    let ground: [CGColor]? = switch appearance {
    // Warm graphite, a shade lighter where the light comes from. Never pure black.
    case .standard: [rgb(0x2A2622), rgb(0x1A1815), rgb(0x121110)]
    case .dark: nil
    case .tinted: [gray(0.17), gray(0.10), gray(0.06)]
    }
    if let ground {
        let gradient = CGGradient(colorsSpace: sRGB, colors: ground as CFArray, locations: [0, 0.55, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 260, y: 0), end: CGPoint(x: 764, y: side), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    place(subject.makeImage()!, in: CGRect(x: 0, y: 0, width: side, height: side), on: context)
    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL, opaque: Bool) {
    var output = image
    if opaque {
        // No alpha channel in an opaque icon: App Store Connect refuses one.
        let flat = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        flat.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        output = flat.makeImage()!
    }
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
    print(url.path)
}

func label(_ text: String, at point: CGPoint, color: CGColor, size: CGFloat = 15, on context: CGContext) {
    let font = CTFontCreateWithName("Menlo" as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    context.saveGState()
    context.translateBy(x: point.x, y: point.y)
    context.scaleBy(x: 1, y: -1)
    context.textPosition = .zero
    CTLineDraw(line, context)
    context.restoreGState()
}

/// The icon as the home screen shows it: masked with the continuous rounded shape.
func masked(_ image: CGImage, size: CGFloat, at origin: CGPoint, on context: CGContext) {
    let frame = CGRect(x: origin.x, y: origin.y, width: size, height: size)
    context.saveGState()
    context.addPath(Path(roundedRect: frame, cornerRadius: size * 0.2237, style: .continuous).cgPath)
    context.clip()
    place(image, in: frame, on: context)
    context.restoreGState()
}

let sizes: [CGFloat] = [180, 120, 80, 58]

/// One band of a contact sheet: the icon at the four sizes on one wallpaper.
func band(_ image: CGImage, y: CGFloat, wallpaper: CGColor, text: CGColor, caption: String, under: CGImage? = nil, on context: CGContext) {
    let height: CGFloat = 270
    context.setFillColor(wallpaper)
    context.fill(CGRect(x: 0, y: y, width: CGFloat(context.width), height: height))
    label(caption, at: CGPoint(x: 28, y: y + 30), color: text, on: context)
    var x: CGFloat = 40
    for size in sizes {
        let origin = CGPoint(x: x, y: y + 230 - size)
        if let under { masked(under, size: size, at: origin, on: context) }
        masked(image, size: size, at: origin, on: context)
        label("\(Int(size))", at: CGPoint(x: x, y: y + 254), color: text, size: 13, on: context)
        x += size + 44
    }
}

/// The dark fill iOS lays under a dark icon (approximated: Apple's template runs from #313131 to #141414).
func systemDarkFill() -> CGImage {
    let context = bitmap(Int(side), Int(side))
    let gradient = CGGradient(colorsSpace: sRGB, colors: [gray(0.19), gray(0.08)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: side), options: [])
    return context.makeImage()!
}

func sheet(_ bands: [(image: CGImage, under: CGImage?, dark: Bool, caption: String)]) -> CGImage {
    let context = bitmap(640, 270 * bands.count)
    for (index, item) in bands.enumerated() {
        band(
            item.image, y: CGFloat(index) * 270,
            wallpaper: item.dark ? rgb(0x0B0B0D) : rgb(0xE9E9EE),
            text: item.dark ? gray(0.62) : gray(0.35),
            caption: item.caption, under: item.under, on: context
        )
    }
    return context.makeImage()!
}

// MARK: Main

@main
enum Render {
    static func main() {
        let arguments = CommandLine.arguments
        let directory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "design/icon", isDirectory: true)
        let fill = systemDarkFill()
        for candidate in Candidate.allCases {
            let name = candidate.rawValue
            let standard = icon(candidate, .standard)
            let dark = icon(candidate, .dark)
            let tinted = icon(candidate, .tinted)
            write(standard, to: directory.appendingPathComponent("\(name).png"), opaque: true)
            write(dark, to: directory.appendingPathComponent("\(name)-dark.png"), opaque: false)
            write(tinted, to: directory.appendingPathComponent("\(name)-tinted.png"), opaque: true)
            write(
                sheet([
                    (standard, nil, true, "\(name) · dark wallpaper"),
                    (standard, nil, false, "\(name) · light wallpaper"),
                ]),
                to: directory.appendingPathComponent("\(name)-sheet.png"), opaque: true
            )
            write(
                sheet([
                    (dark, fill, true, "\(name) · dark appearance, on the system's fill"),
                    (tinted, nil, true, "\(name) · tinted appearance, before the tint"),
                ]),
                to: directory.appendingPathComponent("\(name)-appearances-sheet.png"), opaque: true
            )
        }
    }
}
