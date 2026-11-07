import AppKit

/// What lasts only while Bower runs.
final class EngineLive {
    /// Docked windows kept parked on purpose: out of the zoomed part, a tab behind another, too small for their tile.
    var dockHidden: Set<String> = []
    /// Frames before "frame on its own" in the modes without a tree, so a second double-click puts them back.
    var framedFrom: [String: CGRect] = [:]
    var history = History<SavedView>()
    /// Last solved layout per display, for drags, gap handles and the overview.
    var solved: [String: DockNode.Solved] = [:]
    var collapsed: [String: CollapsedIcon] = [:]
    var resizeWork: DispatchWorkItem?
    /// Floating windows centred with ⌃⌥C keep their size instead of filling the Desktop's tile.
    var centredFloats: Set<String> = []
    var seamWork: DispatchWorkItem?
    /// Bento's tile order per "layout|display", once a window was moved there by keyboard; window keys.
    var bentoOrder: [String: [String]] = [:]
}

extension Engine {
    // MARK: Storage

    func dockKey(_ s: NSScreen, layout n: Int? = nil) -> String { "\(n ?? state.current)|\(s.uuid)" }

    func dockLayout(_ s: NSScreen) -> DockLayout { state.docks[dockKey(s)] ?? DockLayout() }

    func updateDock(_ s: NSScreen, _ change: (inout DockLayout) -> Void) {
        let k = dockKey(s)
        store.update { st in
            var d = st.docks[k] ?? DockLayout()
            change(&d)
            st.docks[k] = d
        }
    }

    func ignores(_ w: Win) -> Bool { w.bundleID.map(state.prefs.ignoredApps.contains) ?? false }

    /// The area windows are laid out in: the visible frame, less the gap round the edge.
    /// Each window's smallest size, as its app showed it, for the tree to make room.
    var dockMins: [String: CGSize] { state.records.compactMapValues { AppLimits.min[$0.bundleID] } }

    func dockRect(_ s: NSScreen) -> CGRect {
        let g = CGFloat(state.prefs.gap)
        return s.axUsableFrame.insetBy(dx: g, dy: g)
    }

