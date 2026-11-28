// Round 2 of the ChessDesk app icon: ten candidates drawn at icon scale, with material and light.
//
// The vocabulary is the brand's (warm graphite, paper ink, one brass element, light from the top
// left) and the material is that of `CDButtonStyle`: lighter at the top, a line of light on the
// upper edge, a dark foot, a short shade under it. Depth, never a glow.
//
// Run `design/icon/render.sh round2` from the repository root.

import CoreGraphics
import CoreText
import Foundation
import SwiftUI

// MARK: Painting

/// SVG path data on a piece's 100 grid, placed on the icon's 1024 grid.
struct Place {
    let scale: CGFloat
    let x: CGFloat
    let y: CGFloat

    var transform: CGAffineTransform { CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale) }

    func path(_ data: String) -> CGPath {
        var t = transform
        return Path(svg: data).cgPath.copy(using: &t)!
    }

    func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: x + px * scale, y: y + py * scale) }

    func disc(_ px: CGFloat, _ py: CGFloat, _ rx: CGFloat, _ ry: CGFloat? = nil) -> CGPath {
        ellipse(x + px * scale, y + py * scale, rx * scale, (ry ?? rx) * scale)
    }
}

func union(_ paths: [CGPath]) -> CGPath {
    paths.dropFirst().reduce(paths[0]) { $0.union($1) }
}

func moved(_ path: CGPath, _ dx: CGFloat, _ dy: CGFloat) -> CGPath {
    var t = CGAffineTransform(translationX: dx, y: dy)
    return path.copy(using: &t)!
}

func outline(_ path: CGPath, _ width: CGFloat, cap: CGLineCap = .round, join: CGLineJoin = .round) -> CGPath {
    path.copy(strokingWithWidth: width, lineCap: cap, lineJoin: join, miterLimit: 4)
}

extension CGContext {
    func paint(_ path: CGPath, _ color: CGColor, rule: CGPathFillRule = .winding) {
        saveGState()
        addPath(path)
        setFillColor(color)
        fillPath(using: rule)
        restoreGState()
    }

    func line(_ path: CGPath, _ color: CGColor, _ width: CGFloat, cap: CGLineCap = .round, join: CGLineJoin = .round) {
        saveGState()
        addPath(path)
        setStrokeColor(color)
        setLineWidth(width)
        setLineCap(cap)
        setLineJoin(join)
        strokePath()
        restoreGState()
    }

    func clipped(to path: CGPath, _ body: () -> Void) {
        saveGState()
        addPath(path)
        clip()
        body()
        restoreGState()
    }

