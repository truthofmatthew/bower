import CoreGraphics

/// Every snap target. Shortcuts and names come from SnapPreview.dc.html and SetShortcuts.dc.html.
enum SnapAction: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case maximize

    var title: String {
        switch self {
        case .leftHalf: String(localized: "Left Half")
        case .rightHalf: String(localized: "Right Half")
        case .topHalf: String(localized: "Top Half")
        case .bottomHalf: String(localized: "Bottom Half")
        case .topLeft: String(localized: "Top Left")
        case .topRight: String(localized: "Top Right")
        case .bottomLeft: String(localized: "Bottom Left")
        case .bottomRight: String(localized: "Bottom Right")
        case .firstThird: String(localized: "First Third")
        case .centerThird: String(localized: "Center Third")
        case .lastThird: String(localized: "Last Third")
        case .firstTwoThirds: String(localized: "First Two Thirds")
        case .lastTwoThirds: String(localized: "Last Two Thirds")
        case .maximize: String(localized: "Maximize")
        }
    }

    var shortcut: String {
        switch self {
        case .leftHalf: "⌃⌥←"
        case .rightHalf: "⌃⌥→"
        case .topHalf: "⌃⌥↑"
        case .bottomHalf: "⌃⌥↓"
        case .topLeft: "⌃⌥U"
        case .topRight: "⌃⌥I"
        case .bottomLeft: "⌃⌥J"
        case .bottomRight: "⌃⌥K"
        case .firstThird: "⌃⌥D"
        case .centerThird: "⌃⌥F"
        case .lastThird: "⌃⌥G"
        case .firstTwoThirds: "⌃⌥E"
        case .lastTwoThirds: "⌃⌥T"
        case .maximize: "⌃⌥↩"
        }
    }

    /// The window's frame inside a display's visible frame. Both rects use the same orientation (AX, top-left).
    func frame(in v: CGRect) -> CGRect {
        let w2 = (v.width / 2).rounded(.down), h2 = (v.height / 2).rounded(.down)
        let w3 = (v.width / 3).rounded(.down)
        switch self {
        case .leftHalf: return CGRect(x: v.minX, y: v.minY, width: w2, height: v.height)
        case .rightHalf: return CGRect(x: v.minX + w2, y: v.minY, width: v.width - w2, height: v.height)
        case .topHalf: return CGRect(x: v.minX, y: v.minY, width: v.width, height: h2)
        case .bottomHalf: return CGRect(x: v.minX, y: v.minY + h2, width: v.width, height: v.height - h2)
        case .topLeft: return CGRect(x: v.minX, y: v.minY, width: w2, height: h2)
        case .topRight: return CGRect(x: v.minX + w2, y: v.minY, width: v.width - w2, height: h2)
        case .bottomLeft: return CGRect(x: v.minX, y: v.minY + h2, width: w2, height: v.height - h2)
        case .bottomRight: return CGRect(x: v.minX + w2, y: v.minY + h2, width: v.width - w2, height: v.height - h2)
        case .firstThird: return CGRect(x: v.minX, y: v.minY, width: w3, height: v.height)
        case .centerThird: return CGRect(x: v.minX + w3, y: v.minY, width: w3, height: v.height)
        case .lastThird: return CGRect(x: v.minX + 2 * w3, y: v.minY, width: v.width - 2 * w3, height: v.height)
        case .firstTwoThirds: return CGRect(x: v.minX, y: v.minY, width: 2 * w3, height: v.height)
        case .lastTwoThirds: return CGRect(x: v.minX + w3, y: v.minY, width: v.width - w3, height: v.height)
        case .maximize: return v
        }
    }
}

enum Bento {
    /// Bento.dc.html: the first (most recently focused) window takes the left column,
    /// the rest fill an even two-row grid on the right. 6 pt gaps and 6 pt outer margin.
    static func tiles(count n: Int, in visible: CGRect, gap g: CGFloat = 6) -> [CGRect] {
        guard n > 0 else { return [] }
        let r = visible.insetBy(dx: g, dy: g)
        if n == 1 { return [r] }
        if n == 2 {
            let w = (r.width - g) / 2
            return [CGRect(x: r.minX, y: r.minY, width: w, height: r.height),
                    CGRect(x: r.minX + w + g, y: r.minY, width: w, height: r.height)]
        }
        let rest = n - 1
        let restCols = (rest + 1) / 2
        let cols = CGFloat(1 + restCols)
        let colW = (r.width - g * (cols - 1)) / cols
        let rowH = (r.height - g) / 2
        var out = [CGRect(x: r.minX, y: r.minY, width: colW, height: r.height)]
        for i in 0..<rest {
            let row = i / restCols, col = i % restCols
            let x = r.minX + CGFloat(col + 1) * (colW + g)
            // The design doesn't draw an odd count: the last tile of a short second row stretches to the right edge.
            let last = i == rest - 1 && row == 1
            let w = last ? r.maxX - x : colW
            out.append(CGRect(x: x, y: r.minY + CGFloat(row) * (rowH + g), width: w, height: rowH))
        }
        return out
    }