    /// The current layout's windows that belong on display `s`, wherever they rest (parked ones by their saved frame).
    func dockWindows(on s: NSScreen) -> [Win] {
        let order = AX.zOrder()
        return AX.windows().filter { w in
            guard let f = w.frame, !isPinned(f), !ignores(w), (state.assignment[w.key] ?? state.current) == state.current else { return false }
            let r = isParked(f) ? state.saved[w.key] ?? f : f
            return NSScreen.containing(ax: r) == s
        }.sorted { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
    }

    /// Re-lays out a display in its mode: Bento's grid, or Dock's tree. Native leaves windows where they are.
    func arrange(_ s: NSScreen, toast: Bool = false) {
        guard arrangesHere else { return }
        switch mode(of: s) {
        case .bento: retile(s, toast: toast)
        case .dock: arrangeDock(s)
        default: live.solved[s.uuid] = nil
        }
        DockChrome.shared.refresh(self)
    }

    // MARK: Dock mode

    /// Brings the tree up to date with the windows on the display, then puts every window in its place.
    func arrangeDock(_ s: NSScreen) {
        let wins = dockWindows(on: s)
        let keys = Set(wins.map(\.key))
        let focused = AX.focusedWindow()?.key
        let rect = dockRect(s)
        let gap = CGFloat(state.prefs.gap)
        let hideKey = dockKey(s)
        updateDock(s) { d in
            let before = d.root.keys
            for k in before where !keys.contains(k) { d.root.remove(k, share: state.prefs.shareRemovedSpace) }
            d.floating = d.floating.intersection(keys)
            // A display new to Dock mode starts from an even grid, not each window halving the one before.
            if d.root.keys.isEmpty, wins.filter({ !d.floating.contains($0.key) }).count > 1 {
                d.root = .grid(wins.filter { !d.floating.contains($0.key) }.map(\.key))
            }
            for w in wins where !d.root.keys.contains(w.key) && !d.floating.contains(w.key) {
                let frames = d.root.solve(in: rect, gap: gap, mins: dockMins).frames
                let beside = DockNode.splitTarget(focused: focused.flatMap { frames[$0] != nil ? $0 : nil } ?? d.root.keys.last,
                                                  frames: frames, area: rect)
                d.root.add(w.key, beside: beside, frames: frames)
            }
            // The Desktop's tile: there while windows float on it, or when shown on purpose; never when hidden.
            let wantsDesktop = !state.prefs.desktopHidden.contains(hideKey)
                && (!d.floating.isEmpty || state.prefs.desktopShown.contains(hideKey))
            if wantsDesktop, !d.root.hasDesktop {
                d.root.insert(.desktop, at: .right, of: [])
            } else if !wantsDesktop, let p = d.root.desktopPath {
                d.root.removeNode(at: p, share: true)
            }
            if d.root.keys != before { d.zoom = nil }
            if let z = d.zoom, d.root[z] == nil { d.zoom = nil }
        }
        place(s, wins: wins)
    }

    /// Puts each window at its solved frame; windows outside the zoomed part, background tabs and windows too small
    /// for their tile are parked (the last shown as their app's icon).
    func place(_ s: NSScreen, wins: [Win]? = nil, animate: Bool = true) {
        let d = dockLayout(s)
        let wins = wins ?? dockWindows(on: s)
        let rect = dockRect(s), gap = CGFloat(state.prefs.gap)
        let full = d.root.solve(in: rect, gap: gap, mins: dockMins)
        let zoomed = d.zoom.flatMap { d.root[$0] }
        let shown = zoomed?.solve(in: rect, gap: gap, mins: dockMins) ?? full
        live.solved[s.uuid] = shown
        let behind = d.root.backgroundTabs
        var moves: [(Win, CGRect)] = []
        var hidden: Set<String> = []
        var icons: [String: CGRect] = [:]
        let floating = wins.filter { d.floating.contains($0.key) }
        for w in wins {
            if d.floating.contains(w.key) {
                if floating.count == 1, state.prefs.soleFloatTakesDesktop, !live.centredFloats.contains(w.key),
                   let dr = shown.desktop ?? full.desktop { moves.append((w, dr)) }
                continue
            }
            guard let f = shown.frames[w.key], !behind.contains(w.key) else {
                hidden.insert(w.key)
                if let cur = w.frame, !isParked(cur) { park(w, frame: shown.frames[w.key] ?? full.frames[w.key] ?? cur) }
                continue
            }
            if state.prefs.collapseSmall, !state.prefs.squeezeBelowMinimum, let m = w.minSize,
               m.width > f.width + 1 || m.height > f.height + 1 {
                hidden.insert(w.key)
                icons[w.key] = f
                if let cur = w.frame, !isParked(cur) { park(w, frame: f) }
                continue
            }
            // A tab group's window starts below its strip.
            let inGroup = d.root.tabGroups.contains { $0.keys.contains(w.key) }
            moves.append((w, inGroup ? CGRect(x: f.minX, y: f.minY + TabsController.stripHeight, width: f.width,
                                              height: f.height - TabsController.stripHeight) : f))
        }
        live.dockHidden = live.dockHidden.subtracting(wins.map(\.key)).union(hidden)
        Motion.shared.apply(moves, engine: self, animate: animate)
        CollapsedIcon.sync(icons, wins: wins, engine: self)
        DockChrome.shared.refresh(self)  // gap handles sit on the seams as they are now
        // Tab strips follow their groups. Not while a gap handle drags (no animation): that would be every mouse move.
        if animate { onWindowsChanged() }
    }

    /// Retile on a Dock display: every row and column shares its space evenly again.
    func rebalance(_ s: NSScreen) {
        updateDock(s) { d in d.root.evenOut() }
        arrangeDock(s)
        onHUD(String(localized: "Evened out."))
    }

    /// Display holding a window, by where it rests.
    func screen(of w: Win) -> NSScreen? {
        guard let f = w.frame else { return nil }
        return NSScreen.containing(ax: isParked(f) ? state.saved[w.key] ?? f : f)
    }

    func isDocked(_ w: Win) -> Bool {
        guard let s = screen(of: w), mode(of: s) == .dock else { return false }
        return dockLayout(s).root.path(of: w.key) != nil
    }

    // MARK: Floating

    /// The green button in Dock mode: a docked window floats on the Desktop, a floating one docks again.
    func toggleFloat(_ w: Win) {
        guard let s = screen(of: w), mode(of: s) == .dock else { return }
        let floating = dockLayout(s).floating.contains(w.key)
        updateDock(s) { d in
            if floating {
                d.floating.remove(w.key)
                live.centredFloats.remove(w.key)
            } else {
                d.root.remove(w.key, share: state.prefs.shareRemovedSpace)
                d.floating.insert(w.key)
            }
        }
        if !floating, state.prefs.hiddenDesktopReturns { setPrefs { $0.desktopHidden.remove(dockKey(s)) } }
        arrangeDock(s)
        if !floating, let dr = live.solved[s.uuid]?.desktop, dockLayout(s).floating.count > 1, let f = w.frame {
            // Floating windows live on the Desktop's tile.
            w.setFrame(CGRect(x: dr.midX - min(f.width, dr.width) / 2, y: dr.midY - min(f.height, dr.height) / 2,
                              width: min(f.width, dr.width), height: min(f.height, dr.height)))
        }
        onDid("float")
        onHUD(floating ? String(localized: "Docked. Its neighbours made room.") : String(localized: "Floating on the Desktop."))
    }

    func floatAll(_ s: NSScreen) {
        guard mode(of: s) == .dock else { return }
        updateDock(s) { d in
            d.floating.formUnion(d.root.keys)
            d.root = .split(.h, [])
        }
        arrangeDock(s)
    }

    // MARK: The Desktop's tile

    func desktopShown(_ s: NSScreen) -> Bool { live.solved[s.uuid]?.desktop != nil }

    /// A display leaving Dock mode: its expand step goes, and the windows Dock mode kept out of sight (expanded past,
    /// a tab behind another, too small for their tile) come back where they were, for the next mode to arrange.
    func leaveDock(display uuid: String, layout n: Int) {
        store.update { $0.docks["\(n)|\(uuid)"]?.zoom = nil }
        guard n == state.current, let s = NSScreen.screens.first(where: { $0.uuid == uuid }) else { return }
        let wins = dockWindows(on: s)
        for w in wins where live.dockHidden.contains(w.key) {
            if let f = w.frame, isParked(f), let back = state.saved[w.key] { w.setFrame(back) }
        }
        live.dockHidden.subtract(wins.map(\.key))
        CollapsedIcon.remove(wins.map(\.key), engine: self)
        live.solved[s.uuid] = nil
        DockChrome.shared.refresh(self)
    }

    /// Show or hide the Desktop's own tile on this display in this layout.
    func toggleDesktop(_ s: NSScreen) {
        let k = dockKey(s)
        let shown = desktopShown(s)
        setPrefs { p in
            if shown { p.desktopHidden.insert(k); p.desktopShown.remove(k) } else { p.desktopHidden.remove(k); p.desktopShown.insert(k) }
        }
        if mode(of: s) != .dock { setMode(.dock, for: s) } else { arrangeDock(s) }
    }

    // MARK: Zoom and framing

    /// The view right now, for history and saved views.
    func currentView(name: String = "") -> SavedView {
        var zoom: [String: [Int]] = [:]
        for s in NSScreen.screens { if let z = dockLayout(s).zoom { zoom[s.uuid] = z } }
        return SavedView(name: name, layout: state.current, zoom: zoom, focused: AX.focusedWindow()?.key)
    }

    /// Goes to a view: its layout, each display's zoomed part, its window.
    func show(_ v: SavedView, recordHistory: Bool = true) {
        if recordHistory { live.history.push(currentView()) }
        if v.layout != state.current { switchTo(v.layout) }
        for s in NSScreen.screens where mode(of: s) == .dock {
            updateDock(s) { $0.zoom = v.zoom[s.uuid] }
            place(s)
        }
        if let k = v.focused, let w = AX.windows().first(where: { $0.key == k }) { w.focus() }
        onChange()
    }

    private func setZoom(_ s: NSScreen, _ z: [Int]?) {
        live.history.push(currentView())
        updateDock(s) { $0.zoom = z }
        place(s)
        onChange()
    }

    /// Frame the focused window on its own; again to go back. Outside Dock mode it fills the screen and returns.
    func frameToggle(_ w: Win) {
        onDid("frame")
        if let s = screen(of: w), mode(of: s) == .dock, let p = dockLayout(s).root.path(of: w.key) {
            setZoom(s, dockLayout(s).zoom == p ? nil : p)
            onHUD(dockLayout(s).zoom == nil ? String(localized: "There and back.") : String(localized: "Framed on its own."))
            return
        }
        if let before = live.framedFrom.removeValue(forKey: w.key) {
            move(w, to: before)
        } else if let f = w.frame {
            live.framedFrom[w.key] = f
            snap(w, .maximize)
            onHUD(String(localized: "Framed on its own."))
        }
    }

    /// Out a level: the zoomed part's parent, up to the whole tree.
    func stepOut(_ s: NSScreen? = nil) {
        guard let s = s ?? focusedScreen else { return }
        guard mode(of: s) == .dock else {
            if let w = AX.focusedWindow(), live.framedFrom[w.key] != nil { frameToggle(w) }
            return
        }
        guard let z = dockLayout(s).zoom else { return }
        setZoom(s, z.isEmpty ? nil : Array(z.dropLast()).nilIfEmptyRoot)
        onHUD(dockLayout(s).zoom == nil ? String(localized: "All windows.") : String(localized: "Back a level."))
    }

    /// In a level, toward the focused window (or the one under the pointer).
    func stepIn(_ s: NSScreen? = nil) {
        guard let s = s ?? focusedScreen else { return }
        // Say why nothing moves, so a pinch never looks ignored.
        guard arrangesHere else {
            onHUD(String(localized: "Bower is off on this desktop. Turn it on in This Display › Use Bower on This Desktop."))
            return
        }
        let w = AX.focusedWindow()
        guard mode(of: s) == .dock else { if let w, live.framedFrom[w.key] == nil { frameToggle(w) }; return }
        let d = dockLayout(s)
        guard let k = w?.key ?? d.root.keys.first, let leaf = d.root.path(of: k) else {
            onHUD(String(localized: "No windows to expand."))
            return
        }
        let z = d.zoom ?? []
        guard leaf.count > z.count else { onHUD(String(localized: "Expanded all the way.")); return }
        setZoom(s, Array(leaf.prefix(z.count + 1)))
        onHUD(String(localized: "Expanded."))
    }

    /// Everything: the whole tree on every display, and the overview.
    func zoomOutAll() {
        live.history.push(currentView())
        for s in NSScreen.screens where mode(of: s) == .dock && dockLayout(s).zoom != nil {
            updateDock(s) { $0.zoom = nil }
            place(s)
        }
        onChange()
    }

    /// Zooms each Dock display to the smallest part holding every window inside `rect` (AX coordinates).
    func zoom(to rect: CGRect) {
        var expanded = false
        for s in NSScreen.screens where mode(of: s) == .dock && s.axFrame.intersects(rect) {
            let d = dockLayout(s)
            let solved = d.root.solve(in: dockRect(s), gap: CGFloat(state.prefs.gap), mins: dockMins)
            let inside = solved.frames.filter { rect.intersects($0.value) }.map(\.key)
            guard let first = inside.first, var p = d.root.path(of: first) else { continue }
            for k in inside.dropFirst() {
                guard let q = d.root.path(of: k) else { continue }
                p = Array(zip(p, q).prefix { $0 == $1 }.map(\.0))
            }
            setZoom(s, p.isEmpty ? nil : p)
            expanded = expanded || !p.isEmpty
        }
        onDid("marquee")
        onHUD(expanded ? String(localized: "Expanded to fit.") : String(localized: "That's every window. Drag around fewer to expand them."))
    }

    var focusedScreen: NSScreen? { AX.focusedWindow().flatMap(screen(of:)) ?? NSScreen.underMouse }

    /// To the neighbouring window: when zoomed to one window, the zoom moves along; past the edge, a window on the
    /// display that lies that way; past the last display sideways, the next or previous layout.
    func neighbour(_ dir: Direction) {
        guard let s = focusedScreen, mode(of: s) == .dock, let w = AX.focusedWindow() else { focusNeighbour(dir); return }
        let d = dockLayout(s)
        let all = d.root.solve(in: dockRect(s), gap: CGFloat(state.prefs.gap), mins: dockMins).frames
        guard let from = all[w.key] else { focusNeighbour(dir); return }
        guard let next = dockNeighbour(of: w.key, dir, frames: all, layout: d) else {
            if focusOtherDisplay(dir, from: from, on: s) { return }
            if dir == .left || dir == .right { step(dir == .right ? 1 : -1) }
            return
        }
        if let z = d.zoom, d.root[z]?.kind != .split, let p = d.root.path(of: next) { setZoom(s, p) }
        AX.windows().first { $0.key == next }?.focus()
        onHUD(String(localized: "Moved."))
    }

    /// The tile nearest `key`'s that way in a solved tree, leaving out tabs behind another.
    func dockNeighbour(of key: String, _ dir: Direction, frames all: [String: CGRect], layout d: DockLayout) -> String? {
        guard let from = all[key] else { return nil }
        let behind = d.root.backgroundTabs
        return Compass.nearest(from: from, all.filter { $0.key != key && !behind.contains($0.key) }.map { ($0.key, $0.value) }, dir)
    }

    // MARK: Changing the tree by hand

    /// Docks `w` at a drop target, from a drag. Returns the message to show.
    func drop(_ w: Win, at target: DropTarget, on s: NSScreen) {
        if mode(of: s) != .dock { setMode(.dock, for: s) }
        updateDock(s) { d in d = trial(d, key: w.key, target: target) }
        arrangeDock(s)
        if case .middle = target { onDid("group") } else { onDid("dock") }
        if case .middle = target { onHUD(String(localized: "Grouped. Click a tab to switch.")) } else { onHUD(String(localized: "Docked. Its neighbours made room.")) }
    }

    /// The tree as it would be with `key` dropped at `target`.
    func trial(_ d: DockLayout, key: String, target: DropTarget) -> DockLayout {
        var d = d
        d.floating.remove(key)
        d.root.remove(key, share: state.prefs.shareRemovedSpace)
        switch target {
        case .edge(let e, let other):
            if let p = d.root.path(of: other) { d.root.insert(.window(key), at: e, of: p) } else { d.root.add(key, beside: nil, frames: [:]) }
        case .screenEdge(let e):
            if d.root.kind == .split, d.root.children.isEmpty { d.root.add(key, beside: nil, frames: [:]) } else { d.root.insert(.window(key), at: e, of: []) }
        case .middle(let other):
            d.root.group(key, onto: other, share: state.prefs.shareRemovedSpace)
        }
        d.zoom = nil
        return d
    }

    /// A gap handle moved: the seam's split shares its space differently.
    func moveSeam(_ seam: DockNode.Seam, by delta: CGFloat, on s: NSScreen) {
        let prefix = dockLayout(s).zoom ?? []
        updateDock(s) { d in d.root.resize(prefix + seam.path, seam: seam.index, by: delta, length: seam.length) }
        place(s, animate: false)
        // Tab strips catch up once the seam stops moving.
        live.seamWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onWindowsChanged() }
        live.seamWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// A docked window resized by its own edge: the seams it touches follow, and its neighbours make room.
    func userResized(_ w: Win) {
        guard !AX.recentlyWrote(w.key), let s = screen(of: w), mode(of: s) == .dock,
              let solved = live.solved[s.uuid], let was = solved.frames[w.key], let now = w.frame else { return }
        let g = CGFloat(state.prefs.gap) + 2
        for seam in solved.seams {
            let r = seam.rect
            if seam.axis == .h, r.minY <= was.midY, r.maxY >= was.midY {
                if abs(r.minX - was.maxX) <= g, abs(now.maxX - was.maxX) > 1 { moveSeam(seam, by: now.maxX - was.maxX, on: s); return }
                if abs(r.maxX - was.minX) <= g, abs(now.minX - was.minX) > 1 { moveSeam(seam, by: now.minX - was.minX, on: s); return }
            }
            if seam.axis == .v, r.minX <= was.midX, r.maxX >= was.midX {
                if abs(r.minY - was.maxY) <= g, abs(now.maxY - was.maxY) > 1 { moveSeam(seam, by: now.maxY - was.maxY, on: s); return }
                if abs(r.maxY - was.minY) <= g, abs(now.minY - was.minY) > 1 { moveSeam(seam, by: now.minY - was.minY, on: s); return }
            }
        }
        place(s)  // an outer edge can't move: back into its tile
    }

    /// Tabs inside the tree: show this one, park the rest of its group.
    func selectTab(_ key: String) {
        for s in NSScreen.screens where mode(of: s) == .dock && dockLayout(s).root.path(of: key) != nil {
            updateDock(s) { $0.root.select(key) }
            place(s)
        }
    }

    /// The tab groups in the Dock trees on screen, for their strips: frame and window keys in tab order.
    func dockGroups() -> [(screen: NSScreen, frame: CGRect, keys: [String], selected: String)] {
        NSScreen.screens.filter { mode(of: $0) == .dock }.flatMap { s -> [(NSScreen, CGRect, [String], String)] in
            let d = dockLayout(s)
            guard let solved = live.solved[s.uuid] else { return [] }
            return d.root.tabGroups.compactMap { g in
                guard let sel = g.children[safe: g.selected]?.key, let f = solved.frames[sel] else { return nil }
                return (s, f, g.keys, sel)
            }
        }
    }

    /// Arrange: this display into Dock mode, every window tiled. All displays with `everywhere`.
    func arrangeIntoTiles(everywhere: Bool) {
        let screens = everywhere ? NSScreen.screens : [focusedScreen].compactMap { $0 }
        for s in screens {
            // Every window, floating or docked, into a fresh even grid.
            updateDock(s) { d in d.floating = []; d.root = .split(.h, []); d.zoom = nil }
            if mode(of: s) != .dock { setMode(.dock, for: s) } else { arrangeDock(s) }
        }
        onHUD(String(localized: "Arranged."))
    }

    /// Split the active tile with a new Finder window.
    func splitWithFinder() {
        if let s = focusedScreen, mode(of: s) != .dock { setMode(.dock, for: s) }
        let src = "tell application \"Finder\" to make new Finder window to home"
        NSAppleScript(source: src)?.executeAndReturnError(nil)
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
    }

    /// A window that came back to its place joins the tree where it can (beside the window it was next to is gone,
    /// so beside the focused one), which `arrangeDock` does on its own; nothing extra for now.
    func dockReturned(_ w: Win, _ r: WindowRecord) {}
}

extension DockNode {
    /// Keys of windows behind another tab of their group.
    var backgroundTabs: Set<String> {
        if kind == .tabs { return Set(children.enumerated().filter { $0.offset != selected }.compactMap(\.element.key)) }
        return children.reduce(into: Set<String>()) { $0.formUnion($1.backgroundTabs) }
    }

