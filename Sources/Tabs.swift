import SwiftUI
import UniformTypeIdentifiers

/// One display's tab groups in one layout: one group, or two side by side. Window keys, left to right.
struct TabGroups: Codable, Equatable {
    var groups: [[String]] = [[]]
    var active: [String?] = [nil]
    /// The group holding the focused window; only its active tab gets the accent underline.
    var focus = 0
}

/// Tabs.dc.html: windows from any app share a pane under a 30 pt strip. The active tab's window fills the pane;
/// the others are parked until their tab is chosen.
final class TabsController {
    static let stripHeight: CGFloat = 30

    private let engine: Engine
    private var strips: [String: StripPanel] = [:]
    private var edge: EdgePanel?
    private var dragging: String?

    init(engine: Engine) { self.engine = engine }

    private func key(_ s: NSScreen, layout: Int? = nil) -> String { "\(layout ?? engine.state.current)|\(s.uuid)" }

    private func state(_ s: NSScreen) -> TabGroups { engine.state.tabs[key(s)] ?? TabGroups() }

    private func save(_ tg: TabGroups, _ s: NSScreen) { engine.store.update { $0.tabs[self.key(s)] = tg } }

    /// Windows in tab groups of the current layout that aren't the active tab: switching layouts leaves them parked.
    func isInactiveTab(_ windowKey: String) -> Bool {
        NSScreen.screens.contains { s in
            guard engine.mode(of: s) == .tabs else { return false }
            let tg = state(s)
            return tg.groups.indices.contains { tg.groups[$0].contains(windowKey) && tg.active[$0] != windowKey }
        }
    }

    // MARK: Layout

    /// (strip, pane) for each group, in AX coordinates.
    func rects(_ s: NSScreen, groups n: Int) -> [(strip: CGRect, pane: CGRect)] {
        let v = s.axUsableFrame
        let h = Self.stripHeight
        guard n == 2 else { return [(CGRect(x: v.minX, y: v.minY, width: v.width, height: h), CGRect(x: v.minX, y: v.minY + h, width: v.width, height: v.height - h))] }
        let w = ((v.width - 1) / 2).rounded(.down)
        let right = v.minX + w + 1  // 1 pt divider
        return [(CGRect(x: v.minX, y: v.minY, width: w, height: h), CGRect(x: v.minX, y: v.minY + h, width: w, height: v.height - h)),
                (CGRect(x: right, y: v.minY, width: v.maxX - right, height: h), CGRect(x: right, y: v.minY + h, width: v.maxX - right, height: v.height - h))]
    }

    /// The display a window belongs to: where it is, or where it returns to if parked.
    private func screen(of w: Win) -> NSScreen? {
        guard let f = w.frame else { return nil }
        return NSScreen.containing(ax: engine.isParked(f) ? engine.state.saved[w.key] ?? f : f)
    }

    func applyAll() {
        applyDock()
        var shown = Set<String>()
        for s in NSScreen.screens where engine.mode(of: s) == .tabs {
            apply(s)
            shown.insert(s.uuid)
        }
        for (k, p) in strips where !k.hasPrefix("dock|") && !shown.contains(String(k.split(separator: "#")[0])) { p.orderOut(nil) }
        // A display that just left Tabs mode: the windows behind other tabs come back, stacked in the pane.
        for s in NSScreen.screens where !shown.contains(s.uuid) {
            let keys = Set(state(s).groups.joined())
            guard !keys.isEmpty else { continue }
            // Not those Dock mode keeps out of sight (a tab behind another, zoomed past, too small for its tile).
            for w in AX.windows() where keys.contains(w.key) && !engine.live.dockHidden.contains(w.key) {
                if let f = w.frame, engine.isParked(f), let back = engine.state.saved[w.key] { w.setFrame(back) }
            }
            engine.store.update { $0.tabs[self.key(s)] = nil }
        }
    }

