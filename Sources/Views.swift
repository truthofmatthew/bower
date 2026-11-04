import AppKit

/// Saved views, back and forward, missing windows, and commands by URL.
extension Engine {
    func goBack() {
        guard let v = live.history.goBack(from: currentView()) else { return NSSound.beep() }
        onDid("back")
        show(v, recordHistory: false)
    }

    func goForward() {
        guard let v = live.history.goForward(from: currentView()) else { return NSSound.beep() }
        show(v, recordHistory: false)
    }

    var canGoBack: Bool { !live.history.back.isEmpty }
    var canGoForward: Bool { !live.history.forward.isEmpty }

    /// Saves what you're looking at as view `n` (1–9), named after the layout and the focused window's app.
    func saveView(_ n: Int) {
        let app = AX.focusedWindow()?.appName
        let name = [state.layouts[state.current].name, app].compactMap { $0 }.joined(separator: " · ")
        setPrefs { $0.views[n] = currentView(name: name) }
        onHUD(state.prefs.menuControls.contains(.views) ? String(localized: "Saved view \(n). It's in the menu bar now.")
                                                        : String(localized: "Saved view \(n). Press ⌃⌥\(n) to come back to it."))
    }

    func goToView(_ n: Int) {
        guard let v = state.prefs.views[n] else {
            onHUD(String(localized: "No view \(n) yet. Save one first."))
            return
        }
        show(v)
    }

    func forgetView(_ n: Int) { setPrefs { $0.views[n] = nil } }

    /// Windows that haven't come back since they closed, their app quit or the Mac restarted.
    var missingWindows: [WindowRecord] { state.orphans + state.prefs.closed }

    func forgetMissing(_ r: WindowRecord? = nil) {
        store.update { st in
            guard let r else { st.orphans = []; st.prefs.closed = []; return }
            st.orphans.removeAll { $0.bundleID == r.bundleID && $0.title == r.title && $0.key == r.key }
            st.prefs.closed.removeAll { $0.bundleID == r.bundleID && $0.title == r.title && $0.key == r.key }
        }
        onChange()
    }

    /// Don't Arrange “App” / Arrange “App” Again.
    func setIgnored(_ bundleID: String, _ ignored: Bool) {
        setPrefs { p in if ignored { p.ignoredApps.insert(bundleID) } else { p.ignoredApps.remove(bundleID) } }
        for s in NSScreen.screens { arrange(s) }
    }
}

/// Every command Bower runs from a `bower://` link (Raycast, Alfred, Shortcuts, a script):
///
///     bower://layout/3        bower://send/3          bower://next        bower://previous
///     bower://snap/leftHalf   bower://wheel           bower://bar         bower://mode/dock
///     bower://workspace/Name  bower://save-workspace  bower://view/2      bower://save-view/2
///     bower://everything      bower://back            bower://forward     bower://step-in
///     bower://step-out        bower://frame           bower://focus/left  bower://arrange
///     bower://arrange-all     bower://split           bower://desktop     bower://float
///     bower://float-all       bower://retile          bower://settings
enum Command: Equatable {
    case layout(Int), send(Int), next, previous, snap(SnapAction), wheel, bar, mode(WindowMode)
    case workspace(String), saveWorkspace, view(Int), saveView(Int), everything, back, forward
    case stepIn, stepOut, frame, focus(String), arrange, arrangeAll, split, desktop, float, floatAll, retile, settings

    init?(url: URL) {
        guard url.scheme == "bower" else { return nil }
        let head = url.host ?? ""
        let arg = url.pathComponents.dropFirst().first.flatMap { $0.removingPercentEncoding }
        let num = arg.flatMap(Int.init)
        switch head {
        case "layout": guard let n = num, (1...9).contains(n) else { return nil }; self = .layout(n - 1)
        case "send": guard let n = num, (1...9).contains(n) else { return nil }; self = .send(n - 1)
        case "next": self = .next
        case "previous": self = .previous
        case "snap": guard let a = arg.flatMap(SnapAction.init(rawValue:)) else { return nil }; self = .snap(a)
        case "wheel": self = .wheel
        case "bar": self = .bar
        case "mode": guard let m = arg.flatMap(WindowMode.init(rawValue:)) else { return nil }; self = .mode(m)
        case "workspace": guard let a = arg else { return nil }; self = .workspace(a)
        case "save-workspace": self = .saveWorkspace
        case "view": guard let n = num, (1...9).contains(n) else { return nil }; self = .view(n)
        case "save-view": guard let n = num, (1...9).contains(n) else { return nil }; self = .saveView(n)
        case "everything": self = .everything
        case "back": self = .back
        case "forward": self = .forward
        case "step-in": self = .stepIn
        case "step-out": self = .stepOut
        case "frame": self = .frame
        case "focus": guard let a = arg, ["left", "right", "up", "down"].contains(a) else { return nil }; self = .focus(a)
        case "arrange": self = .arrange
        case "arrange-all": self = .arrangeAll
        case "split": self = .split
        case "desktop": self = .desktop
        case "float": self = .float
        case "float-all": self = .floatAll
        case "retile": self = .retile
        case "settings": self = .settings
        default: return nil
        }
    }
}
