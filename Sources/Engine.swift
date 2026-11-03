import AppKit

/// Layouts, instant switching, sending, snapping and Bento tiling.
///
/// Switching hides a window by parking it just off the bottom-right corner of a display, the way
/// AeroSpace does, so there is no Spaces animation and SIP stays on.
final class Engine {
    let store: Store
    var onChange: () -> Void = {}
    var onRetile: (_ count: Int, _ screen: NSScreen) -> Void = { _, _ in }

    /// Runs after windows open or close on the current layout; Tabs Mode uses it to keep its groups current.
    var onWindowsChanged: () -> Void = {}
    /// Runs when a shortcut or the keyboard preset changes, so hotkeys are registered again.
    var onShortcutsChanged: () -> Void = {}
    /// Tabs Mode: windows behind another tab stay parked when their layout is shown.
    var keepParked: (String) -> Bool = { _ in false }

    /// What was on each display at the last look, so a display that disconnects can be shelved.
    var displaySnapshot: [String: (display: DisplayRecord, windows: [WindowRecord])] = [:]

    init(store: Store) { self.store = store }

    var state: DeskState { store.state }

    // MARK: Parking

    /// shortcut: parks on the bottom-right-most unpinned display; a display placed further right or below
    /// it could show a sliver of parked windows. Pick a corner per display if that comes up.
    private var parkScreen: NSScreen? {
        NSScreen.screens.filter { !state.pinned.contains($0.uuid) }
            .max { $0.axFrame.maxX + $0.axFrame.maxY < $1.axFrame.maxX + $1.axFrame.maxY }
    }

    private func parkPoint() -> CGPoint? {
        guard let s = parkScreen?.axFrame else { return nil }
        return CGPoint(x: s.maxX - 1, y: s.maxY - 1)
    }

    /// macOS keeps a sliver of a pushed-off window on screen and clamps its y to keep the title bar reachable,
    /// so "parked" is "left edge within the last few points of a display", whatever the y.
    func isParked(_ f: CGRect) -> Bool {
        NSScreen.screens.contains { s in
            let r = s.axFrame
            return f.minX >= r.maxX - 40 && f.minX <= r.maxX && f.minY >= r.minY && f.minY <= r.maxY
        }
    }

    func park(_ w: Win, frame: CGRect) {
        guard let p = parkPoint() else { return }
        store.update { $0.saved[w.key] = frame }
        w.move(to: p)
    }

    private func unpark(_ w: Win) {
        if let f = state.saved[w.key] {
            w.setFrame(f)
        } else if let v = NSScreen.main?.axVisibleFrame, let f = w.frame {
            w.setFrame(CGRect(x: v.midX - f.width / 2, y: v.midY - f.height / 2, width: f.width, height: f.height))
        }
    }

    func isPinned(_ f: CGRect) -> Bool {
        guard !isParked(f), let s = NSScreen.containing(ax: f) else { return false }
        return state.pinned.contains(s.uuid)
    }

    /// The layout a window belongs to. A window seen for the first time joins its app's route,
    /// or the layout that was showing while it opened.
    private func layout(of w: Win, defaultingTo fallback: Int) -> Int {
        if let n = state.assignment[w.key] { return n }
        let n = w.bundleID.flatMap { state.routes[$0] } ?? fallback
        store.update { $0.assignment[w.key] = n }
        return n
    }

    // MARK: Layouts

    func windowCount(in n: Int) -> Int {
        AX.windows().filter { w in
            guard let f = w.frame, !isPinned(f) else { return false }
            return (state.assignment[w.key] ?? state.current) == n
        }.count
    }

    func switchTo(_ n: Int) {
        // Pressing the current layout again re-applies it, bringing back anything still parked.
        guard (0..<9).contains(n) else { return }
        let old = state.current
        let focused = AX.focusedWindow()
        let wins = AX.windows()
        var target: Win?
        store.update {
            if let focused, ($0.assignment[focused.key] ?? old) == old { $0.layouts[old].lastFocused = focused.key }
            $0.current = n
        }
        for w in wins {
            guard let f = w.frame, !isPinned(f) else { continue }
            let l = layout(of: w, defaultingTo: old)
            if l == n {
                if isParked(f) { if !keepParked(w.key) { unpark(w) } } else if !state.hideOtherLayouts { w.raise() }
                if w.key == state.layouts[n].lastFocused || target == nil { target = w }
            } else if state.hideOtherLayouts, !isParked(f) {
                park(w, frame: f)
            }
        }
        for s in NSScreen.screens where mode(of: s) == .bento { retile(s, toast: false) }
        onWindowsChanged()  // Tabs Mode places its panes and strips for the new layout
        if let target {
            target.focus()
        } else {
            // An empty layout: with nothing focusable here, macOS would jump to another Space (say, a
            // full-screen app), where the parked windows can't be listed to bring them back.
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
        }
        prune()
        lastSwitch = Date()
        onChange()
    }