    /// Syncs the groups with the windows on the display, places the active tabs and parks the rest.
    func apply(_ s: NSScreen, focusActive: Bool = false) {
        let current = engine.state.current
        let wins = AX.windows().filter { w in
            (engine.state.assignment[w.key] ?? current) == current && screen(of: w) == s && !(w.frame.map(engine.isPinned) ?? false)
        }
        let byKey = Dictionary(wins.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        known.merge(byKey) { _, new in new }
        var tg = state(s)
        tg.groups = tg.groups.map { $0.filter { byKey[$0] != nil } }
        let known = Set(tg.groups.joined())
        for w in wins where !known.contains(w.key) {
            tg.groups[min(tg.focus, tg.groups.count - 1)].append(w.key)
            tg.active[min(tg.focus, tg.groups.count - 1)] = w.key
        }
        if tg.groups.count == 2, tg.groups.contains(where: \.isEmpty) {
            tg = TabGroups(groups: [tg.groups.joined().map { $0 }], active: [tg.active.compactMap { $0 }.first], focus: 0)
        }
        while tg.active.count < tg.groups.count { tg.active.append(nil) }
        for g in tg.groups.indices where tg.active[g].map({ !tg.groups[g].contains($0) }) ?? true { tg.active[g] = tg.groups[g].first }
        tg.focus = min(tg.focus, tg.groups.count - 1)
        save(tg, s)

        let r = rects(s, groups: tg.groups.count)
        for g in tg.groups.indices {
            for k in tg.groups[g] {
                guard let w = byKey[k], let f = w.frame else { continue }
                if k == tg.active[g] {
                    place(w, f, in: r[g].pane)
                } else if engine.isParked(f) {
                    engine.store.update { $0.saved[k] = r[g].pane }
                } else {
                    engine.park(w, frame: r[g].pane)
                }
            }
            showStrip(s, group: g, rect: r[g].strip, tg: tg, wins: byKey)
        }
        for (k, p) in strips where k.hasPrefix(s.uuid + "#") && Int(k.split(separator: "#")[1])! >= tg.groups.count { p.orderOut(nil) }
        if focusActive, let k = tg.active[tg.focus], let w = byKey[k] { w.focus() }
    }

    /// The pane each showing tab was last asked to fill, and the frame its app answered with.
    private var asked: [String: (pane: CGRect, answer: CGRect?)] = [:]

    /// Puts the showing tab in its pane, once: some apps keep their own height or position (Claude and Edge stay
    /// full height), and asking again on every refresh made them jump back and forth.
    private func place(_ w: Win, _ f: CGRect, in pane: CGRect) {
        guard f != pane else { asked[w.key] = nil; return }
        if let a = asked[w.key], a.pane == pane {
            if a.answer == nil { asked[w.key]?.answer = f }  // its answer: leave it there
            if asked[w.key]?.answer == f { return }
        }
        asked[w.key] = (pane, nil)
        w.setFrame(pane)
    }

    private func showStrip(_ s: NSScreen, group g: Int, rect: CGRect, tg: TabGroups, wins: [String: Win]) {
        let id = "\(s.uuid)#\(g)"
        let panel = strips[id] ?? StripPanel(controller: self)
        strips[id] = panel
        panel.update(screen: s, group: g, dock: false, prefs: engine.state.prefs, active: tg.active[g], focused: g == tg.focus,
                     tabs: tg.groups[g].compactMap { k in wins[k].map { StripModel.Tab(id: k, title: $0.title, icon: $0.icon) } },
                     frame: NSScreen.appKit(rect))
        if !tucked.contains(id) { panel.orderFrontRegardless() }
    }

    // MARK: Tab groups in Dock mode

    /// Strips over the Dock trees' tab groups. The group's frame starts below its strip (Engine.place leaves room).
    func applyDock() {
        var ids = Set<String>()
        let wins = Dictionary(AX.windows().map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        known.merge(wins) { _, new in new }
        let focused = AX.focusedWindow()?.key
        for g in engine.dockGroups() {
            let id = "dock|\(g.keys.first ?? "")"
            ids.insert(id)
            let panel = strips[id] ?? StripPanel(controller: self)
            strips[id] = panel
            let strip = CGRect(x: g.frame.minX, y: g.frame.minY - Self.stripHeight, width: g.frame.width, height: Self.stripHeight)
            panel.update(screen: g.screen, group: panel.model.group, dock: true, prefs: engine.state.prefs, active: g.selected,
                         focused: focused.map(g.keys.contains) ?? false,
                         tabs: g.keys.compactMap { k in wins[k].map { StripModel.Tab(id: k, title: $0.title, icon: $0.icon) } },
                         frame: NSScreen.appKit(strip))
            if !tucked.contains(id) { panel.orderFrontRegardless() }
        }
        for (k, p) in strips where k.hasPrefix("dock|") && !ids.contains(k) { p.orderOut(nil); strips[k] = nil }
    }

    /// Strips hidden while their window is dragged ("Tuck the strip away while its window moves").
    private var tucked: Set<String> = []
    /// A grouped window whose title bar was just pressed: if the press becomes a drag, its strip tucks away.
    private var dragKey: String?

    func tuck(_ windowKey: String?) {
        guard engine.state.prefs.tuckStrips else { return }
        let ids = strips.filter { windowKey.map($0.value.model.tabs.map(\.id).contains) ?? false }.map(\.key)
        if windowKey == nil {
            for id in tucked { strips[id]?.orderFrontRegardless() }
            tucked = []
        } else {
            for id in ids { strips[id]?.orderOut(nil); tucked.insert(id) }
        }
    }

    /// Tabs-mode and Dock-mode groups alike: the keys in the group holding `windowKey`.
    func groupKeys(of windowKey: String) -> [String]? {
        strips.values.first { $0.model.tabs.contains { $0.id == windowKey } }?.model.tabs.map(\.id)
    }

    func minimize(_ windowKey: String) {
        guard let w = AX.windows().first(where: { $0.key == windowKey }) else { return }
        AXUIElementSetAttributeValue(w.el, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    /// Takes a tab out of its group: Dock mode puts it beside the group, Tabs mode gives it a pane of its own.
    func moveToNewWindow(_ windowKey: String, from model: StripModel) {
        if model.dock {
            for s in NSScreen.screens where engine.mode(of: s) == .dock && engine.dockLayout(s).root.path(of: windowKey) != nil {
                engine.updateDock(s) { $0.root.ungroup(windowKey) }
                engine.arrangeDock(s)
            }
            applyDock()
        } else if let s = model.screen {
            split(windowKey, on: s)
        }
    }

    /// The red, yellow and green buttons of a grouped window act on the whole group (⇧-click: just this tab;
    /// fn-click: macOS's own). Green on the tab shown takes it out of the group.
    func installGroupButtons() {
        var h = EventTap.Handler()
        h.down = { [weak self] p, e in
            guard let self else { return false }
            self.dragKey = nil
            // Cheap checks first: some group exists, and the click is on a window's buttons (its first 80 × 30 points).
            guard !self.strips.isEmpty, !e.fn, !self.onStrip(p), let hit = AX.hit(p), p.y - hit.bounds.minY < 30 else { return false }
            if self.engine.state.prefs.tuckStrips, self.groupKeys(of: String(hit.id)) != nil { self.dragKey = String(hit.id) }
            guard p.x - hit.bounds.minX < 80, let keys = self.groupKeys(of: String(hit.id)), keys.count > 1,
                  let w = AX.window(id: hit.id, pid: hit.pid) else { return false }
            let whole = self.engine.state.prefs.windowButtonsActOnGroup != e.shift
            let near: (String) -> Bool = { attr in w.button(attr)?.insetBy(dx: -2, dy: -2).contains(p) ?? false }
            if near(kAXCloseButtonAttribute) {
                guard whole else { return false }
                DispatchQueue.main.async { for k in keys { self.close(k) } }
                return true
            }
            if near(kAXMinimizeButtonAttribute) {
                guard whole else { return false }
                DispatchQueue.main.async { for k in keys { self.minimize(k) } }
                return true
            }
            if near(kAXFullScreenButtonAttribute) || near(kAXZoomButtonAttribute) {
                guard let model = self.strips.values.first(where: { $0.model.tabs.contains { $0.id == w.key } })?.model else { return false }
                DispatchQueue.main.async { self.moveToNewWindow(w.key, from: model) }
                return true
            }
            return false
        }
        h.dragged = { [weak self] _, _ in
            guard let self, let k = self.dragKey else { return false }
            self.dragKey = nil
            DispatchQueue.main.async { self.tuck(k) }
            return false
        }
        h.up = { [weak self] _, _ in
            if self?.tucked.isEmpty == false { DispatchQueue.main.async { self?.tuck(nil) } }
            return false
        }
        EventTap.shared.add("tabButtons", h)
    }

    /// A point (AX coordinates) on one of the strips showing: the strip takes that click, not a window under it.
    private func onStrip(_ p: CGPoint) -> Bool {
        let q = NSScreen.appKit(CGRect(origin: p, size: .zero)).origin
        return strips.values.contains { $0.isVisible && $0.frame.contains(q) }
    }

    // MARK: Actions from the strip

    func activate(_ windowKey: String, on s: NSScreen) {
        if engine.mode(of: s) == .dock {
            engine.selectTab(windowKey)
            AX.windows().first { $0.key == windowKey }?.focus()
            return applyDock()
        }
        var tg = state(s)
        guard let g = tg.groups.firstIndex(where: { $0.contains(windowKey) }) else { return }
        tg.active[g] = windowKey
        tg.focus = g
        save(tg, s)
        apply(s, focusActive: true)
    }

    /// A Dock click or ⌘Tab to an app whose window waits behind another tab brings that tab forward.
    func reveal(pid: pid_t) {
        let mine = AX.windows().filter { $0.pid == pid }
        let focused = AX.focusedWindow().flatMap { f in mine.first { $0.key == f.key } }
        for s in NSScreen.screens where engine.mode(of: s) == .tabs {
            let tg = state(s)
            if mine.contains(where: { w in tg.active.contains(w.key) }) { return }  // one of its tabs is already showing
            let candidates = [focused].compactMap { $0 } + mine
            guard let w = candidates.first(where: { w in tg.groups.contains { $0.contains(w.key) } }) else { continue }
            return activate(w.key, on: s)
        }
    }

    /// Windows seen at the last refresh, so a tab's × doesn't have to list every app's windows to find its own.
    private var known: [String: Win] = [:]

    func close(_ windowKey: String) {
        guard let w = known[windowKey] ?? AX.windows().first(where: { $0.key == windowKey }),
              let button: AXUIElement = AX.value(w.el, kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
        whenGone(w, tries: 10) { [weak self] in
            self?.known[windowKey] = nil
            self?.showNext(after: windowKey)
        }
    }

    /// Runs `then` once the window is really gone: a document with changes asks first, and its sheet must stay
    /// in view rather than be covered by the next tab.
    private func whenGone(_ w: Win, tries: Int, then: @escaping () -> Void) {
        if (AX.value(w.el, kAXRoleAttribute) as String?) == nil { return then() }
        guard tries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.whenGone(w, tries: tries - 1, then: then) }
    }

    /// The tab beside a closing one shows at once, rather than after macOS reports the close and every window is
    /// listed again. The usual refresh follows and finds it already in place.
    private func showNext(after windowKey: String) {
        for s in NSScreen.screens where engine.mode(of: s) == .tabs {
            var tg = state(s)
            guard let g = tg.groups.firstIndex(where: { $0.contains(windowKey) }), let i = tg.groups[g].firstIndex(of: windowKey) else { continue }
            tg.groups[g].remove(at: i)
            let showing = tg.active[g] == windowKey
            if showing { tg.active[g] = tg.groups[g].indices.contains(i) ? tg.groups[g][i] : tg.groups[g].last }
            save(tg, s)
            if showing, let k = tg.active[g], let w = known[k] { w.setFrame(rects(s, groups: tg.groups.count)[g].pane) }
            if let p = strips["\(s.uuid)#\(g)"] {
                p.model.tabs.removeAll { $0.id == windowKey }
                p.model.active = tg.active[g]
            }
            return
        }
    }

    /// Drag a tab onto the other group's strip.
    func move(_ windowKey: String, toGroup g: Int, on s: NSScreen) {
        var tg = state(s)
        guard tg.groups.indices.contains(g) else { return }
        for i in tg.groups.indices { tg.groups[i].removeAll { $0 == windowKey } }
        tg.groups[g].append(windowKey)
        tg.active[g] = windowKey
        tg.focus = g
        save(tg, s)
        hideEdge()
        apply(s, focusActive: true)
    }

    /// Drop a tab on the pane's right edge: it becomes a second group.
    func split(_ windowKey: String, on s: NSScreen) {
        var tg = state(s)
        guard tg.groups.count == 1, tg.groups[0].count > 1 else { return hideEdge() }
        tg.groups[0].removeAll { $0 == windowKey }
        tg.groups.append([windowKey])
        tg.active = [tg.groups[0].first, windowKey]
        tg.focus = 1
        save(tg, s)
        hideEdge()
        apply(s, focusActive: true)
    }

    /// ⌃Tab: next tab in the group that holds the focused window. Returns false if that window isn't in a tab group.
    func cycleFocusedGroup() -> Bool {
        guard let fw = AX.focusedWindow(), let s = screen(of: fw), engine.mode(of: s) == .tabs else { return false }
        let tg = state(s)
        guard let g = tg.groups.firstIndex(where: { $0.contains(fw.key) }), tg.groups[g].count > 1,
              let i = tg.groups[g].firstIndex(of: fw.key) else { return false }
        activate(tg.groups[g][(i + 1) % tg.groups[g].count], on: s)
        return true
    }

    /// Move window (⌃⌥⇧ and an arrow) in Tabs mode: the focused tab moves along its strip, left or up to go
    /// earlier, right or down later. False when the focused window isn't in a Tabs mode group.
    func shiftFocused(_ d: Heading) -> Bool {
        guard let fw = AX.focusedWindow(), let s = screen(of: fw), engine.mode(of: s) == .tabs else { return false }
        var tg = state(s)
        guard let g = tg.groups.firstIndex(where: { $0.contains(fw.key) }), let i = tg.groups[g].firstIndex(of: fw.key) else { return false }
        let j = i + (d == .left || d == .up ? -1 : 1)
        guard tg.groups[g].indices.contains(j) else { return true }  // already at that end
        tg.groups[g].swapAt(i, j)
        save(tg, s)
        apply(s)
        return true
    }

    /// Keeps the underline on the group holding the focused window.
    func focusChanged() {
        guard let fw = AX.focusedWindow(), let s = screen(of: fw), engine.mode(of: s) == .tabs else { return }
        var tg = state(s)
        guard let g = tg.groups.firstIndex(where: { $0.contains(fw.key) }), g != tg.focus else { return }
        tg.focus = g
        save(tg, s)
        for (id, p) in strips where id.hasPrefix(s.uuid + "#") { p.model.focused = p.model.group == g }
    }

    func began(dragging windowKey: String, on s: NSScreen) {
        dragging = windowKey
        guard state(s).groups.count == 1 else { return }
        let pane = rects(s, groups: 1)[0].pane
        let zone = CGRect(x: pane.maxX - 80, y: pane.minY, width: 80, height: pane.height)
        let e = edge ?? EdgePanel(controller: self)
        edge = e
        e.target = s
        e.setFrame(NSScreen.appKit(zone), display: true)
        e.orderFrontRegardless()
        // There is no drag-ended callback for a cancelled drag; the zone goes away on its own.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.hideEdge() }
    }

    func draggedKey() -> String? { dragging }

    private func hideEdge() {
        edge?.orderOut(nil)
        dragging = nil
    }

    func hideAll() {
        for p in strips.values { p.orderOut(nil) }
        hideEdge()
    }

    func setMode(_ s: NSScreen) {
        if engine.mode(of: s) == .tabs { apply(s) } else {
            for (k, p) in strips where k.hasPrefix(s.uuid + "#") { p.orderOut(nil) }
        }
    }
}

// MARK: - Strip

final class StripModel: ObservableObject {
    struct Tab: Identifiable, Equatable {
        let id: String
        let title: String
        let icon: NSImage?
        /// The icon is the app's and only changes with it; a fresh copy of it isn't a change.
        static func == (a: Tab, b: Tab) -> Bool { a.id == b.id && a.title == b.title }
    }

    @Published var tabs: [Tab] = []
    @Published var active: String?
    @Published var focused = false
    @Published var prefs = Prefs()
    var screen: NSScreen?
    var group = 0
    /// A group inside a Dock mode tree rather than a Tabs mode pane.
    var dock = false
}

final class StripPanel: NSPanel {
    let model = StripModel()

    init(controller: TabsController) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        contentView = NSHostingView(rootView: TabStripView(model: model, controller: controller))
    }

    override var canBecomeKey: Bool { false }

    /// Only what changed: every assignment redraws the strip, and a redraw between a press and its release loses
    /// the click (and flickers).
    func update(screen: NSScreen, group: Int, dock: Bool, prefs: Prefs, active: String?, focused: Bool, tabs: [StripModel.Tab], frame: NSRect) {
        let m = model
        if m.screen != screen { m.screen = screen }
        if m.group != group { m.group = group }
        if m.dock != dock { m.dock = dock }
        if m.prefs != prefs { m.prefs = prefs }
        if m.active != active { m.active = active }
        if m.focused != focused { m.focused = focused }
        if m.tabs != tabs { m.tabs = tabs }
        if self.frame != frame { setFrame(frame, display: true) }
    }
}

/// A transparent drop zone on the pane's right edge, shown while a tab is dragged, to split the pane.
final class EdgePanel: NSPanel {
    /// The display whose pane this zone splits.
    var target: NSScreen?

    init(controller: TabsController) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: EdgeZone(controller: controller, panel: self))
    }
}

private enum TC {
    private static func dyn(_ d: NSColor, _ l: NSColor) -> Color { Color(nsColor: NSColor(name: nil) { Theme.isDark($0) ? d : l }) }
    static let strip = dyn(Theme.hex(0x151517), Theme.hex(0xDCDCDF))
    static let win = dyn(Theme.hex(0x262628), Theme.hex(0xFFFFFF))
    static let fill = dyn(Theme.rgba(255, 255, 255, 0.07), Theme.rgba(0, 0, 0, 0.045))
    static let fill2 = dyn(Theme.rgba(255, 255, 255, 0.16), Theme.rgba(0, 0, 0, 0.10))
    static let hair = dyn(Theme.rgba(255, 255, 255, 0.10), Theme.rgba(0, 0, 0, 0.10))
    static let label = dyn(Theme.rgba(255, 255, 255, 0.92), Theme.rgba(0, 0, 0, 0.88))
    static let label2 = dyn(Theme.rgba(235, 235, 245, 0.64), Theme.rgba(60, 60, 67, 0.74))
    static let accent = dyn(Theme.hex(0x3FD3C2), Theme.hex(0x0B7A72))
}

/// `.strip`: 30 pt; tabs share the width equally, at least 120 pt each, then scroll.
private struct TabStripView: View {
    @ObservedObject var model: StripModel
    let controller: TabsController