    /// A linear gradient across a shape. `from` and `to` are in the unit square of its bounding box.
    func wash(
        _ path: CGPath, _ colors: [CGColor], _ locations: [CGFloat]? = nil,
        from: CGPoint = CGPoint(x: 0.25, y: 0), to: CGPoint = CGPoint(x: 0.75, y: 1)
    ) {
        let box = path.boundingBoxOfPath
        let stops = locations ?? colors.indices.map { CGFloat($0) / CGFloat(colors.count - 1) }
        let gradient = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: stops)!
        clipped(to: path) {
            drawLinearGradient(
                gradient,
                start: CGPoint(x: box.minX + from.x * box.width, y: box.minY + from.y * box.height),
                end: CGPoint(x: box.minX + to.x * box.width, y: box.minY + to.y * box.height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
    }

    /// The short shade a raised shape throws down and to the right.
    func shade(_ path: CGPath, dx: CGFloat = 6, dy: CGFloat = 14, blur: CGFloat = 18, _ alpha: CGFloat = 0.6) {
        saveGState()
        // Shadow offsets are in the bitmap's own space (y up), whatever the transform.
        setShadow(offset: CGSize(width: dx, height: -dy), blur: blur, color: rgb(0x050403, alpha))
        addPath(path)
        setFillColor(rgb(0x0C0B0A))
        fillPath()
        restoreGState()
    }

    /// Light or shade falling inside a shape from its own edge: the edge of light of a raised form
    /// (offset down-right, light colour) or the wall shadow of a recess (offset down-right, dark).
    func edge(_ path: CGPath, dx: CGFloat, dy: CGFloat, blur: CGFloat, _ color: CGColor) {
        saveGState()
        addPath(path)
        clip()
        setShadow(offset: CGSize(width: dx, height: -dy), blur: blur, color: color)
        let outside = CGMutablePath()
        outside.addRect(CGRect(x: -3000, y: -3000, width: 7000, height: 7000))
        outside.addPath(path)
        addPath(outside)
        setFillColor(color.copy(alpha: 1)!)
        fillPath(using: .evenOdd)
        restoreGState()
    }

    /// Parallel engraving strokes clipped to a shape. 45° reads "/" like the emblems' hatch.
    func hatch(_ clip: CGPath, pitch: CGFloat, width: CGFloat, _ color: CGColor) {
        let box = clip.boundingBoxOfPath
        let lines = CGMutablePath()
        var c = ((box.minX + box.minY) / pitch).rounded(.down) * pitch
        while c < box.maxX + box.maxY + pitch {
            lines.move(to: CGPoint(x: c - box.maxY - width, y: box.maxY + width))
            lines.addLine(to: CGPoint(x: c - box.minY + width, y: box.minY - width))
            c += pitch
        }
        clipped(to: clip) { line(lines, color, width, cap: .butt) }
    }

    /// A groove cut in a raised form: a dark line with light caught on its lower lip.
    func groove(_ path: CGPath, _ width: CGFloat, dark: CGColor, light: CGColor) {
        line(moved(path, width * 0.35, width * 0.45), light, width * 0.7)
        line(path, dark, width)
    }
}

// MARK: Materials

enum Metal {
    static let ink = rgb(0xEFEAE2)
    static let brass = rgb(0xE0B676)
    static let brassDark = rgb(0x6E4F24)
    static let graphite = rgb(0x1A1815)

    /// Warm graphite, a shade lighter where the light comes from. Never pure black.
    static func ground(_ c: CGContext, _ colors: [UInt32] = [0x2E2A25, 0x1B1916, 0x121110]) {
        let gradient = CGGradient(colorsSpace: sRGB, colors: colors.map { rgb($0) } as CFArray, locations: [0, 0.55, 1])!
        c.drawLinearGradient(
            gradient, start: CGPoint(x: 260, y: 0), end: CGPoint(x: 764, y: side),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    /// Raised brass, lit from the top left.
    static func brass(_ c: CGContext, _ p: CGPath, depth d: CGFloat = 8, shade: CGFloat = 0.6) {
        if shade > 0 { c.shade(p, dx: d * 0.7, dy: d * 1.6, blur: d * 2.2, shade) }
        c.wash(p, [rgb(0xF1D5A2), rgb(0xE0B676), rgb(0xC0935A)], [0, 0.48, 1])
        c.edge(p, dx: -d * 0.9, dy: -d * 1.1, blur: d * 1.6, rgb(0x7A5526, 0.75))
        c.edge(p, dx: d * 0.55, dy: d * 0.7, blur: d * 0.35, rgb(0xFBEBCB, 0.95))
    }

    /// Raised paper ink: the same form, in the colour of the page.
    static func paper(_ c: CGContext, _ p: CGPath, depth d: CGFloat = 8, shade: CGFloat = 0.6) {
        if shade > 0 { c.shade(p, dx: d * 0.7, dy: d * 1.6, blur: d * 2.2, shade) }
        c.wash(p, [rgb(0xF8F5EF), rgb(0xEFEAE2), rgb(0xD3CBBE)], [0, 0.45, 1])
        c.edge(p, dx: -d * 0.9, dy: -d * 1.1, blur: d * 1.8, rgb(0x8E8577, 0.7))
        c.edge(p, dx: d * 0.5, dy: d * 0.6, blur: d * 0.3, rgb(0xFFFFFF, 0.9))
    }

    /// A recess cut in the graphite, its floor engraved.
    static func recess(_ c: CGContext, _ p: CGPath, depth d: CGFloat = 8, pitch: CGFloat = 44, hatch: CGFloat = 12) {
        c.wash(p, [rgb(0x100F0D), rgb(0x191714)])
        c.hatch(p, pitch: pitch, width: hatch, rgb(0x857F78, 0.55))
        c.edge(p, dx: d * 0.9, dy: d * 1.3, blur: d * 1.8, rgb(0x000000, 0.8))
        c.line(moved(p, d * 0.25, d * 0.3), rgb(0xFFF6E6, 0.10), d * 0.4)
    }
}

// MARK: Pieces (100 grid, y down)

enum Piece {
    /// A Staunton knight in profile, facing left: pricked ear, long nose, the jaw clear of the chest.
    static let knight =
        "M57 2C55 5.6 53 9.6 52 14C47.6 15 43.4 18 40.4 22.4C38 26 35.4 30.2 32 34.2"
        + "C26.6 40.6 21.2 46.2 16.6 51.4C12.8 55.6 10 59.2 10 63.8C10 68.8 12.8 72.4 17.6 72.6"
        + "C22.8 72.8 27.6 70.6 32.6 67.4C37.6 65 42.8 63.4 47.2 59.6C48.4 67.6 43.4 76 36.8 82.4"
        + "C32.2 87 29.4 91.6 28.8 97L88 97C92 73 89.4 46 73 24.4C70.4 21 67 17.4 63.4 14.4"
        + "C61.8 10 59.8 5.6 57 2Z"
    static let knightEye = "M35.6 36.6C37 34.4 40 33.8 42.2 35.4C40.8 37.8 37.8 38.4 35.6 36.6Z"
    static let knightNostril = "M13.6 61C15 59.8 16.8 60.2 17.4 61.8C16 62.8 14.4 62.6 13.6 61Z"
    static let knightMouth = "M10.8 67.6C14 66.8 17.6 67 21 65"
    static let knightCheek = "M45.4 42.4C49.8 47.6 50.4 54 47.2 59.6"
    static let knightEar = "M56.6 7.6C55 10.4 54.2 13 54 15.6"
    /// The crest: the line of the mane along the back of the neck, the mane itself, and its locks.
    static let knightCrest = "M63.4 14.4C76 34 81 63 78.6 97"
    static let knightManeSide = "M63.4 14.4C76 34 81 63 78.6 97L120 97L120 14.4Z"
    static let knightMane = [
        "M68.6 24.6C72.6 26.6 76.6 29.6 80 33.6", "M73.6 36.6C77.6 38.6 81.6 41.6 84.8 45.8",
        "M77 49C80.8 51 84.6 54 87.6 58", "M79 61.6C82.6 63.6 86.2 66.6 89 70.6",
        "M79.8 74.4C83 76.4 86.6 79.4 89.6 83.4",
    ]

    /// A Staunton king, front view: cross, crown, collar, body, foot.
    static let kingParts = [
        "M46.6 1.5H53.4V7.4H59.6V13.6H53.4V21H46.6V13.6H40.4V7.4H46.6Z",
        "M31 25.5C39 19.6 61 19.6 69 25.5L61.6 44H38.4Z",
        "M34.6 43.4H65.4C67 43.4 68 44.4 68 46V48.4C68 50 67 51 65.4 51H34.6C33 51 32 50 32 48.4V46C32 44.4 33 43.4 34.6 43.4Z",
        "M40.4 50H59.6C60 63 63.6 73.6 72.4 83H27.6C36.4 73.6 40 63 40.4 50Z",
        "M26 82H74C76.4 82 78 83.6 78 86V98H22V86C22 83.6 23.6 82 26 82Z",
    ]

    /// A pawn: head, collar, body, foot.
    static let pawnParts = [
        "M50 6C61 6 69.4 14.4 69.4 25.4C69.4 36.4 61 44.8 50 44.8C39 44.8 30.6 36.4 30.6 25.4C30.6 14.4 39 6 50 6Z",
        "M34 42.6H66C68 42.6 69.4 44 69.4 46V47.6C69.4 49.6 68 51 66 51H34C32 51 30.6 49.6 30.6 47.6V46C30.6 44 32 42.6 34 42.6Z",
        "M40.6 50H59.4C59.8 62.6 64 73 73.6 82.6H26.4C36 73 40.2 62.6 40.6 50Z",
        "M24.6 81.6H75.4C77.8 81.6 79.6 83.4 79.6 85.8V98H20.4V85.8C20.4 83.4 22.2 81.6 24.6 81.6Z",
    ]

    /// A bishop: finial, mitre, collar, body, foot.
    static let bishopParts = [
        "M50 1.6C53.4 1.6 56 4.2 56 7.6C56 11 53.4 13.6 50 13.6C46.6 13.6 44 11 44 7.6C44 4.2 46.6 1.6 50 1.6Z",
        "M50 11C61.6 20.6 67.6 31.6 67.6 39.6C67.6 45.6 63.6 49.6 58 49.6H42C36.4 49.6 32.4 45.6 32.4 39.6C32.4 31.6 38.4 20.6 50 11Z",
        "M35 48H65C67 48 68.4 49.4 68.4 51.4V52.6C68.4 54.6 67 56 65 56H35C33 56 31.6 54.6 31.6 52.6V51.4C31.6 49.4 33 48 35 48Z",
        "M41.4 55H58.6C59 66 63 75 72 83H28C37 75 41 66 41.4 55Z",
        "M25.6 82H74.4C76.8 82 78.6 83.8 78.6 86.2V98H21.4V86.2C21.4 83.8 23.2 82 25.6 82Z",
    ]
    static let bishopSlit = "M57.4 21.6 47.4 34.6"

    /// A rook: battlements, tower, foot.
    static let rookParts = [
        "M24 6H37V14H44V6H56V14H63V6H76V27C76 31 73 34 69 34H31C27 34 24 31 24 27Z",
        "M33.6 32H66.4L70.4 80H29.6Z",
        "M24 78H76C78.4 78 80 79.6 80 82V98H20V82C20 79.6 21.6 78 24 78Z",
    ]

    static func whole(_ parts: [String], _ at: Place) -> CGPath { union(parts.map(at.path)) }
}

// MARK: Type

func bundledFont(_ file: String, _ size: CGFloat) -> CTFont {
    let url = URL(fileURLWithPath: "ChessDesk/Resources/Fonts/\(file)")
    guard let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider) else {
        fatalError("Font not found: \(url.path). Run from the repository root.")
    }
    return CTFontCreateWithGraphicsFont(font, size, nil, nil)
}

/// The outlines of a line of text, y down, the baseline's start at the origin.
func outlines(_ text: String, _ font: CTFont, tracking: CGFloat = 0) -> CGPath {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTKernAttributeName as String): tracking,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let result = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for index in 0..<count {
            guard let glyph = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
            let t = CGAffineTransform(translationX: positions[index].x, y: -positions[index].y).scaledBy(x: 1, y: -1)
            result.addPath(glyph, transform: t)
        }
    }
    return result
}

/// A path moved so that its bounding box is centred on a point.
func centred(_ path: CGPath, at point: CGPoint) -> CGPath {
    let box = path.boundingBoxOfPath
    return moved(path, point.x - box.midX, point.y - box.midY)
}

func lozenge(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: x - r, y: y))
    path.addLine(to: CGPoint(x: x, y: y - r))
    path.addLine(to: CGPoint(x: x + r, y: y))
    path.addLine(to: CGPoint(x: x, y: y + r))
    path.closeSubpath()
    return path
}