    /// The same tiles, made to fit windows that can't go smaller than `mins` (by index; nil for no limit). The
    /// even grid when everything fits it; otherwise the same shape, with room taken from tiles that can spare it.
    static func tiles(count n: Int, in visible: CGRect, gap g: CGFloat = 6, mins: [CGSize?]) -> [CGRect] {
        let even = tiles(count: n, in: visible, gap: g)
        let fits = zip(even, mins).allSatisfy { t, m in m.map { $0.width <= t.width + 1 && $0.height <= t.height + 1 } ?? true }
        guard !fits, n > 1 else { return even }
        let key = { (i: Int) in DockNode.window(String(i)) }
        let root: DockNode
        if n == 2 {
            root = .split(.h, [key(0), key(1)])
        } else {
            // Left column, then a top row of `cols` tiles over a bottom row whose last tile takes what's left.
            let rest = n - 1, cols = (rest + 1) / 2, bottom = rest - cols
            let top = DockNode.split(.h, (0..<cols).map { key(1 + $0) })
            var bottomWeights = Array(repeating: 1.0, count: bottom)
            bottomWeights[bottom - 1] += Double(cols - bottom)
            let low = DockNode.split(.h, (0..<bottom).map { key(1 + cols + $0) }, weights: bottomWeights)
            root = .split(.h, [key(0), .split(.v, [top, low])], weights: [1, Double(cols)])
        }
        var limits: [String: CGSize] = [:]
        for (i, m) in mins.enumerated() { if let m { limits[String(i)] = m } }
        let frames = root.solve(in: visible.insetBy(dx: g, dy: g), gap: g, mins: limits).frames
        return (0..<n).map { frames[String($0)] ?? even[$0] }
    }
}

/// Snap Wheel geometry from the component sheet, in the wheel panel's flipped coordinates.
enum WheelGeometry {
    static let panelSize = CGSize(width: 420, height: 460)
    static let center = CGPoint(x: 210, y: 210)
    static let cancelRadius: CGFloat = 32
    static let inner: (r0: CGFloat, r1: CGFloat) = (40, 88)
    static let outer: (r0: CGFloat, r1: CGFloat) = (94, 146)
    static let innerGlyphRadius: CGFloat = 64
    static let outerGlyphRadius: CGFloat = 120

    struct Arc: Equatable {
        let parent: Int
        let count: Int
        let step: CGFloat  // degrees per item
        let r0: CGFloat, r1: CGFloat
        static func layouts(_ parent: Int) -> Arc { Arc(parent: parent, count: 9, step: 15, r0: 154, r1: 196) }
        static func three(_ parent: Int) -> Arc { Arc(parent: parent, count: 3, step: 30, r0: 154, r1: 206) }
        /// One segment per Window Mode.
        static func modes(_ parent: Int) -> Arc { Arc(parent: parent, count: WindowMode.allCases.count, step: 26, r0: 154, r1: 206) }

        func angle(_ i: Int) -> CGFloat {
            WheelGeometry.angle(parent) + rad((CGFloat(i) - CGFloat(count - 1) / 2) * step)
        }
    }

    enum Hit: Equatable { case none, cancel, inner(Int), outer(Int), arc(Int) }

    static func rad(_ deg: CGFloat) -> CGFloat { deg * .pi / 180 }
    /// Slot i is centred at −90° + 45°·i, clockwise from the top (y points down).
    static func angle(_ i: Int) -> CGFloat { rad(-90 + 45 * CGFloat(i)) }

    static func point(_ r: CGFloat, _ a: CGFloat) -> CGPoint {
        CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
    }

    /// A ring segment with a constant 2 pt gap: 1 pt per side, converted to an angle at each radius.
    static func sector(_ r0: CGFloat, _ r1: CGFloat, _ a0: CGFloat, _ a1: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.addArc(center: center, radius: r1, startAngle: a0 + 1 / r1, endAngle: a1 - 1 / r1, clockwise: false)
        p.addArc(center: center, radius: r0, startAngle: a1 - 1 / r0, endAngle: a0 + 1 / r0, clockwise: true)
        p.closeSubpath()
        return p
    }

    static func slotSector(_ i: Int, _ ring: (r0: CGFloat, r1: CGFloat)) -> CGPath {
        let c = angle(i)
        return sector(ring.r0, ring.r1, c - rad(22.5), c + rad(22.5))
    }

    static func hit(_ p: CGPoint, arc: Arc?) -> Hit {
        let dx = p.x - center.x, dy = p.y - center.y
        let r = hypot(dx, dy)
        var deg = atan2(dy, dx) * 180 / .pi + 90 + 22.5  // 0 at the start of slot 0
        deg = deg.truncatingRemainder(dividingBy: 360)
        if deg < 0 { deg += 360 }
        let slot = Int(deg / 45) % 8
        if let arc, r >= arc.r0 - 4, r <= arc.r1 + 8 {
            let a = atan2(dy, dx)
            for i in 0..<arc.count {
                var d = a - arc.angle(i)
                d = atan2(sin(d), cos(d))
                if abs(d) <= rad(arc.step / 2) { return .arc(i) }
            }
        }
        switch r {
        case ..<inner.r0: return .cancel
        case ..<((inner.r1 + outer.r0) / 2): return .inner(slot)
        case ..<(outer.r1 + 4): return .outer(slot)
        default: return .none
        }
    }
}