    var tabGroups: [DockNode] { kind == .tabs ? [self] : children.flatMap(\.tabGroups) }

    /// Every split shares its space evenly.
    mutating func evenOut() {
        if kind == .split, !children.isEmpty { weights = Array(repeating: 1 / Double(children.count), count: children.count) }
        for i in children.indices { children[i].evenOut() }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
    var nilIfEmptyRoot: Self? { isEmpty ? nil : self }
}

// MARK: - Drag to dock, the green button, double-click to frame

/// Watches title-bar drags on Dock displays and shows where the window will land; a pause over a target makes
/// room, letting go docks it. Also: the green button floats, a double-click on the title bar frames.
final class DockDrag {
    private unowned let engine: Engine
    private let preview = SnapPreview()
    private var candidate: (id: CGWindowID, pid: pid_t, start: CGPoint)?
    private var dragging: (win: Win, screen: NSScreen, original: DockLayout)?
    private var pending: (target: DropTarget?, since: Date)?
    private var active: DropTarget?
    private var holdWork: DispatchWorkItem?

    init(engine: Engine) { self.engine = engine }

    func install() {
        var h = EventTap.Handler()
        h.down = { [weak self] p, e in self?.down(p, e) ?? false }
        h.dragged = { [weak self] p, _ in self?.dragged(p); return false }
        h.up = { [weak self] p, _ in self?.up(p); return false }
        EventTap.shared.add("dock", h)
    }