// MARK: The ten candidates

struct Round2Candidate {
    let number: Int
    let name: String
    let draw: (CGContext) -> Void

    var file: String { String(format: "%02d-%@", number, name) }
}

let round2: [Round2Candidate] = [
    Round2Candidate(number: 1, name: "brass-knight", draw: brassKnight),
    Round2Candidate(number: 2, name: "engraved-knight", draw: engravedKnight),
    Round2Candidate(number: 3, name: "inlaid-mark", draw: inlaidMark),
    Round2Candidate(number: 4, name: "monogram", draw: monogram),
    Round2Candidate(number: 5, name: "king-cameo", draw: kingCameo),
    Round2Candidate(number: 6, name: "paper-knight", draw: paperKnight),
    Round2Candidate(number: 7, name: "board-crop", draw: boardCrop),
    Round2Candidate(number: 8, name: "better-move", draw: betterMove),
    Round2Candidate(number: 9, name: "seal", draw: seal),
    Round2Candidate(number: 10, name: "promotion", draw: promotion),
]

/// The knight's engraved features, as grooves in a raised form. With `raised`, the mane stands
/// proud of the neck instead of being bounded by a groove.
func knightFeatures(
    _ c: CGContext, _ at: Place, dark: CGColor, light: CGColor, weight: CGFloat = 1, raised: CGPath? = nil
) {
    let w = at.scale * weight
    if let raised {
        let mane = at.path(Piece.knightManeSide).intersection(raised)
        Metal.brass(c, mane, depth: at.scale * 0.9, shade: 0)
        c.clipped(to: raised) { c.line(at.path(Piece.knightCrest), dark.copy(alpha: 0.55)!, w * 0.8) }
    } else {
        c.groove(at.path(Piece.knightCrest), w * 1.5, dark: dark, light: light)
    }
    c.clipped(to: raised ?? at.path(Piece.knight)) {
        for stroke in Piece.knightMane { c.groove(at.path(stroke), w * 1.4, dark: dark, light: light) }
    }
    c.groove(at.path(Piece.knightCheek), w * 1.5, dark: dark, light: light)
    c.groove(at.path(Piece.knightMouth), w * 1.4, dark: dark, light: light)
    c.groove(at.path(Piece.knightEar), w * 1.3, dark: dark, light: light)
    c.paint(moved(at.path(Piece.knightEye), w * 0.3, w * 0.4), light)
    c.paint(at.path(Piece.knightEye), dark)
    c.paint(at.path(Piece.knightNostril), dark)
}

