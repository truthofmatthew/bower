import AppKit

/// Keyboard moves on the focused window: move it among its neighbours, step its width, centre it, put it back,
/// send it to the next display. Each does what fits the display's mode.
extension Engine {
    // MARK: Move window

    /// ⌃⌥⇧ and an arrow. Dock: trades places with the tile that way (every tile keeps its size); a tab moves along
    /// its group with up and down. Bento: trades tiles, and the order sticks. Native: trades frames with the
    /// nearest window that way. Tabs mode is handled by TabsController.shiftFocused.
    func moveWindow(_ dir: Direction) {
        guard let w = AX.focusedWindow(), let s = screen(of: w) else { return }
        switch mode(of: s) {
        case .dock:
            if isDocked(w) { moveDocked(w, dir, on: s) } else { onHUD(String(localized: "Floating windows stay where you put them.")) }
        case .bento: moveBento(w, dir, on: s)
        case .tabs: break
        case .native: moveNative(w, dir, on: s)
        }
    }

    private func moveDocked(_ w: Win, _ dir: Direction, on s: NSScreen) {
        let d = dockLayout(s)
        if dir == .up || dir == .down, let p = d.root.path(of: w.key), d.root[p]?.kind == .tabs {
            var root = d.root
            if root.moveTab(w.key, by: dir == .up ? -1 : 1) {
                updateDock(s) { $0.root = root }
                place(s)
                return onHUD(String(localized: "Moved."))
            }
        }
        let frames = d.root.solve(in: dockRect(s), gap: CGFloat(state.prefs.gap), mins: dockMins).frames
        guard let other = dockNeighbour(of: w.key, dir, frames: frames, layout: d) else {
            return onHUD(String(localized: "Nothing further that way."))
        }
        updateDock(s) { d in
            d.root.swap(w.key, other)
            // Expanded onto one window: keep showing the one that moved.
            if let z = d.zoom, d.root[z]?.kind != .split { d.zoom = d.root.path(of: w.key) }
        }
        place(s)
        onHUD(String(localized: "Moved."))
    }

    private func moveBento(_ w: Win, _ dir: Direction, on s: NSScreen) {
        let tiles = bentoTiles(bentoWindows(on: s), on: s)
        // Each tile's window is the one sitting in it now: bringing a window forward changes the front-to-back
        // order without moving anything, so that order can't say whose tile is whose.
        var left = bentoWindows(on: s)
        let wins = tiles.prefix(left.count).map { t -> Win in
            let i = left.indices.min { a, b in Bento.distance(left[a].frame, t) < Bento.distance(left[b].frame, t) }!
            return left.remove(at: i)
        }
        guard let i = wins.firstIndex(where: { $0.key == w.key }) else { return }
        let others = wins.indices.filter { $0 != i }.map { ($0, tiles[$0]) }
        guard let j = Compass.nearest(from: tiles[i], others, dir) else {
            return onHUD(String(localized: "Nothing further that way."))
        }
        var keys = wins.map(\.key)
        keys.swapAt(i, j)
        live.bentoOrder[dockKey(s)] = keys
        retile(s, toast: false)
        onHUD(String(localized: "Moved."))
    }

    private func moveNative(_ w: Win, _ dir: Direction, on s: NSScreen) {
        guard let from = w.frame else { return }
        let others = AX.windows().compactMap { o -> (Win, CGRect)? in
            guard o.key != w.key, let f = o.frame, !isParked(f), NSScreen.containing(ax: f) == s, !ignores(o),
                  (state.assignment[o.key] ?? state.current) == state.current else { return nil }
            return (o, f)
        }
        guard let o = Compass.nearest(from: from, others, dir), let to = o.frame else {
            return onHUD(String(localized: "Nothing further that way."))
        }
        Motion.shared.apply([(w, to), (o, from)], engine: self)
        onHUD(String(localized: "Moved."))
    }

    // MARK: Width