    private func down(_ p: CGPoint, _ e: CGEvent) -> Bool {
        candidate = nil
        // Only clicks in a title bar on a Dock mode display matter; everything else passes at the cost of one lookup.
        guard let s = NSScreen.screens.first(where: { $0.axFrame.contains(p) }), engine.mode(of: s) == .dock,
              let hit = AX.hit(p), p.y - hit.bounds.minY < 30, engine.arrangesHere else { return false }
        let st = engine.state
        // The window buttons sit in the first 80 points of the title bar.
        if p.x - hit.bounds.minX < 80 {
            guard st.prefs.greenButtonFloats, !e.fn, !e.option, let w = AX.window(id: hit.id, pid: hit.pid), !engine.ignores(w),
                  let b = w.button(kAXFullScreenButtonAttribute) ?? w.button(kAXZoomButtonAttribute), b.insetBy(dx: -2, dy: -2).contains(p) else { return false }
            DispatchQueue.main.async { self.engine.toggleFloat(w) }
            return true
        }
        if e.clicks == 2, st.prefs.doubleClickFrames, !e.option, let w = AX.window(id: hit.id, pid: hit.pid), !engine.ignores(w) {
            DispatchQueue.main.async { self.engine.frameToggle(w) }
            return true
        }
        candidate = (hit.id, hit.pid, p)
        return false
    }