// 1. Brass knight in relief: embossed brass on graphite, the board only a pressure in the ground.
func brassKnight(_ c: CGContext) {
    Metal.ground(c)
    // The board, suggested: two squares pressed into the graphite, meeting behind the knight.
    for square in [rect(0, 0, 512, 512), rect(512, 512, 512, 512)] {
        c.paint(square, rgb(0x0B0A09, 0.34))
        c.hatch(square, pitch: 46, width: 5, rgb(0xEFEAE2, 0.045))
        c.edge(square, dx: 6, dy: 8, blur: 14, rgb(0x000000, 0.5))
    }
    // The bust runs off the foot of the icon.
    let at = Place(scale: 9.9, x: 512 - 49 * 9.9, y: 70)
    let knight = at.path(Piece.knight)
    Metal.brass(c, knight, depth: 16, shade: 0.8)
    // Modelled, not flat: the form turns away from the light toward the back and the foot.
    c.edge(knight, dx: -34, dy: -40, blur: 90, rgb(0x7A5526, 0.5))
    c.edge(knight, dx: 22, dy: 26, blur: 60, rgb(0xFBEBCB, 0.3))
    knightFeatures(c, at, dark: rgb(0x6E4F24, 0.9), light: rgb(0xFBEBCB, 0.75), raised: knight)
}

// 2. Engraved knight, full bleed: the head modelled only by lines that follow the arch of the neck.
func engravedKnight(_ c: CGContext) {
    Metal.ground(c, [0x26221E, 0x181613, 0x100F0D])
    let at = Place(scale: 11.6, x: -78, y: 26)
    let knight = at.path(Piece.knight)
    c.paint(knight, rgb(0x0E0D0B, 0.55))
    // Concentric lines about a point under the jaw: they run up the neck and over the poll.
    // Their weight is the light: heavy on the brow and the front of the neck, a hair on the back.
    let centre = at.point(27, 86)
    let pitch: CGFloat = 39
    let box = knight.boundingBoxOfPath
    c.clipped(to: knight) {
        c.setStrokeColor(Metal.ink)
        c.setLineCap(.round)
        var radius = pitch * 0.6
        while radius < 1500 {
            let step = 7 / radius
            var angle = -CGFloat.pi
            while angle < 0.4 {
                let a = CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
                let b = CGPoint(x: centre.x + radius * cos(angle + step), y: centre.y + radius * sin(angle + step))
                angle += step
                guard box.insetBy(dx: -20, dy: -20).contains(a) else { continue }
                // Light from the top left, falling away toward the mane and the foot.
                let across = 0.75 * (a.x - box.minX) / box.width + 0.35 * (a.y - box.minY) / box.height
                let light = max(0, min(1, 1.25 - 1.45 * across))
                c.setLineWidth(pitch * (0.08 + 0.74 * pow(light, 1.3)))
                c.move(to: a)
                c.addLine(to: b)
                c.strokePath()
            }
            radius += pitch
        }
    }
    // The contour, and the features cut back into the ground.
    c.line(knight, Metal.ink, 15)
    let cut = rgb(0x131210)
    c.line(at.path(Piece.knightCheek), cut, 26)
    c.line(at.path(Piece.knightCheek), Metal.ink, 9)
    c.paint(at.disc(15.4, 61.4, 2.5, 1.9), cut)
    // The one brass detail: the eye.
    let eye = at.path(Piece.knightEye)
    c.line(eye, cut, 44)
    Metal.brass(c, outline(eye, 14).union(eye), depth: 5, shade: 0)
}