    private var p: Prefs { model.prefs }

    var body: some View {
        GeometryReader { geo in
            let lights: CGFloat = p.tabStripLights ? 60 : 0
            let w = max(120, (geo.size.width - lights) / CGFloat(max(model.tabs.count, 1)))
            HStack(spacing: 0) {
                if p.tabStripLights { GroupLights(model: model, controller: controller).frame(width: lights) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CGFloat(p.tabSelectedChip ? p.tabChipMargin : 0)) {
                        ForEach(model.tabs) { t in
                            TabView_(tab: t, active: t.id == model.active, underline: t.id == model.active && model.focused, prefs: p,
                                     activate: { if let s = model.screen { controller.activate(t.id, on: s) } },
                                     close: { controller.close(t.id) },
                                     springOpen: {
                                         // A file or link held over a tab, not one of Bower's own tabs being moved.
                                         if controller.draggedKey() == nil, let s = model.screen { controller.activate(t.id, on: s) }
                                     })
                                .frame(width: w - CGFloat(p.tabSelectedChip ? p.tabChipMargin : 0))
                                .onDrag {
                                    if let s = model.screen { controller.began(dragging: t.id, on: s) }
                                    return NSItemProvider(object: t.id as NSString)
                                }
                                .contextMenu {
                                    Button("Close Tab") { controller.close(t.id) }
                                    Button("Minimize Tab") { controller.minimize(t.id) }
                                    Button("Move Tab to New Window") { controller.moveToNewWindow(t.id, from: model) }
                                }
                        }
                    }
                    .padding(.horizontal, CGFloat(p.tabSelectedChip ? p.tabInset : 0))
                    .padding(.vertical, CGFloat(p.tabSelectedChip ? p.tabInset : 0))
                }
            }
        }
        .frame(height: TabsController.stripHeight)
        .background(StripBackground(prefs: p, focused: model.focused))
        .overlay(alignment: .bottom) { TC.hair.frame(height: 1) }
        .onDrop(of: [.plainText], isTargeted: nil) { _ in
            guard let k = controller.draggedKey(), let s = model.screen, !model.tabs.contains(where: { $0.id == k }) else { return false }
            controller.move(k, toGroup: model.group, on: s)
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }
}

/// `.tab`: icon, title, close; active = window background; hover = fill; focused active = 2 pt accent underline.
private struct TabView_: View {
    let tab: StripModel.Tab
    let active: Bool
    let underline: Bool
    let prefs: Prefs
    let activate: () -> Void
    let close: () -> Void
    /// Something dragged from another app (a file, a link) held over the tab opens it, so it can be dropped inside.
    let springOpen: () -> Void
    @State private var hover = false
    @State private var dropOver = false
    @State private var spring: DispatchWorkItem?