    private func dragged(_ p: CGPoint) {
        if dragging == nil {
            guard let c = candidate, hypot(p.x - c.start.x, p.y - c.start.y) > 6 else { return }
            candidate = nil  // one lookup per drag, not one per mouse move
            guard let w = AX.window(id: c.id, pid: c.pid), !engine.ignores(w), let s = engine.screen(of: w) else { return }
            dragging = (w, s, engine.dockLayout(s))
            candidate = nil
        }
        guard let (w, s, original) = dragging else { return }
        let target = target(at: p, dragging: w.key, on: s)
        if pending?.target != target {
            pending = (target, Date())
            holdWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.settle(target, w: w, s: s, original: original) }
            holdWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + engine.state.prefs.holdDelay, execute: work)
        }
    }

    /// The pointer stayed over one target long enough: show where the window lands, and make room.
    private func settle(_ target: DropTarget?, w: Win, s: NSScreen, original: DockLayout) {
        guard dragging?.win.key == w.key else { return }
        active = target
        let rect = engine.dockRect(s), gap = CGFloat(engine.state.prefs.gap)
        guard let target else {
            preview.hide()
            if !engine.state.prefs.keepPushed { reflow(original, except: w.key, s: s) }
            return
        }
        let t = engine.trial(original, key: w.key, target: target)
        let solved = t.root.solve(in: rect, gap: gap, mins: engine.dockMins)
        if engine.state.prefs.previewDrags, let f = solved.frames[w.key] { preview.show(f) }
        if engine.state.prefs.reflowWhileDragging { reflow(t, except: w.key, s: s) }
    }

