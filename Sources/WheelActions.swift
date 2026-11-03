import AppKit

/// Everything an outer wheel slot can hold: the default eight plus SetWheel.dc.html's palette and the snap presets.
enum WheelAction: String, Codable, CaseIterable {
    case maximize, thirds, mode, layouts, send, retile, recipe, settings
    case center, almostMaximize, nextDisplay, restore, minimize, hideOthers
    case split, fourCorners, focusStack

    static let defaults: [WheelAction?] = [.maximize, .thirds, .mode, .layouts, .send, .retile, .recipe, .settings]

    var title: String {
        switch self {
        case .maximize: String(localized: "Maximize")
        case .thirds: String(localized: "Thirds")
        case .mode: String(localized: "Window Mode")
        case .layouts: String(localized: "Layouts")
        case .send: String(localized: "Send to Layout")
        case .retile: String(localized: "Retile")
        case .recipe: String(localized: "AI Recipe")
        case .settings: String(localized: "Settings")
        case .center: String(localized: "Center")
        case .almostMaximize: String(localized: "Almost Maximize")
        case .nextDisplay: String(localized: "Next Display")
        case .restore: String(localized: "Restore")
        case .minimize: String(localized: "Minimize")
        case .hideOthers: String(localized: "Hide Others")
        case .split: String(localized: "Split")
        case .fourCorners: String(localized: "Four Corners")
        case .focusStack: String(localized: "Focus + Stack")
        }
    }

    /// Palette label: arc actions carry a ▸, as in the design.
    var paletteTitle: String { hasArc ? "\(title) ▸" : title }

    /// The caption pill's key badge.
    var key: String {
        switch self {
        case .maximize: "⌃⌥↩"
        case .thirds: "⌃⌥D F G"
        case .layouts: "⌥1–9"
        case .send: "⇧⌥1–9"
        case .retile: "⌃⌥R"
        case .settings: "⌘,"
        default: ""
        }
    }

    var hasArc: Bool { self == .thirds || self == .mode || self == .layouts || self == .send }

    /// 16 pt icon paths from the component sheet and SetWheel.dc.html; presets drawn in the same style.
    var iconPath: String {
        switch self {
        case .maximize: Icon.maximize
        case .thirds: Icon.thirds
        case .mode: Icon.mode
        case .layouts: Icon.layouts
        case .send: Icon.send
        case .retile: "M13.25 2.25V5.5H10"  // plus the arc in `icon`
        case .recipe: Icon.recipe
        case .settings: Icon.settings
        case .center: "M2 3h12v10H2zM5.5 6h5v4h-5z"
        case .almostMaximize: "M2 3h12v10H2zM4 5h8v6H4z"
        case .nextDisplay: "M1.5 4h8v6h-8zM11 6.5h3.5M12.5 5l1.5 1.5-1.5 1.5"
        case .restore: "M3 2.5V5h2.5"  // plus the arc in `icon`
        case .minimize: "M3 12.5h10"
        case .hideOthers: "M2.5 13.5l11-11"  // plus the eye in `icon`
        case .split: "M2 3h12v10H2zM8 3v10"
        case .fourCorners: "M2 3h12v10H2zM8 3v10M2 8h12"
        case .focusStack: "M2 3h12v10H2zM10 3v10M10 8h4"
        }
    }

    /// The full icon, including the curves the path parser doesn't read (arcs and the eye).
    var icon: CGPath {
        let p = CGMutablePath()
        p.addPath(Icon.path(iconPath))
        switch self {
        case .retile:
            p.addArc(center: CGPoint(x: 8, y: 8), radius: 5.25, startAngle: 0, endAngle: -.pi / 4 + 2 * .pi, clockwise: false)
        case .restore:
            // "M3 8a5 5 0 1 0 1.5-3.6": from the left, round the bottom, ending top-left.
            p.move(to: CGPoint(x: 3, y: 8))
            p.addArc(center: CGPoint(x: 8, y: 8), radius: 5, startAngle: .pi, endAngle: .pi + 0.80, clockwise: true)
        case .hideOthers:
            // "M1.5 8s2.4-4.5 6.5-4.5S14.5 8 14.5 8s-2.4 4.5-6.5 4.5S1.5 8 1.5 8z"
            p.move(to: CGPoint(x: 1.5, y: 8))
            p.addCurve(to: CGPoint(x: 8, y: 3.5), control1: CGPoint(x: 1.5, y: 8), control2: CGPoint(x: 3.9, y: 3.5))
            p.addCurve(to: CGPoint(x: 14.5, y: 8), control1: CGPoint(x: 12.1, y: 3.5), control2: CGPoint(x: 14.5, y: 8))
            p.addCurve(to: CGPoint(x: 8, y: 12.5), control1: CGPoint(x: 14.5, y: 8), control2: CGPoint(x: 12.1, y: 12.5))
            p.addCurve(to: CGPoint(x: 1.5, y: 8), control1: CGPoint(x: 3.9, y: 12.5), control2: CGPoint(x: 1.5, y: 8))
        default:
            break
        }
        return p
    }
}

