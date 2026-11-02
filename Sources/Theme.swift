import AppKit

/// Tokens from docs/design/Tokens.dc.html. Every value is (dark, light).
enum Theme {
    static func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        rgba(Int(v >> 16 & 0xFF), Int(v >> 8 & 0xFF), Int(v & 0xFF), a)
    }

    static func isDark(_ appearance: NSAppearance = NSApp.effectiveAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var highContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// Strong ease-out, cubic-bezier(0.23, 1, 0.32, 1): enter and exit.
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    /// Strong ease-in-out, cubic-bezier(0.77, 0, 0.175, 1): movement on screen.
    static let easeInOut = CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)
}

/// The Snap Wheel's palette, copied from the `K` table in Wheel.dc.html.
struct WheelPalette {
    let hud, hudHC, fill, fill2, fillHC, line, lineHC: NSColor
    let label, label2, label3, accent, on, tint, sub, subCur, shadow, cap: NSColor

    static let dark = WheelPalette(
        hud: Theme.rgba(38, 38, 42, 0.70), hudHC: Theme.rgba(20, 20, 22, 0.97),
        fill: Theme.rgba(255, 255, 255, 0.08), fill2: Theme.rgba(255, 255, 255, 0.16),
        fillHC: Theme.rgba(255, 255, 255, 0.12), line: Theme.rgba(255, 255, 255, 0.14),
        lineHC: Theme.rgba(255, 255, 255, 0.72), label: Theme.hex(0xF2F2F4),
        label2: Theme.rgba(235, 235, 245, 0.62), label3: Theme.rgba(235, 235, 245, 0.28),
        accent: Theme.hex(0x3FD3C2), on: Theme.hex(0x04231F), tint: Theme.rgba(63, 211, 194, 0.24),
        sub: Theme.rgba(44, 44, 48, 0.94), subCur: Theme.rgba(28, 74, 70, 0.96),
        shadow: Theme.rgba(0, 0, 0, 0.45), cap: Theme.rgba(30, 30, 34, 0.86))

    static let light = WheelPalette(
        hud: Theme.rgba(250, 250, 252, 0.72), hudHC: Theme.rgba(255, 255, 255, 0.98),
        fill: Theme.rgba(0, 0, 0, 0.05), fill2: Theme.rgba(0, 0, 0, 0.10),
        fillHC: Theme.rgba(0, 0, 0, 0.07), line: Theme.rgba(0, 0, 0, 0.12),
        lineHC: Theme.rgba(0, 0, 0, 0.72), label: Theme.hex(0x1D1D1F),
        label2: Theme.rgba(60, 60, 67, 0.72), label3: Theme.rgba(60, 60, 67, 0.30),
        accent: Theme.hex(0x0B7A72), on: Theme.hex(0xFFFFFF), tint: Theme.rgba(11, 122, 114, 0.16),
        sub: Theme.rgba(250, 250, 252, 0.96), subCur: Theme.rgba(212, 234, 231, 0.98),
        shadow: Theme.rgba(0, 0, 0, 0.22), cap: Theme.rgba(255, 255, 255, 0.9))

    static func current(_ appearance: NSAppearance) -> WheelPalette { Theme.isDark(appearance) ? dark : light }
}

/// Snap preview colours from SnapPreview.dc.html.
struct SnapPalette {
    let fill, fillHC, stroke, keyline, innerKeyline, hud, hair, label, label2: NSColor

    static let dark = SnapPalette(
        fill: Theme.rgba(63, 211, 194, 0.18), fillHC: Theme.rgba(63, 211, 194, 0.28),
        stroke: Theme.rgba(63, 211, 194, 0.92), keyline: Theme.rgba(0, 0, 0, 0.35),
        innerKeyline: Theme.rgba(0, 0, 0, 0.25), hud: Theme.rgba(36, 36, 40, 0.72),
        hair: Theme.rgba(255, 255, 255, 0.14), label: Theme.rgba(255, 255, 255, 0.92),
        label2: Theme.rgba(235, 235, 245, 0.64))