    private func reflow(_ d: DockLayout, except key: String, s: NSScreen) {
        let solved = d.root.solve(in: engine.dockRect(s), gap: CGFloat(engine.state.prefs.gap), mins: engine.dockMins)
        let wins = engine.dockWindows(on: s).filter { $0.key != key }
        Motion.shared.apply(wins.compactMap { w in solved.frames[w.key].map { (w, $0) } }, engine: engine)
    }

    private func up(_ p: CGPoint) {
        holdWork?.cancel()
        candidate = nil
        defer { dragging = nil; pending = nil; active = nil; preview.hide() }
        guard let (w, s, _) = dragging else { return }
        // Letting go drops it on the target under the pointer at once, without waiting.
        let target = active ?? target(at: p, dragging: w.key, on: s)
        DispatchQueue.main.async {
            if let target { self.engine.drop(w, at: target, on: s) } else if self.engine.isDocked(w) { self.engine.arrangeDock(s) }
        }
    }

    private func target(at p: CGPoint, dragging key: String, on s: NSScreen) -> DropTarget? {
        guard let screen = NSScreen.screens.first(where: { $0.axFrame.contains(p) }) else { return nil }
        if let t = DropTarget.screen(screen.axVisibleFrame, at: p) { return t }
        guard screen == s, let solved = engine.live.solved[s.uuid] else { return nil }
        let behind = engine.dockLayout(s).root.backgroundTabs
        for (k, f) in solved.frames where k != key && !behind.contains(k) {
            if let t = DropTarget.over(k, frame: f, at: p) { return t }
        }
        return nil
    }
}