    var body: some View {
        HStack(spacing: 6) {
            if prefs.tabCloseButtons, !prefs.tabCloseOnRight { CloseButton(action: close).opacity(hover || active ? 1 : 0) }
            Group {
                if let icon = tab.icon { Image(nsImage: icon).resizable() } else { TC.fill2 }
            }
            .frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 4))
            Text(tab.title).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(active ? TC.label : TC.label2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if prefs.tabCloseButtons, prefs.tabCloseOnRight { CloseButton(action: close).opacity(hover || active ? 1 : 0) }
        }
        .padding(.leading, CGFloat(prefs.tabPadding) + 2).padding(.trailing, CGFloat(prefs.tabPadding) - 2)
        .frame(maxHeight: .infinity)
        .background(active ? TC.win : hover ? TC.fill : .clear,
                    in: RoundedRectangle(cornerRadius: prefs.tabSelectedChip ? 6 : 0))
        .overlay(alignment: .trailing) { if !active && !prefs.tabSelectedChip { TC.hair.frame(width: 1) } }
        .overlay(alignment: .bottom) {
            if underline { RoundedRectangle(cornerRadius: 1).fill(TC.accent).frame(height: 2).padding(.horizontal, 8) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: activate)
        .onHover { hover = $0 }
        // Not plain text: that's how Bower's own tabs are dragged, and the strip takes those.
        .onDrop(of: [.fileURL, .url, .image, .pdf, .movie, .audio, .rtf, .html, .vCard, .emailMessage], isTargeted: $dropOver) { _ in false }
        .onChange(of: dropOver) { _, over in
            spring?.cancel()
            guard over, !active else { return }
            let work = DispatchWorkItem(block: springOpen)
            spring = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)  // as long as Finder's spring-loading
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(tab.title)
        .accessibilityAction(named: "Close tab", close)
    }
}

/// The strip's look (Settings › Appearance › Tabs): material, glass (the wallpaper, blurred, darker to the left and
/// lighter to the right) or solid; tinted with the accent; glass turns opaque when its group isn't focused.
private struct StripBackground: View {
    let prefs: Prefs
    let focused: Bool