    func cycle() { switchTo((state.current + 1) % 9) }

    /// When the last switch ran; the app it focuses activates right after, and that isn't the user picking it.
    private(set) var lastSwitch = Date.distantPast

    /// Clicking an app in the Dock (or ⌘Tab to it) shows the layout its windows are in, when none are in this one.
    func follow(pid: pid_t) {
        guard Date().timeIntervalSince(lastSwitch) > 0.6 else { return }
        let mine = AX.windows().filter { $0.pid == pid && $0.frame.map(isPinned) != true }
        guard !mine.contains(where: { layout(of: $0, defaultingTo: state.current) == state.current }) else { return }
        let w = AX.focusedWindow().flatMap { f in mine.first { $0.key == f.key } } ?? mine.first
        guard let w, let n = state.assignment[w.key] else { return }
        store.update { $0.layouts[n].lastFocused = w.key }
        switchTo(n)
    }

    /// ⌥N: the next layout after the current one that has no windows yet.
    func switchToEmptyLayout() {
        let used = Set(state.assignment.values)
        if let n = (1...8).map({ (state.current + $0) % 9 }).first(where: { !used.contains($0) }) { switchTo(n) }
    }

    enum Direction { case left, right, up, down }

    /// ⌘⌥J/L/I/K: focuses the nearest visible window in that direction, measured between centres.
    func focusNeighbour(_ d: Direction) {
        guard let from = AX.focusedWindow()?.frame else { return }
        let c = CGPoint(x: from.midX, y: from.midY)
        let candidates = AX.windows().compactMap { w -> (Win, CGFloat)? in
            guard let f = w.frame, !isParked(f), f != from else { return nil }
            let dx = f.midX - c.x, dy = f.midY - c.y
            let ahead: Bool
            switch d {
            case .left: ahead = dx < 0 && abs(dx) >= abs(dy)
            case .right: ahead = dx > 0 && abs(dx) >= abs(dy)
            case .up: ahead = dy < 0 && abs(dy) >= abs(dx)
            case .down: ahead = dy > 0 && abs(dy) >= abs(dx)
            }
            return ahead ? (w, hypot(dx, dy)) : nil
        }
        candidates.min { $0.1 < $1.1 }?.0.focus()
    }

    func setKeepEmptySpace(_ on: Bool) {
        store.update { $0.keepEmptySpace = on }
        for s in NSScreen.screens where mode(of: s) == .bento { retile(s, toast: false) }
        onChange()
    }

    func setTrackpadTapWheel(_ on: Bool) {
        store.update { $0.trackpadTapWheel = on }
        onChange()
    }

    func setSwipeLayouts(_ on: Bool) {
        store.update { $0.swipeLayouts = on }
        onChange()
    }

    func setKeepFullScreenHere(_ on: Bool) {
        store.update { $0.keepFullScreenHere = on }
        onChange()
    }

    /// Three-finger swipe: the next or previous layout in use (named, or holding windows). Stops at the ends, as desktops do.
    func step(_ d: Int) {
        let used = Set(state.assignment.values)
        let list = (0..<9).filter { !state.layouts[$0].isUntitled || used.contains($0) || $0 == state.current }
        guard let i = list.firstIndex(of: state.current), list.indices.contains(i + d) else { return }
        switchTo(list[i + d])
    }

    /// The windows layout `n` holds on screen `s`, at their resting frames: what the wheel's layout preview draws.
    func windows(in n: Int, on s: NSScreen) -> [(win: Win, frame: CGRect)] {
        AX.windows().compactMap { w in
            guard let f = w.frame, (state.assignment[w.key] ?? state.current) == n else { return nil }
            let r = isParked(f) ? state.saved[w.key] ?? f : f
            return NSScreen.containing(ax: r) == s ? (w, r) : nil
        }
    }