// MARK: - Gap handles, the dimmed background, icons for windows that don't fit

/// What Dock mode draws around the windows: gap handles to drag, the dimmed background behind them.
final class DockChrome {
    static let shared = DockChrome()
    private var handles: [GapHandle] = []
    private var dims: [String: NSPanel] = [:]

    func refresh(_ engine: Engine) {
        let p = engine.state.prefs
        var seams: [(NSScreen, DockNode.Seam)] = []
        for s in NSScreen.screens where engine.mode(of: s) == .dock && p.gapHandles {
            for seam in engine.live.solved[s.uuid]?.seams ?? [] { seams.append((s, seam)) }
        }
        while handles.count > seams.count { handles.removeLast().close() }
        while handles.count < seams.count { handles.append(GapHandle(engine: engine)) }
        for (h, (s, seam)) in zip(handles, seams) { h.show(seam, on: s, always: p.gapHandlesAlwaysShown) }

        for s in NSScreen.screens {
            let want = p.dimBehind && engine.mode(of: s) == .dock && engine.arrangesHere
            if want {
                let panel = dims[s.uuid] ?? makeDim()
                dims[s.uuid] = panel
                (panel.contentView as? NSVisualEffectView)?.alphaValue = 1
                panel.contentView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(p.dimOpacity).cgColor
                panel.setFrame(s.frame, display: true)
                panel.orderFrontRegardless()
            } else {
                dims.removeValue(forKey: s.uuid)?.orderOut(nil)
            }
        }
    }