    var body: some View {
        ZStack {
            switch prefs.tabStyle {
            case .material: VisualEffect(material: .headerView)
            case .glass:
                if prefs.tabGlassOpaqueWhenInactive && !focused { TC.strip } else {
                    VisualEffect(material: .hudWindow)
                    LinearGradient(colors: [.black.opacity(0.18), .white.opacity(0.06)], startPoint: .leading, endPoint: .trailing)
                }
            case .solid: TC.strip
            }
            TC.accent.opacity(prefs.tabTint * 0.5)
        }
    }
}

/// Red, yellow and green on the strip itself: close, minimise, or take out of the group the tab shown;
/// with "act on the whole group", every tab.
private struct GroupLights: View {
    @ObservedObject var model: StripModel
    let controller: TabsController

    var body: some View {
        HStack(spacing: 8) {
            light(Color(red: 1, green: 0.37, blue: 0.34), String(localized: "Close")) { act { controller.close($0) } }
            light(Color(red: 1, green: 0.74, blue: 0.18), String(localized: "Minimize")) { act { controller.minimize($0) } }
            light(Color(red: 0.16, green: 0.79, blue: 0.25), String(localized: "Take out of the group")) {
                if let a = model.active { controller.moveToNewWindow(a, from: model) }
            }
        }
    }