// 3. The mark, with material: brass and paper inlays, two engraved recesses.
func inlaidMark(_ c: CGContext) { inlaidMark(c, .standard) }

/// The chosen icon in one of the three appearances of iOS 18.
///
/// - `standard`: the inlays on the warm graphite ground.
/// - `dark`: the four squares alone on a transparent ground. The system's dark fill is lighter
///   than the graphite, so the recesses carry their own near-black floor, a brighter hatch and a
///   lit lower lip: they stay cut into whatever lies under them.
/// - `tinted`: grayscale on a dark ground. The system multiplies it by the tint, so brass and
///   paper are told apart by value alone: brass sits at mid-gray, paper near white.
func inlaidMark(_ c: CGContext, _ appearance: Appearance) {
    let size: CGFloat = 372
    let gap: CGFloat = 44
    let radius: CGFloat = 78
    let near = (side - 2 * size - gap) / 2
    let far = near + size + gap
    let recesses = [rect(far, near, size, size, radius), rect(near, far, size, size, radius)]
    let brass = rect(near, near, size, size, radius)
    let paper = rect(far, far, size, size, radius)

    switch appearance {
    case .standard:
        Metal.ground(c)
        for recess in recesses { Metal.recess(c, recess, depth: 13, pitch: 50, hatch: 13) }
        Metal.brass(c, brass, depth: 15, shade: 0.7)
        Metal.paper(c, paper, depth: 15, shade: 0.7)

    case .dark:
        for recess in recesses {
            c.wash(recess, [rgb(0x070605), rgb(0x0E0D0B)])
            c.hatch(recess, pitch: 50, width: 13, rgb(0xA39C93, 0.62))
            c.edge(recess, dx: 12, dy: 17, blur: 23, rgb(0x000000, 0.85))
            // The lip of the cut, catching the light on its lower right.
            c.clipped(to: outline(recess, 14)) { c.line(moved(recess, 4, 5), rgb(0xFFF6E6, 0.34), 6) }
        }
        Metal.brass(c, brass, depth: 15, shade: 0.7)
        Metal.paper(c, paper, depth: 15, shade: 0.7)

    case .tinted:
        Metal.ground(c, [0x2B2B2B, 0x1A1A1A, 0x0F0F0F])
        for recess in recesses {
            c.wash(recess, [gray(0.03), gray(0.06)])
            c.hatch(recess, pitch: 50, width: 13, gray(0.52, 0.5))
            c.edge(recess, dx: 12, dy: 17, blur: 23, gray(0, 0.8))
            c.line(moved(recess, 3, 4), gray(1, 0.12), 5)
        }
        // Brass, a clear step under the paper.
        c.shade(brass, dx: 10, dy: 24, blur: 33, 0.7)
        c.wash(brass, [gray(0.66), gray(0.56), gray(0.44)], [0, 0.48, 1])
        c.edge(brass, dx: -13, dy: -16, blur: 24, gray(0.22, 0.7))
        c.edge(brass, dx: 8, dy: 10, blur: 5, gray(0.80, 0.95))
        c.shade(paper, dx: 10, dy: 24, blur: 33, 0.7)
        c.wash(paper, [gray(1), gray(0.95), gray(0.84)], [0, 0.45, 1])
        c.edge(paper, dx: -13, dy: -16, blur: 27, gray(0.55, 0.7))
        c.edge(paper, dx: 7, dy: 9, blur: 4, gray(1, 0.9))
    }
}

/// Renders the chosen icon (no. 3, `inlaid-mark`) in its three appearances, with its sheets.
func renderChosen(into directory: URL) {
    func image(_ appearance: Appearance) -> CGImage {
        let context = bitmap(Int(side), Int(side))
        inlaidMark(context, appearance)
        return context.makeImage()!
    }
    let name = "inlaid-mark"
    let standard = image(.standard)
    let dark = image(.dark)
    let tinted = image(.tinted)
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
            (dark, systemDarkFill(), true, "\(name) · dark appearance, on the system's fill"),
            (dark, systemDarkFill(), false, "\(name) · dark appearance, light wallpaper"),
            (tinted, nil, true, "\(name) · tinted appearance, before the tint"),
        ]),
        to: directory.appendingPathComponent("\(name)-appearances-sheet.png"), opaque: true
    )
}

