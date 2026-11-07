import AppKit

/// Points kept free along each edge of every display (Settings › Dock › Keep space free).
struct ReservedEdges: Equatable {
    var top = 0.0, bottom = 0.0, left = 0.0, right = 0.0
}

extension Prefs {
    var reserved: ReservedEdges { ReservedEdges(top: reserveTop, bottom: reserveBottom, left: reserveLeft, right: reserveRight) }
}

/// The part of a display Bower arranges into: the visible frame (menu bar and Dock left out), less the space kept free.
/// Dock mode, Bento, snapping, framing, the overview's desk and Tabs mode all go through `axUsableFrame`, so they agree.
/// Menus, panels and parking use the real screen instead.
enum UsableArea {
    /// AppDelegate points this at the settings; tests and diagnostics runs keep nothing free.
    static var reserved: () -> ReservedEdges = { ReservedEdges() }

    /// Never less than this much is left to arrange into, however much is kept free.
    static let minimum = CGSize(width: 320, height: 240)

    /// `visible` in AX coordinates (top-left origin), so `top` comes off `minY`.
    static func inset(_ visible: CGRect, by r: ReservedEdges) -> CGRect {
        guard r != ReservedEdges() else { return visible }
        func fit(_ a: Double, _ b: Double, room: CGFloat) -> (CGFloat, CGFloat) {
            let a = CGFloat(max(a, 0)), b = CGFloat(max(b, 0)), spare = max(room, 0)
            guard a + b > spare, a + b > 0 else { return (a, b) }
            return (a * spare / (a + b), b * spare / (a + b))
        }
        let (l, rt) = fit(r.left, r.right, room: visible.width - minimum.width)
        let (t, b) = fit(r.top, r.bottom, room: visible.height - minimum.height)
        return CGRect(x: visible.minX + l, y: visible.minY + t, width: visible.width - l - rt, height: visible.height - t - b).integral
    }
}

extension NSScreen {
    /// Where Bower arranges windows on this display, in AX coordinates. See `UsableArea`.
    var axUsableFrame: CGRect { UsableArea.inset(axVisibleFrame, by: UsableArea.reserved()) }
}
