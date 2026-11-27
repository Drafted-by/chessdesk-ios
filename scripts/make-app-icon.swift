// Draws the app icon: the 2×2 ChessDesk mark in brass on the warm canvas.
// Usage: swift scripts/make-app-icon.swift <output.png>
import AppKit
import CoreGraphics

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

// Canvas, lit slightly from the top like a lamp over a desk.
let gradient = CGGradient(
    colorsSpace: space,
    colors: [color(0x221E1A), color(0x100F0D)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: []
)

// The mark, on the site's 24-unit grid, scaled to sit inside the icon.
let scale: CGFloat = 26
let offset = (CGFloat(size) - 24 * scale) / 2
func square(_ x: CGFloat, _ y: CGFloat, inset: CGFloat = 0) -> CGPath {
    let rect = CGRect(x: offset + x * scale, y: offset + y * scale, width: 9.5 * scale, height: 9.5 * scale)
        .insetBy(dx: inset, dy: inset)
    return CGPath(roundedRect: rect, cornerWidth: 2 * scale - inset, cornerHeight: 2 * scale - inset, transform: nil)
}

// CoreGraphics has y up: the brass squares go top-left and bottom-right.
context.setFillColor(color(0xE0B676))
context.addPath(square(2, 12.5))
context.addPath(square(12.5, 2))
context.fillPath()

context.setStrokeColor(color(0x857F78))
context.setLineWidth(1.5 * scale)
context.addPath(square(12.5, 12.5, inset: 0.75 * scale))
context.addPath(square(2, 2, inset: 0.75 * scale))
context.strokePath()

let image = NSBitmapImageRep(cgImage: context.makeImage()!)
try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
