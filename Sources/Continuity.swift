import AppKit

/// Workspaces (Workspaces.dc.html) and display recovery (the Offline shelf in SetDisplays.dc.html).
extension Engine {
    // MARK: Records

    /// A window's frame where it will next appear: its current frame, or the saved one while it's parked.
    private func restingFrame(_ w: Win) -> CGRect? {
        guard let f = w.frame else { return nil }
        return isParked(f) ? state.saved[w.key] ?? f : f
    }

    private func record(_ w: Win, frame: CGRect) -> WindowRecord? {
        guard let b = w.bundleID else { return nil }
        return WindowRecord(bundleID: b, title: w.title, layout: state.assignment[w.key] ?? state.current, frame: frame, key: w.key)
    }

    static func displayRecord(_ s: NSScreen) -> DisplayRecord {
        DisplayRecord(uuid: s.uuid, name: s.localizedName, size: s.frame.size)
    }

    // MARK: Workspaces

    /// "3 displays, 6 layouts and window positions for 14 apps": what a save would hold right now.
    func workspaceSummary() -> (displays: Int, layouts: Int, apps: Int) {
        let recs = currentRecords()
        return (NSScreen.screens.count, Set(recs.map(\.layout)).count, Set(recs.map(\.bundleID)).count)
    }

    private func currentRecords() -> [WindowRecord] {
        AX.windows().compactMap { w in
            guard let f = restingFrame(w), !isPinned(f) else { return nil }
            return record(w, frame: f)
        }
    }

    /// Saves every layout, Window Mode, route, pin and window position. Saving under an existing name updates it.
    func saveWorkspace(named name: String) {
        let ws = Workspace(name: name, saved: Date(), layouts: state.layouts, current: state.current,
                           displays: NSScreen.screens.map(Engine.displayRecord), windows: currentRecords(),
                           pinned: state.pinned, routes: state.routes)
        store.update { st in
            if let i = st.workspaces.firstIndex(where: { $0.name == name }) { st.workspaces[i] = ws } else { st.workspaces.append(ws) }
            st.currentWorkspace = name
        }
        onChange()
    }

    /// Puts each open window back in its saved layout and position. Windows the workspace doesn't know stay where they are.
    func loadWorkspace(named name: String) {
        guard let ws = state.workspaces.first(where: { $0.name == name }) else { return }
        store.update { st in
            st.layouts = ws.layouts
            st.pinned = ws.pinned
            st.routes = ws.routes
            st.currentWorkspace = name
            st.current = ws.current
        }
        for (w, r) in ws.windows.match(AX.windows()) {
            guard let f = w.frame else { continue }
            store.update { $0.assignment[w.key] = r.layout }
            if r.layout == ws.current || !state.hideOtherLayouts {
                w.setFrame(r.frame)
            } else if isParked(f) {
                store.update { $0.saved[w.key] = r.frame }
            } else {
                park(w, frame: r.frame)
            }
        }
        switchTo(ws.current)  // re-applies the layout: focus, Bento tiling, windows it didn't know
    }

    func deleteWorkspace(named name: String) {
        store.update { st in
            st.workspaces.removeAll { $0.name == name }
            if st.currentWorkspace == name { st.currentWorkspace = nil }
        }
        onChange()
    }

    // MARK: Displays

    /// Remembers which windows sit on which display, relative to its top-left. Runs every few seconds and before a switch.
    func snapshotDisplays() {
        let wins = AX.windows()
        var snap: [String: (display: DisplayRecord, windows: [WindowRecord])] = [:]
        for s in NSScreen.screens { snap[s.uuid] = (Engine.displayRecord(s), []) }
        for w in wins {
            guard let f = restingFrame(w), let s = NSScreen.containing(ax: f) else { continue }
            let rel = f.offsetBy(dx: -s.axFrame.minX, dy: -s.axFrame.minY)
            if let r = record(w, frame: rel) { snap[s.uuid]?.windows.append(r) }
        }
        // A display that just vanished keeps its last entry until displaysChanged has shelved it: the timer can
        // run between the unplug and macOS's notification.
        for (uuid, old) in displaySnapshot where snap[uuid] == nil && !state.shelf.contains(where: { $0.display.uuid == uuid }) {
            snap[uuid] = old
        }
        displaySnapshot = snap
        updateRecords(wins)
    }

    /// Called when displays connect or disconnect. A display that left goes on the shelf with its windows;
    /// a display that came back gets them returned.
    func displaysChanged() {
        let now = Set(NSScreen.screens.map(\.uuid))
        for (uuid, snap) in displaySnapshot where !now.contains(uuid) && !snap.windows.isEmpty {
            guard !state.shelf.contains(where: { $0.display.uuid == uuid }) else { continue }
            var modes: [Int: WindowMode] = [:]
            for (i, l) in state.layouts.enumerated() { if let m = l.modes[uuid] { modes[i] = m } }
            store.update { $0.shelf.append(ShelfEntry(display: snap.display, lastSeen: Date(), windows: snap.windows, modes: modes)) }
        }
        displaySnapshot = displaySnapshot.filter { now.contains($0.key) }
        // macOS rearranges windows for a while after a display change; let it finish before putting ours back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            for entry in state.shelf {
                if let s = NSScreen.screens.first(where: { $0.uuid == entry.display.uuid }) { restore(entry, onto: s) }
            }
            snapshotDisplays()
            onChange()
        }
        onChange()
    }

    /// Returns a shelved display's windows onto `screen`, scaled if it's a different size. "Move to…" uses the same path.
    func restore(_ entry: ShelfEntry, onto screen: NSScreen) {
        let target = screen.axFrame
        let sx = target.width / max(entry.display.size.width, 1), sy = target.height / max(entry.display.size.height, 1)
        for (w, r) in entry.windows.match(AX.windows()) {
            let f = CGRect(x: target.minX + r.frame.minX * sx, y: target.minY + r.frame.minY * sy,
                           width: r.frame.width * sx, height: r.frame.height * sy)
            let layout = state.assignment[w.key] ?? r.layout
            if layout == state.current || !state.hideOtherLayouts {
                w.setFrame(f)
            } else {
                store.update { $0.saved[w.key] = f }
            }
        }
        store.update { st in
            for (i, m) in entry.modes where i < st.layouts.count { st.layouts[i].modes[screen.uuid] = m }
            st.shelf.removeAll { $0.display.uuid == entry.display.uuid }
        }
        onChange()
    }

    func forget(_ entry: ShelfEntry) {
        store.update { $0.shelf.removeAll { $0.display.uuid == entry.display.uuid } }
        onChange()
    }
}