    /// The green button gives a window a full-screen desktop of its own, where no layout can hold it.
    /// With "keep full screen here" on, the window comes back and fills the screen in its layout instead.
    func catchFullScreen() {
        guard state.keepFullScreenHere, let (el, id) = AX.focusedFullScreenWindow() else { return }
        AXUIElementSetAttributeValue(el, "AXFullScreen" as CFString, kCFBooleanFalse)
        // The window can't be moved until the exit animation (about 0.7 s) lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, let w = AX.windows().first(where: { $0.id == id }) else { return }
            if let n = self.state.assignment[w.key], n != self.state.current { self.switchTo(n) }
            self.snap(w, .maximize)
        }
    }

    func setMiddleClickWheel(_ on: Bool) {
        store.update { $0.middleClickWheel = on }
        onChange()
    }

    func send(_ w: Win, to n: Int) {
        guard (0..<9).contains(n), let f = w.frame else { return }
        store.update { $0.assignment[w.key] = n }
        if n != state.current, state.hideOtherLayouts, !isParked(f) { park(w, frame: f) }
        onChange()
    }

    func sendFocused(to n: Int) {
        if let w = AX.focusedWindow() { send(w, to: n) }
    }

    func route(bundleID: String, to n: Int?) {
        store.update { $0.routes[bundleID] = n }
        guard let n else { return onChange() }
        for w in AX.windows() where w.bundleID == bundleID { send(w, to: n) }
    }

    func togglePin(_ s: NSScreen) {
        store.update { st in
            if st.pinned.contains(s.uuid) { st.pinned.remove(s.uuid) } else { st.pinned.insert(s.uuid) }
        }
        onChange()
    }

    /// Back to an unused layout: Untitled, Native everywhere. Its windows stay where they are.
    func clearLayout(_ n: Int) {
        store.update { $0.layouts[n].name = Layout.untitled; $0.layouts[n].modes = [:] }
        if n == state.current { onWindowsChanged() }  // Tabs Mode takes its strips down
        onChange()
    }

    func rename(_ n: Int, to name: String) {
        store.update { $0.layouts[n].name = name }
        onChange()
    }

    /// Forgets windows that no longer exist, so state.json doesn't grow forever. AX only lists the current
    /// Space's windows, so existence comes from the window server, which sees every Space.
    /// A window whose app quit (its process is gone) becomes an orphan record, so it can be put back when the app returns.
    /// A window closed while its app keeps running is simply forgotten: that close was on purpose.
    private func prune() {
        let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let keys = Set(info.compactMap { ($0[kCGWindowNumber as String] as? CGWindowID).map(String.init) })
        let livePIDs = Set(AX.apps().map(\.pid))
        store.update { st in
            let gone = st.records.filter { !keys.contains($0.key) }
            for (key, r) in gone {
                guard let layout = st.assignment[key], let pid = r.pid, !livePIDs.contains(pid) else { continue }
                // The record may be a few seconds old: take the window's current layout and resting frame.
                var orphan = r
                orphan.layout = layout
                if let f = st.saved[key] { orphan.frame = f }
                st.orphans.append(orphan)
            }
            st.orphans = Array(st.orphans.suffix(200))
            st.records = st.records.filter { keys.contains($0.key) }
            st.assignment = st.assignment.filter { keys.contains($0.key) }
            st.saved = st.saved.filter { keys.contains($0.key) }
        }
    }

    // MARK: Window events

    private var lastVisible: Set<String> = []

    /// Runs when any window opens or closes (WindowWatcher). New windows go to their app's route, or back to the
    /// layout and place they had before their app quit; Bento displays retile when what's on them changed.
    func windowsChanged() {
        prune()
        let wins = AX.windows()
        for w in wins where state.assignment[w.key] == nil {
            guard let f = w.frame, !isPinned(f) else { continue }
            if let i = orphanIndex(for: w) {
                let r = state.orphans[i]
                store.update { $0.orphans.remove(at: i); $0.assignment[w.key] = r.layout }
                if r.layout == state.current || !state.hideOtherLayouts { w.setFrame(r.frame) } else { park(w, frame: r.frame) }
            } else {
                let n = w.bundleID.flatMap { state.routes[$0] } ?? state.current
                store.update { $0.assignment[w.key] = n }
                if n != state.current, state.hideOtherLayouts, !isParked(f) { park(w, frame: f) }
            }
        }
        updateRecords(wins)
        let visible = Set(wins.filter { w in w.frame.map { !isParked($0) } ?? false }.map(\.key))
        if visible != lastVisible {
            lastVisible = visible
            for s in NSScreen.screens where mode(of: s) == .bento { retile(s) }
            onWindowsChanged()
        }
        onChange()
    }

    /// Same app and title first, then the same browser profile, then the same app.
    private func orphanIndex(for w: Win) -> Int? {
        guard let b = w.bundleID else { return nil }
        return state.orphans.lastIndex { $0.bundleID == b && $0.title == w.title }
            ?? state.orphans.lastIndex { sameProfile(w, $0) }
            ?? state.orphans.lastIndex { $0.bundleID == b }
    }

    /// Remembers each open window's app, title, layout, frame and display.
    func updateRecords(_ wins: [Win]) {
        var recs: [String: WindowRecord] = [:]
        for w in wins {
            guard let b = w.bundleID, let f = w.frame else { continue }
            let frame = isParked(f) ? state.saved[w.key] ?? f : f
            recs[w.key] = WindowRecord(bundleID: b, title: w.title, layout: state.assignment[w.key] ?? state.current,
                                       frame: frame, key: w.key, display: NSScreen.containing(ax: frame)?.uuid, pid: w.pid)
        }
        // Windows on other Spaces aren't listed; keep their last record.
        store.update { $0.records.merge(recs) { _, new in new } }
    }

    /// Brings every parked window back. Runs on quit so nothing is left off-screen without Bower.
    func unparkAll() {
        for w in AX.windows() {
            if let f = w.frame, isParked(f) { unpark(w) }
        }
    }

    /// On launch: windows parked by an earlier run that belong to the current layout, or to no layout, come back.
    func recover() {
        for w in AX.windows() {
            guard let f = w.frame, isParked(f) else { continue }
            let l = state.assignment[w.key]
            if (l == nil || l == state.current) && !keepParked(w.key) { unpark(w) }
        }
    }

    // MARK: Window Modes

    func mode(of s: NSScreen) -> WindowMode { state.layouts[state.current].modes[s.uuid] ?? .native }

    func setMode(_ m: WindowMode, for s: NSScreen) { setMode(m, display: s.uuid, layout: state.current) }

    func setMode(_ m: WindowMode, display uuid: String, layout n: Int) {
        store.update { $0.layouts[n].modes[uuid] = m }
        if m == .bento, n == state.current, let s = NSScreen.screens.first(where: { $0.uuid == uuid }) { retile(s, toast: true) }
        if n == state.current { onWindowsChanged() }
        onChange()
    }

    /// Moves a layout to a new position; window assignments, routes and the current layout follow it.
    func moveLayout(from a: Int, to b: Int) {
        guard a != b, (0..<9).contains(a), (0..<9).contains(b) else { return }
        var order = Array(0..<9)
        order.insert(order.remove(at: a), at: b)
        let newIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        store.update { st in
            st.layouts = order.map { st.layouts[$0] }
            st.current = newIndex[st.current]!
            st.assignment = st.assignment.mapValues { newIndex[$0]! }
            st.routes = st.routes.mapValues { newIndex[$0]! }
        }
        onChange()
    }

    func setAI(_ ai: AISettings) {
        store.update { $0.ai = ai }
        onChange()
    }

    func setStatusStyle(_ s: StatusStyle) {
        store.update { $0.statusStyle = s }
        onChange()
    }

    func setHideOtherLayouts(_ on: Bool) {
        store.update { $0.hideOtherLayouts = on }
        if !on { unparkAll() }
        onChange()
    }

    /// Windows on the current Space grouped by layout, front to back, for the Layouts Bar.
    /// Windows Bower hasn't assigned yet come back under `nil`.
    func windowsByLayout() -> [Int?: [Win]] {
        let order = AX.zOrder()
        let wins = AX.windows().filter { w in w.frame.map { !isPinned($0) } ?? false }
            .sorted { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
        return Dictionary(grouping: wins) { state.assignment[$0.key] }
    }

    func setModeForAllDisplays(_ m: WindowMode) {
        for s in NSScreen.screens { setMode(m, for: s) }
    }

    /// Bento tiling of one display: the most recently focused window takes the left column.
    func retile(_ s: NSScreen, toast: Bool = true) {
        let order = AX.zOrder()
        let wins = AX.windows().filter { w in
            guard let f = w.frame, !isParked(f), NSScreen.containing(ax: f) == s else { return false }
            return (state.assignment[w.key] ?? state.current) == state.current
        }.sorted { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
        // "Keep its space empty": windows of quit apps that lived here hold their tiles, at the end of the grid.
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let held = state.keepEmptySpace
            ? state.orphans.filter { $0.layout == state.current && $0.display == s.uuid && !running.contains($0.bundleID) }.count : 0
        for (w, f) in zip(wins, Bento.tiles(count: wins.count + held, in: s.axVisibleFrame)) { w.setFrame(f) }
        if toast, !wins.isEmpty { onRetile(wins.count, s) }
    }

    // MARK: Snapping

    func target(_ a: SnapAction, for w: Win) -> (frame: CGRect, screen: NSScreen)? {
        guard let f = w.frame, let s = NSScreen.containing(ax: f) else { return nil }
        return (a.frame(in: s.axVisibleFrame), s)
    }

    func snap(_ w: Win, _ a: SnapAction) {
        if let t = target(a, for: w) { move(w, to: t.frame) }
    }
}