// 4. Monogram: "cd" in Newsreader over the rule with its brass lozenge. A book plate.
func monogram(_ c: CGContext) {
    Metal.ground(c)
    // The plate: a ruled frame, inside the mask's corners.
    let frame = rect(84, 84, 856, 856, 150)
    c.line(frame, rgb(0x857F78, 0.55), 7)
    c.line(rect(112, 112, 800, 800, 124), rgb(0x857F78, 0.28), 4)
    let letters = centred(outlines("cd", bundledFont("Newsreader72pt-Medium.ttf", 640), tracking: -14), at: CGPoint(x: 512, y: 446))
    Metal.paper(c, letters, depth: 9, shade: 0.7)
    // The ornament rule: a line, a dot, the lozenge, a dot, a line.
    let y: CGFloat = 770
    let rule = CGMutablePath()
    rule.move(to: CGPoint(x: 236, y: y))
    rule.addLine(to: CGPoint(x: 408, y: y))
    rule.move(to: CGPoint(x: 616, y: y))
    rule.addLine(to: CGPoint(x: 788, y: y))
    c.line(rule, rgb(0xEFEAE2, 0.75), 10)
    c.paint(ellipse(446, y, 11, 11), rgb(0xEFEAE2, 0.85))
    c.paint(ellipse(578, y, 11, 11), rgb(0xEFEAE2, 0.85))
    Metal.brass(c, lozenge(512, y, 46), depth: 6, shade: 0.6)
}

// 5. King cameo: a king in a brass-ringed medallion, the ground engraved.
func kingCameo(_ c: CGContext) {
    Metal.ground(c)
    let field = ellipse(512, 512, 398, 398)
    Metal.recess(c, field, depth: 16, pitch: 40, hatch: 9)
    let ring = ellipse(512, 512, 446, 446).subtracting(ellipse(512, 512, 384, 384))
    let at = Place(scale: 7.1, x: 512 - 50 * 7.1, y: 512 - 50.5 * 7.1)
    let king = Piece.whole(Piece.kingParts, at)
    Metal.paper(c, king, depth: 12, shade: 0.75)
    // Engraved: the joints of the turned piece.
    let cut = rgb(0x2A2622, 0.85)
    c.line(at.path("M38.4 44H61.6M32.4 51H67.6M27.8 82.4H72.2"), cut, 7, cap: .butt)
    Metal.brass(c, ring, depth: 13, shade: 0.7)
}

// 6. Paper icon: the palette inverted. A page, the knight in dark ink, its square in brass.
func paperKnight(_ c: CGContext) {
    let page = CGGradient(
        colorsSpace: sRGB, colors: [rgb(0xF7F3EC), rgb(0xEFEAE2), rgb(0xE0D8CA)] as CFArray, locations: [0, 0.5, 1]
    )!
    c.drawLinearGradient(
        page, start: CGPoint(x: 200, y: 0), end: CGPoint(x: 824, y: side),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    // The square behind the head: the one brass element, inlaid in the page.
    let square = rect(118, 118, 560, 560, 40)
    c.wash(square, [rgb(0xEDCC95), rgb(0xE0B676), rgb(0xCDA162)])
    c.edge(square, dx: 5, dy: 7, blur: 10, rgb(0x6E4F24, 0.55))
    let at = Place(scale: 9.6, x: 512 - 46.5 * 9.6, y: 100)
    let knight = at.path(Piece.knight)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 8, height: -14), blur: 22, color: rgb(0x4A3A22, 0.35))
    c.paint(knight, rgb(0x1A1815))
    c.restoreGState()
    c.wash(knight, [rgb(0x2E2A25), rgb(0x1A1815), rgb(0x121110)])
    c.edge(knight, dx: 5, dy: 6, blur: 5, rgb(0x6B655D, 0.8))
    // Engraved in the ink: the page shows through.
    let paper = rgb(0xEFEAE2)
    c.clipped(to: knight) { c.line(at.path(Piece.knightCrest), paper, 12) }
    c.clipped(to: knight) { for stroke in Piece.knightMane { c.line(at.path(stroke), paper, 12) } }
    c.line(at.path(Piece.knightCheek), paper, 14)
    c.line(at.path(Piece.knightMouth), paper, 12)
    c.line(at.path(Piece.knightEar), paper, 12)
    c.paint(at.path(Piece.knightEye), paper)
    c.line(at.path(Piece.knightEye), paper, 6)
    c.paint(at.path(Piece.knightNostril), paper)
}

