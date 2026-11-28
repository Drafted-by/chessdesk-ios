import SwiftUI

// SVG path data ("M5 26.9c.1-2 1.4-3.3 2.6-4.6…") read into a `Path`, so the
// emblems can be carried over from the site's `components/ui/emblems.tsx`
// figure for figure instead of being redrawn by hand. Every command of the
// path grammar is read: M L H V C S Q T A Z, absolute and relative, with the
// compact number spellings SVG allows ("1.2.4", "-4.6-2.4", "0 01").

nonisolated extension Path {
    init(svg data: String) {
        var reader = SVGPathReader(data)
        self = reader.path()
    }
}

private nonisolated struct SVGPathReader {
    private let characters: [Character]
    private var index = 0

    init(_ data: String) {
        characters = Array(data)
    }

    mutating func path() -> Path {
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        /// The last control point of the previous curve, for S and T.
        var control: CGPoint?
        var command: Character = "M"

        while true {
            skipSeparators()
            guard index < characters.count else { break }
            if characters[index].isLetter {
                command = characters[index]
                index += 1
            } else if command == "Z" || command == "z" {
                break
            }
            let relative = command.isLowercase
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            var nextControl: CGPoint?
            switch command {
            case "M", "m":
                guard let x = number(), let y = number() else { return path }
                current = point(x, y)
                start = current
                path.move(to: current)
                // Further pairs after a move are lines.
                command = relative ? "l" : "L"
            case "L", "l":
                guard let x = number(), let y = number() else { return path }
                current = point(x, y)
                path.addLine(to: current)
            case "H", "h":
                guard let x = number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            case "V", "v":
                guard let y = number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            case "C", "c":
                guard let x1 = number(), let y1 = number(), let x2 = number(), let y2 = number(),
                      let x = number(), let y = number() else { return path }
                let second = point(x2, y2)
                let end = point(x, y)
                path.addCurve(to: end, control1: point(x1, y1), control2: second)
                current = end
                nextControl = second
            case "S", "s":
                guard let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return path }
                let first = control.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let second = point(x2, y2)
                let end = point(x, y)
                path.addCurve(to: end, control1: first, control2: second)
                current = end
                nextControl = second
            case "Q", "q":
                guard let x1 = number(), let y1 = number(), let x = number(), let y = number() else { return path }
                let first = point(x1, y1)
                let end = point(x, y)
                path.addQuadCurve(to: end, control: first)
                current = end
                nextControl = first
            case "T", "t":
                guard let x = number(), let y = number() else { return path }
                let first = control.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let end = point(x, y)
                path.addQuadCurve(to: end, control: first)
                current = end
                nextControl = first
            case "A", "a":
                guard let rx = number(), let ry = number(), let rotation = number(),
                      let large = flag(), let sweep = flag(), let x = number(), let y = number() else { return path }
                let end = point(x, y)
                Self.arc(&path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                current = end
            case "Z", "z":
                path.closeSubpath()
                current = start
            default:
                return path
            }
            control = nextControl
        }
        return path
    }

    private mutating func skipSeparators() {
        while index < characters.count, characters[index] == " " || characters[index] == "," || characters[index].isNewline
            || characters[index] == "\t" {
            index += 1
        }
    }

    private mutating func number() -> CGFloat? {
        skipSeparators()
        var text = ""
        if index < characters.count, characters[index] == "-" || characters[index] == "+" {
            text.append(characters[index])
            index += 1
        }
        var seenPoint = false
        while index < characters.count {
            let character = characters[index]
            if character.isNumber {
                text.append(character)
            } else if character == ".", !seenPoint {
                seenPoint = true
                text.append(character)
            } else {
                break
            }
            index += 1
        }
        return Double(text).map { CGFloat($0) }
    }

    /// An arc flag is one digit, and may be glued to what follows ("01").
    private mutating func flag() -> Bool? {
        skipSeparators()
        guard index < characters.count, characters[index] == "0" || characters[index] == "1" else { return nil }
        defer { index += 1 }
        return characters[index] == "1"
    }

    /// An elliptical arc in SVG's endpoint form, as cubic curves (the
    /// conversion of the SVG implementation notes, section B.2.4).
    private static func arc(
        _ path: inout Path, from: CGPoint, to: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool
    ) {
        var rx = abs(rx)
        var ry = abs(ry)
        guard rx > 0, ry > 0, from != to else {
            path.addLine(to: to)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (from.x - to.x) / 2
        let dy = (from.y - to.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = denominator == 0 ? 0 : max(0, numerator / denominator).squareRoot()
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (from.x + to.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (from.y + to.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            var value = acos(min(1, max(-1, dot / length)))
            if ux * vy - uy * vx < 0 { value = -value }
            return value
        }
        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let pieces = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / CGFloat(pieces)
        let handle = 4 / 3 * tan(step / 4)
        func onEllipse(_ t: CGFloat) -> CGPoint {
            CGPoint(
                x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi
            )
        }
        func tangent(_ t: CGFloat) -> CGPoint {
            CGPoint(
                x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi
            )
        }
        for piece in 0..<pieces {
            let t0 = theta + CGFloat(piece) * step
            let t1 = t0 + step
            let p0 = onEllipse(t0)
            let p1 = piece == pieces - 1 ? to : onEllipse(t1)
            let d0 = tangent(t0)
            let d1 = tangent(t1)
            path.addCurve(
                to: p1,
                control1: CGPoint(x: p0.x + handle * d0.x, y: p0.y + handle * d0.y),
                control2: CGPoint(x: p1.x - handle * d1.x, y: p1.y - handle * d1.y)
            )
        }
    }
}
