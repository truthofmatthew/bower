// Draws Bower's app icon from AppIcon.dc.html into Sources/Assets.xcassets/AppIcon.appiconset.
// Run from the repo root: swift docs/make-icon.swift
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// "M{x0} 830C{x0} {y1} {c1} {top} 512 {top}S{1024-x0} {y1} {1024-x0} 830": an arch; S mirrors the control point.
func arch(_ x0: CGFloat, _ y1: CGFloat, _ c1: CGFloat, _ top: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x0, y: 830))
    p.addCurve(to: CGPoint(x: 512, y: top), control1: CGPoint(x: x0, y: y1), control2: CGPoint(x: c1, y: top))
    p.addCurve(to: CGPoint(x: 1024 - x0, y: 830), control1: CGPoint(x: 1024 - c1, y: top), control2: CGPoint(x: 1024 - x0, y: y1))
    return p
}

/// `full`: the 1024 artwork. Otherwise the downsampled one: solid body and one arch of `simpleStroke` (in 1024 units).
func render(px: Int, full: Bool, simpleStroke: CGFloat) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024
    // SVG's y points down.
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: s, y: -s)
    let body = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)

    if full {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: color(0x000000, 0.35))
        ctx.addPath(body); ctx.setFillColor(color(0x0B2F2C)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(body); ctx.clip()
        let g = CGGradient(colorsSpace: nil, colors: [color(0x17534E), color(0x0B2F2C)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: CGRect(x: 100.5, y: 100.5, width: 823, height: 823), cornerWidth: 184.5, cornerHeight: 184.5, transform: nil))
        ctx.setStrokeColor(color(0xFFFFFF, 0.10)); ctx.setLineWidth(1); ctx.strokePath()
    } else {
        ctx.addPath(body); ctx.setFillColor(color(0x124541)); ctx.fillPath()
    }

    for (x, y, hex) in [(300.0, 540.0, UInt32(0x3FD3C2)), (524, 540, 0xF3E6C8), (300, 684, 0x4C7BE8), (524, 684, 0x9FE8DD)] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: 200, height: 120), cornerWidth: 22, cornerHeight: 22, transform: nil))
        ctx.setFillColor(color(hex)); ctx.fillPath()
    }

    ctx.setLineCap(.round)
    if full {
        ctx.addPath(arch(234, 400, 360, 226)); ctx.setStrokeColor(color(0xF0D9A3)); ctx.setLineWidth(22); ctx.strokePath()
        ctx.addPath(arch(266, 430, 380, 266)); ctx.setStrokeColor(color(0xD9B66E)); ctx.setLineWidth(22); ctx.strokePath()
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [120, 26])
        ctx.addPath(arch(204, 370, 340, 190)); ctx.setStrokeColor(color(0xC49A52)); ctx.setLineWidth(14); ctx.strokePath()
        ctx.restoreGState()
    } else {
        ctx.addPath(arch(250, 415, 370, 246)); ctx.setStrokeColor(color(0xE8C98A)); ctx.setLineWidth(simpleStroke); ctx.strokePath()
    }
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "Sources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
// Stroke widths for the downsampled arch, from the design's "Downsampled sizes" table.
let simple: [Int: CGFloat] = [256: 26, 128: 30, 64: 40, 32: 56, 16: 72]
for px in [16, 32, 64, 128, 256, 512, 1024] {
    try render(px: px, full: px >= 512, simpleStroke: simple[px] ?? 26).write(to: dir.appendingPathComponent("icon_\(px).png"))
}
let entries = [(16, 1, 16), (16, 2, 32), (32, 1, 32), (32, 2, 64), (128, 1, 128), (128, 2, 256), (256, 1, 256), (256, 2, 512), (512, 1, 512), (512, 2, 1024)]
let images = entries.map { #"{"idiom":"mac","size":"\#($0.0)x\#($0.0)","scale":"\#($0.1)x","filename":"icon_\#($0.2).png"}"# }
try #"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
    .write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try #"{"info":{"author":"xcode","version":1}}"#
    .write(to: dir.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(dir.path)")