// 7. Board crop: two squares across, bleeding off the edges; a paper rook cut by the frame.
func boardCrop(_ c: CGContext) {
    Metal.ground(c)
    let splitX: CGFloat = 372
    let splitY: CGFloat = 318
    let far: CGFloat = 1400
    // Dark squares: engraved graphite.
    for square in [rect(-far, -far, far + splitX, far + splitY), rect(splitX, splitY, far, far)] {
        c.wash(square, [rgb(0x24211D), rgb(0x141210)])
        c.hatch(square, pitch: 54, width: 13, rgb(0x857F78, 0.5))
    }
    // Light squares: brass inlay, the one brass element.
    for square in [rect(splitX, -far, far, far + splitY), rect(-far, splitY, far + splitX, far)] {
        c.clipped(to: square) {
            c.wash(rect(0, 0, side, side), [rgb(0xF1D5A2), rgb(0xE0B676), rgb(0xC0935A)], [0, 0.45, 1])
        }
        c.edge(square, dx: 6, dy: 8, blur: 4, rgb(0xFBEBCB, 0.9))
        c.edge(square, dx: -8, dy: -10, blur: 14, rgb(0x7A5526, 0.6))
    }
    // The rook stands on the dark square, its foot below the frame.
    let at = Place(scale: 7.7, x: 706 - 50 * 7.7, y: 236)
    let rook = Piece.whole(Piece.rookParts, at)
    // Its shade, long across the board.
    c.saveGState()
    c.translateBy(x: 56, y: 40)
    c.setShadow(offset: .zero, blur: 30, color: rgb(0x050403, 0.5))
    c.paint(rook, rgb(0x050403, 0.42))
    c.restoreGState()
    Metal.paper(c, rook, depth: 15, shade: 0.5)
    c.line(at.path("M27 34H73M26.4 78.4H73.6"), rgb(0x2A2622, 0.85), 8, cap: .butt)
    c.line(at.path("M63.6 40 67 75"), rgb(0x2A2622, 0.32), 22)
}

// 8. The better move: a brass arrow from a bishop to its square, on an engraved board.
func betterMove(_ c: CGContext) {
    Metal.ground(c)
    let tile: CGFloat = 352
    let origin: CGFloat = -16
    for row in 0..<3 {
        for column in 0..<3 where (row + column) % 2 == 0 {
            let square = rect(origin + CGFloat(column) * tile, origin + CGFloat(row) * tile, tile, tile)
            c.paint(square, rgb(0x0C0B0A, 0.5))
            c.hatch(square, pitch: 44, width: 10, rgb(0x857F78, 0.42))
        }
    }
    for index in 1..<3 {
        let at = origin + CGFloat(index) * tile
        c.line(rect(at - 2, 0, 4, side), rgb(0x857F78, 0.35), 1)
        c.line(rect(0, at - 2, side, 4), rgb(0x857F78, 0.35), 1)
    }
    // The arrow: from the bishop's square to the far corner square.
    let from = CGPoint(x: 350, y: 674)
    let to = CGPoint(x: 880, y: 144)
    let length = hypot(to.x - from.x, to.y - from.y)
    let arrow = CGMutablePath()
    let half: CGFloat = 50
    let head: CGFloat = 250
    let wing: CGFloat = 144
    arrow.move(to: CGPoint(x: 0, y: -half))
    arrow.addLine(to: CGPoint(x: length - head, y: -half))
    arrow.addLine(to: CGPoint(x: length - head, y: -wing))
    arrow.addLine(to: CGPoint(x: length, y: 0))
    arrow.addLine(to: CGPoint(x: length - head, y: wing))
    arrow.addLine(to: CGPoint(x: length - head, y: half))
    arrow.addLine(to: CGPoint(x: 0, y: half))
    arrow.closeSubpath()
    var turn = CGAffineTransform(translationX: from.x, y: from.y).rotated(by: atan2(to.y - from.y, to.x - from.x))
    let placed = outline(arrow.copy(using: &turn)!, 26).union(arrow.copy(using: &turn)!)
    Metal.brass(c, placed, depth: 13, shade: 0.75)
    // The bishop, in paper, standing on its square in front of the arrow's tail.
    let at = Place(scale: 5.3, x: 252 - 50 * 5.3, y: 424)
    let bishop = Piece.whole(Piece.bishopParts, at)
    Metal.paper(c, bishop, depth: 11, shade: 0.8)
    let cut = rgb(0x2A2622, 0.85)
    c.line(at.path(Piece.bishopSlit), cut, 15)
    c.line(at.path("M33 49.4H67M32.4 56H67.6M28.4 82.4H71.6"), cut, 6, cap: .butt)
}

// 9. Seal: a struck brass coin, raised rim, beaded border, the knight in relief.
func seal(_ c: CGContext) {
    Metal.ground(c)
    let centre = CGPoint(x: 512, y: 512)
    let coin = ellipse(centre.x, centre.y, 452, 452)
    Metal.brass(c, coin, depth: 16, shade: 0.8)
    // The field, struck lower than the rim.
    let field = ellipse(centre.x, centre.y, 392, 392)
    c.wash(field, [rgb(0xCDA162), rgb(0xBE9255), rgb(0xA67B43)])
    c.edge(field, dx: 9, dy: 12, blur: 16, rgb(0x5E411B, 0.75))
    c.line(moved(field, 3, 4), rgb(0xFBEBCB, 0.5), 4)
    // The beaded border.
    let beads = 44
    for index in 0..<beads {
        let angle = CGFloat(index) / CGFloat(beads) * 2 * .pi
        let bead = ellipse(centre.x + 354 * cos(angle), centre.y + 354 * sin(angle), 11, 11)
        Metal.brass(c, bead, depth: 4, shade: 0.35)
    }
    // The knight, struck in relief, its neck running out under the border like a portrait bust.
    let at = Place(scale: 7.2, x: 162, y: 188)
    let inner = ellipse(centre.x, centre.y, 326, 326)
    let knight = at.path(Piece.knight).intersection(inner)
    Metal.brass(c, knight, depth: 12, shade: 0.5)
    c.edge(knight, dx: -22, dy: -26, blur: 60, rgb(0x7A5526, 0.45))
    c.clipped(to: inner) {
        knightFeatures(c, at, dark: rgb(0x6E4F24, 0.9), light: rgb(0xFBEBCB, 0.7), raised: knight)
    }
}