    static let light = SnapPalette(
        fill: Theme.rgba(11, 122, 114, 0.14), fillHC: Theme.rgba(11, 122, 114, 0.28),
        stroke: Theme.rgba(11, 122, 114, 0.88), keyline: Theme.rgba(255, 255, 255, 0.60),
        innerKeyline: Theme.rgba(255, 255, 255, 0.40), hud: Theme.rgba(250, 250, 252, 0.78),
        hair: Theme.rgba(0, 0, 0, 0.12), label: Theme.rgba(0, 0, 0, 0.88),
        label2: Theme.rgba(60, 60, 67, 0.74))

    static func current(_ appearance: NSAppearance) -> SnapPalette { Theme.isDark(appearance) ? dark : light }
}

/// The 16 pt icon set: path strings copied verbatim from the design, drawn with a 1.5 pt round stroke.
enum Icon {
    static let maximize = "M2.5 6V2.5H6M10 2.5h3.5V6M13.5 10v3.5H10M6 13.5H2.5V10"
    static let thirds = "M1.75 3.25h12.5v9.5H1.75zM5.9 3.25v9.5M10.1 3.25v9.5"
    static let mode = "M2 5h9v8.5H2zM5 5V2.5h9V11h-3"
    static let layouts = "M2 2h5v5H2zM9 2h5v5H9zM2 9h5v5H2zM9 9h5v5H9z"
    static let send = "M1.5 8h8.5M7 5l3 3-3 3M13.5 2.5v11"
    static let recipe = "M3.5 1.75h6l3 3v9.5h-9zM9.5 1.75v3h3M5.75 8h4.5M5.75 10.5h4.5M5.75 13h2.5"
    static let settings = "M2 4.5h7.5M12.5 4.5H14M2 11.5h1.5M6.5 11.5H14M11 3v3M5 10v3"
    static let plus = "M8 3.5v9M3.5 8h9"

    /// "M13.25 8A5.25 5.25 0 1 1 11.7 4.3M13.25 2.25V5.5H10", with the arc built by hand.
    static var retile: CGPath {
        let p = CGMutablePath()
        // From angle 0 sweeping 315° (y-down) to (11.7, 4.3).
        p.addArc(center: CGPoint(x: 8, y: 8), radius: 5.25, startAngle: 0, endAngle: -.pi / 4 + 2 * .pi, clockwise: false)
        p.addPath(path("M13.25 2.25V5.5H10"))
        return p
    }

    /// Parses the subset of SVG path syntax the design uses: M L H V Z, absolute and relative.
    static func path(_ d: String) -> CGPath {
        let p = CGMutablePath()
        let regex = try! NSRegularExpression(pattern: "[MmLlHhVvZz]|-?(?:\\d+\\.?\\d*|\\.\\d+)")
        let tokens = regex.matches(in: d, range: NSRange(d.startIndex..., in: d)).map { String(d[Range($0.range, in: d)!]) }
        var i = 0, cmd = "M", cur = CGPoint.zero, start = CGPoint.zero
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i])!) }
        while i < tokens.count {
            if Double(tokens[i]) == nil { cmd = tokens[i]; i += 1 }
            switch cmd {
            case "M", "m":
                let x = num(), y = num()
                cur = cmd == "M" ? CGPoint(x: x, y: y) : CGPoint(x: cur.x + x, y: cur.y + y)
                start = cur
                p.move(to: cur)
                cmd = cmd == "M" ? "L" : "l"  // extra pairs after a move are line-tos
            case "L", "l":
                let x = num(), y = num()
                cur = cmd == "L" ? CGPoint(x: x, y: y) : CGPoint(x: cur.x + x, y: cur.y + y)
                p.addLine(to: cur)
            case "H", "h":
                let x = num(); cur.x = cmd == "H" ? x : cur.x + x; p.addLine(to: cur)
            case "V", "v":
                let y = num(); cur.y = cmd == "V" ? y : cur.y + y; p.addLine(to: cur)
            default:  // Z
                p.closeSubpath(); cur = start
            }
        }
        return p
    }
}