    private func act(_ f: (String) -> Void) {
        let keys = model.prefs.windowButtonsActOnGroup != NSEvent.modifierFlags.contains(.shift) ? model.tabs.map(\.id) : [model.active].compactMap { $0 }
        keys.forEach(f)
    }

    private func light(_ c: Color, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Circle().fill(c).frame(width: 12, height: 12) }
            .buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}

/// `.x`: 16 pt; pressed = filled square.
private struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Glyph(d: "M1 1l6 6M7 1 1 7", grid: 8, size: 8, width: 1.4)
        }
        .buttonStyle(CloseStyle())
        .accessibilityLabel("Close tab")
    }

    private struct CloseStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(configuration.isPressed ? TC.label : TC.label2)
                .frame(width: 16, height: 16)
                .background(configuration.isPressed ? TC.fill2 : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())  // the whole square takes the click, not just the cross's strokes
        }
    }
}

private struct EdgeZone: View {
    let controller: TabsController
    let panel: EdgePanel
    @State private var over = false

    var body: some View {
        Rectangle()
            .fill(over ? TC.accent.opacity(0.22) : Color.white.opacity(0.001))
            .overlay(alignment: .leading) { if over { TC.accent.frame(width: 2) } }
            .onDrop(of: [.plainText], isTargeted: $over) { _ in
                guard let k = controller.draggedKey(), let s = panel.target else { return false }
                controller.split(k, on: s)
                return true
            }
    }
}

// MARK: - ⌃Tab

/// A keyboard event tap for the "Next tab in group" shortcut, so it only acts when the focused window is in a
/// tab group and otherwise reaches the app (⌃Tab switches tabs in browsers too).
final class KeyTap {
    var combo: () -> Combo? = { nil }
    var handle: () -> Bool = { false }
    private var tap: CFMachPort?

    func start() {
        guard tap == nil else { return }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: { _, type, event, refcon in
            Unmanaged<KeyTap>.fromOpaque(refcon!).takeUnretainedValue().on(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func on(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let c = combo(), Int(event.getIntegerValueField(.keyboardEventKeycode)) == c.key,
              KeyNames.carbon(NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))) == c.mods,
              handle() else { return Unmanaged.passUnretained(event) }
        return nil
    }
}