// 10. Promotion: the pawn that earns its crown. Getting better, which is what the app is for.
func promotion(_ c: CGContext) {
    Metal.ground(c)
    // Its square, engraved, bleeding off the foot of the icon.
    let square = rect(172, 520, 680, 680)
    Metal.recess(c, square, depth: 12, pitch: 50, hatch: 12)
    let at = Place(scale: 6.5, x: 512 - 50 * 6.5, y: 350)
    let pawn = Piece.whole(Piece.pawnParts, at)
    Metal.paper(c, pawn, depth: 13, shade: 0.8)
    let cut = rgb(0x2A2622, 0.85)
    c.line(at.path("M31.4 51H68.6M26.8 82H73.2"), cut, 7, cap: .butt)
    // The crown, in brass, held above the head.
    let k = Place(scale: 4.3, x: 512 - 50 * 4.3, y: 72)
    let crown = union([
        k.path("M10 20 28 46 50 12 72 46 90 20 82 66H18Z"),
        k.disc(10, 18, 7.5), k.disc(50, 10, 8.5), k.disc(90, 18, 7.5),
        k.path("M16 62H84C86 62 87.4 63.4 87.4 65.4V72.6C87.4 74.6 86 76 84 76H16C14 76 12.6 74.6 12.6 72.6V65.4C12.6 63.4 14 62 16 62Z"),
    ])
    Metal.brass(c, crown, depth: 11, shade: 0.75)
    c.groove(k.path("M17 62.4H83"), 6, dark: rgb(0x6E4F24, 0.85), light: rgb(0xFBEBCB, 0.7))
}

// MARK: Sheets

func round2Icon(_ candidate: Round2Candidate) -> CGImage {
    let context = bitmap(Int(side), Int(side))
    candidate.draw(context)
    return context.makeImage()!
}

/// All the candidates side by side, masked and numbered, on a dark and on a light wallpaper.
func overview(_ icons: [(Round2Candidate, CGImage)], size: CGFloat, columns: Int) -> CGImage {
    let gap = max(28, size * 0.26)
    let caption = max(26, size * 0.2)
    let margin: CGFloat = 44
    let rows = Int((Double(icons.count) / Double(columns)).rounded(.up))
    let width = 2 * margin + CGFloat(columns) * size + CGFloat(columns - 1) * gap
    let bandHeight = 2 * margin + CGFloat(rows) * (size + caption) + CGFloat(rows - 1) * gap * 0.5
    let context = bitmap(Int(width), Int(bandHeight * 2))
    for (band, dark) in [true, false].enumerated() {
        let top = CGFloat(band) * bandHeight
        context.setFillColor(dark ? rgb(0x0B0B0D) : rgb(0xE9E9EE))
        context.fill(CGRect(x: 0, y: top, width: width, height: bandHeight))
        for (index, item) in icons.enumerated() {
            let x = margin + CGFloat(index % columns) * (size + gap)
            let y = top + margin + CGFloat(index / columns) * (size + caption + gap * 0.5)
            masked(item.1, size: size, at: CGPoint(x: x, y: y), on: context)
            label(
                size >= 120 ? "\(item.0.number) · \(item.0.name)" : "\(item.0.number)",
                at: CGPoint(x: x, y: y + size + caption * 0.72), color: dark ? gray(0.66) : gray(0.32),
                size: size >= 120 ? 13 : 12, on: context
            )
        }
    }
    return context.makeImage()!
}

func renderRound2(into directory: URL, only: Set<Int> = []) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var icons: [(Round2Candidate, CGImage)] = []
    for candidate in round2 {
        let image = round2Icon(candidate)
        icons.append((candidate, image))
        guard only.isEmpty || only.contains(candidate.number) else { continue }
        write(image, to: directory.appendingPathComponent("\(candidate.file).png"), opaque: true)
        write(
            sheet([
                (image, nil, true, "\(candidate.number) · \(candidate.name) · dark wallpaper"),
                (image, nil, false, "\(candidate.number) · \(candidate.name) · light wallpaper"),
            ]),
            to: directory.appendingPathComponent("\(candidate.file)-sheet.png"), opaque: true
        )
    }
    write(overview(icons, size: 180, columns: 5), to: directory.appendingPathComponent("overview.png"), opaque: true)
    write(overview(icons, size: 60, columns: 10), to: directory.appendingPathComponent("overview-small.png"), opaque: true)
}