// MARK: - The actions themselves

extension Engine {
    /// Remembers where a window was before Bower moved it, for Restore.
    private static var before: [String: CGRect] = [:]

    func move(_ w: Win, to f: CGRect) {
        if let cur = w.frame { Self.before[w.key] = cur }
        w.setFrame(f)
    }

    func perform(_ a: WheelAction, on w: Win?, screen s: NSScreen?) {
        let visible = (w?.frame).flatMap { NSScreen.containing(ax: $0) }?.axVisibleFrame ?? s?.axVisibleFrame
        switch a {
        case .maximize: if let w { snap(w, .maximize) }
        case .retile: if let s { retile(s) }
        case .center:
            guard let w, let f = w.frame, let v = visible else { return }
            move(w, to: CGRect(x: v.midX - f.width / 2, y: v.midY - f.height / 2, width: min(f.width, v.width), height: min(f.height, v.height)))
        case .almostMaximize:
            // 90% of the visible frame, centred.
            guard let w, let v = visible else { return }
            move(w, to: v.insetBy(dx: v.width * 0.05, dy: v.height * 0.05).integral)
        case .nextDisplay:
            guard let w, let f = w.frame, let from = NSScreen.containing(ax: f), NSScreen.screens.count > 1,
                  let i = NSScreen.screens.firstIndex(of: from) else { return }
            let to = NSScreen.screens[(i + 1) % NSScreen.screens.count].axVisibleFrame, v = from.axVisibleFrame
            let sx = to.width / v.width, sy = to.height / v.height
            move(w, to: CGRect(x: to.minX + (f.minX - v.minX) * sx, y: to.minY + (f.minY - v.minY) * sy,
                               width: f.width * sx, height: f.height * sy).integral)
        case .restore:
            if let w, let f = Self.before[w.key] { move(w, to: f) }
        case .minimize:
            if let w { AXUIElementSetAttributeValue(w.el, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
        case .hideOthers:
            let keep = w?.pid ?? AX.frontApp()?.pid
            for (pid, app) in AX.apps() where pid != keep && pid != ProcessInfo.processInfo.processIdentifier {
                app.hide()
            }
        case .split, .fourCorners, .focusStack:
            if let s = (w?.frame).flatMap({ NSScreen.containing(ax: $0) }) ?? s { arrange(a, on: s) }
        case .thirds, .mode, .layouts, .send, .recipe, .settings:
            break  // arcs and windows are handled by the wheel
        }
    }

    /// The snap presets: the display's windows in this layout, front to back, laid out together.
    func arrange(_ preset: WheelAction, on s: NSScreen) {
        let order = AX.zOrder()
        let wins = AX.windows().filter { w in
            guard let f = w.frame, !isParked(f), NSScreen.containing(ax: f) == s else { return false }
            return (state.assignment[w.key] ?? state.current) == state.current
        }.sorted { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
        let v = s.axVisibleFrame
        var frames: [CGRect] = []
        switch preset {
        case .split: frames = [SnapAction.leftHalf, .rightHalf].map { $0.frame(in: v) }
        case .fourCorners: frames = [SnapAction.topLeft, .topRight, .bottomLeft, .bottomRight].map { $0.frame(in: v) }
        default:
            // Focus + Stack: the front window takes two thirds, the rest share the last third top to bottom.
            frames = [SnapAction.firstTwoThirds.frame(in: v)]
            let stack = SnapAction.lastThird.frame(in: v), n = max(wins.count - 1, 1)
            let h = (stack.height / CGFloat(n)).rounded(.down)
            for i in 0..<n { frames.append(CGRect(x: stack.minX, y: stack.minY + CGFloat(i) * h, width: stack.width, height: i == n - 1 ? stack.maxY - (stack.minY + CGFloat(i) * h) : h)) }
        }
        for (w, f) in zip(wins, frames) { move(w, to: f) }
    }

    func setWheelSlots(_ slots: [WheelAction?]) {
        store.update { $0.wheelSlots = slots }
        onChange()
    }
}