    /// ⌃⌥W wider, ⌃⌥⇧W narrower: ½, ⅔, 90% and the full width of the display. Dock: the window's column takes
    /// that share of its row, the others share the rest. Elsewhere the window takes that width, centred where it was.
    func cycleWidth(wider: Bool) {
        guard let w = AX.focusedWindow(), let s = screen(of: w) else { return }
        if mode(of: s) == .dock, isDocked(w) {
            let d = dockLayout(s)
            guard let current = d.root.columnShare(of: w.key) else {
                return onHUD(String(localized: "Nothing beside it to make room."))
            }
            guard let f = WidthCycle.next(from: current, wider: wider) else {
                return onHUD(wider ? String(localized: "As wide as it goes.") : String(localized: "As narrow as it goes."))
            }
            var root = d.root
            guard let got = root.setColumnShare(of: w.key, to: f, length: dockRect(s).width, mins: dockMins), abs(got - current) > 0.005 else {
                return onHUD(wider ? String(localized: "As wide as it goes.") : String(localized: "As narrow as it goes."))
            }
            updateDock(s) { $0.root = root }
            place(s)
            return onHUD(String(localized: "Width \(Int((got * 100).rounded()))%."))
        }
        guard let fr = w.frame else { return }
        let v = s.axUsableFrame
        guard let f = WidthCycle.next(from: Double(fr.width / v.width), wider: wider) else {
            return onHUD(wider ? String(localized: "As wide as it goes.") : String(localized: "As narrow as it goes."))
        }
        move(w, to: WidthCycle.frame(fr, width: (v.width * CGFloat(f)).rounded(), in: v))
        onHUD(String(localized: "Width \(Int((f * 100).rounded()))%."))
    }

    // MARK: Centre

    /// ⌃⌥C. A docked window floats onto the Desktop's tile, centred there, the way the green button floats it:
    /// moving it to the middle of the display would cover the tiles around it. Any other window moves to the middle
    /// of its display, keeping its size.
    func centre() {
        guard let w = AX.focusedWindow(), let s = screen(of: w) else { return }
        guard let f = w.frame else { return }
        // Dock mode keeps tiles clear: the window floats, at its size, in the middle of the Desktop's tile.
        if mode(of: s) == .dock {
            live.centredFloats.insert(w.key)
            if isDocked(w) { toggleFloat(w) }
            guard let dr = live.solved[s.uuid]?.desktop else { return }
            let size = CGSize(width: min(f.width, dr.width), height: min(f.height, dr.height))
            return move(w, to: CGRect(x: (dr.midX - size.width / 2).rounded(), y: (dr.midY - size.height / 2).rounded(),
                                      width: size.width, height: size.height))
        }
        move(w, to: WidthCycle.centred(f, in: s.axUsableFrame))
    }

    // MARK: Put back

    /// ⌃⌥B: windows go back to where Bower puts them, for apps that move or resize their own windows.
    func putBack() {
        guard let s = AX.focusedWindow().flatMap(screen(of:)) ?? focusedScreen else { return }
        switch mode(of: s) {
        case .dock, .bento: arrange(s)
        case .tabs: onWindowsChanged()  // Tabs mode places its panes again
        case .native: return onHUD(String(localized: "Bower doesn't place windows on this display."))
        }
        onHUD(String(localized: "Put back."))
    }

    // MARK: Next display

    /// ⌃⌥M: the focused window goes to the next display, in the same layout. Dock and Bento displays at both ends
    /// arrange again, so it leaves its tile and takes a new one.
    func sendToNextDisplay() {
        guard NSScreen.screens.count > 1 else { return onHUD(String(localized: "There's only one display.")) }
        guard let w = AX.focusedWindow(), let from = screen(of: w) else { return }
        perform(.nextDisplay, on: w, screen: from)
        guard let to = screen(of: w), to != from else { return }
        for sc in [from, to] where [.dock, .bento].contains(mode(of: sc)) { arrange(sc) }
        if mode(of: from) == .tabs || mode(of: to) == .tabs { onWindowsChanged() }
        w.focus()
    }
}