    /// Just above the desktop icons, so it darkens and blurs the wallpaper behind every window.
    private func makeDim() -> NSPanel {
        let panel = OverlayPanel(level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1))
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        v.wantsLayer = true
        panel.contentView = v
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        return panel
    }
}

/// A gap between docked windows: drag it to resize both sides. Shows a grip on hover (or always).
final class GapHandle {
    private let panel: NSPanel
    private let view: GapHandleView
    private unowned let engine: Engine

    init(engine: Engine) {
        self.engine = engine
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        view = GapHandleView()
        panel.contentView = view
    }

    func show(_ seam: DockNode.Seam, on s: NSScreen, always: Bool) {
        // At least 8 points wide to grab, centred on the gap.
        let r = seam.axis == .h ? seam.rect.insetBy(dx: min(0, (seam.rect.width - 8) / 2), dy: 0)
                                : seam.rect.insetBy(dx: 0, dy: min(0, (seam.rect.height - 8) / 2))
        panel.setFrame(NSScreen.appKit(r), display: true)
        view.axis = seam.axis
        view.always = always
        view.onDrag = { [weak self] delta in self?.engine.moveSeam(seam, by: delta, on: s) }
        view.needsDisplay = true
        panel.orderFrontRegardless()
    }

    func close() { panel.orderOut(nil) }
}

private final class GapHandleView: NSView {
    var axis = DockAxis.h
    var always = false
    var onDrag: (CGFloat) -> Void = { _ in }
    private var hover = false
    private var last: NSPoint?

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { (axis == .h ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set() }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true; cursorUpdate(with: event) }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true; NSCursor.arrow.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { last = NSEvent.mouseLocation }

    override func mouseDragged(with event: NSEvent) {
        guard let l = last else { return }
        let p = NSEvent.mouseLocation
        // AppKit's y grows upward; the tree's (AX) grows downward.
        let d = axis == .h ? p.x - l.x : l.y - p.y
        guard abs(d) >= 1 else { return }
        last = p
        onDrag(d)
    }

    override func mouseUp(with event: NSEvent) { last = nil }

    override func draw(_ dirtyRect: NSRect) {
        guard hover || always else { return }
        let grip = axis == .h ? NSRect(x: bounds.midX - 2, y: bounds.midY - 20, width: 4, height: 40)
                              : NSRect(x: bounds.midX - 20, y: bounds.midY - 2, width: 40, height: 4)
        NSColor.controlAccentColor.withAlphaComponent(hover ? 0.9 : 0.35).setFill()
        NSBezierPath(roundedRect: grip, xRadius: 2, yRadius: 2).fill()
    }
}

/// A window too small for its app, shown as its icon in its tile until there's room; double-click to go in.
final class CollapsedIcon {
    private let panel: NSPanel
    private let key: String

    private init(key: String, icon: NSImage?, name: String, engine: Engine) {
        self.key = key
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .normal
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        let v = CollapsedView(icon: icon, name: name) { [weak engine] in
            guard let engine, let w = AX.windows().first(where: { $0.key == key }) else { return }
            engine.frameToggle(w)
        }
        panel.contentView = v
    }

    static func remove(_ keys: [String], engine: Engine) {
        for k in keys { engine.live.collapsed.removeValue(forKey: k)?.panel.orderOut(nil) }
    }

    static func sync(_ icons: [String: CGRect], wins: [Win], engine: Engine) {
        for (k, c) in engine.live.collapsed where icons[k] == nil { c.panel.orderOut(nil); engine.live.collapsed[k] = nil }
        for (k, r) in icons {
            let w = wins.first { $0.key == k }
            let c = engine.live.collapsed[k] ?? CollapsedIcon(key: k, icon: w?.icon, name: w?.appName ?? "", engine: engine)
            engine.live.collapsed[k] = c
            c.panel.setFrame(NSScreen.appKit(r), display: true)
            c.panel.orderFrontRegardless()
        }
    }
}

private final class CollapsedView: NSView {
    let icon: NSImage?
    let name: String
    let open: () -> Void

    init(icon: NSImage?, name: String, open: @escaping () -> Void) {
        self.icon = icon
        self.name = name
        self.open = open
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "\(name), too small to show. Double-click to open it on its own."))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { if event.clickCount == 2 { open() } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
        let side = min(64, bounds.width * 0.5, bounds.height * 0.5)
        icon?.draw(in: NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2 + 8, width: side, height: side))
        let s = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        s.draw(at: NSPoint(x: bounds.midX - s.size().width / 2, y: bounds.midY - side / 2 - 10))
    }
}
