import AppKit
import SwiftUI

/// The menu items, commands and windows that came with docking, zoom and views.
extension AppDelegate {
    /// A swipe between layouts: the desk slides the way the fingers went while the layout changes underneath.
    func swiped(_ d: Int) {
        guard !wheel.isOpen, engine.canStep(d) else { return }
        if let s = NSScreen.underMouse { Motion.shared.slide(d, screen: s, engine: engine) }
        engine.step(d)
        lessons.did("swipe")
    }

    /// A layout setting changed in Settings (gap, handles, dimming, tab strips): lay everything out again.
    func applyPrefsIfChanged() {
        guard AX.trusted else { return }
        let p = store.state.prefs
        let look = "\(p.gap)|\(p.gapHandles)|\(p.gapHandlesAlwaysShown)|\(p.dimBehind)|\(p.dimOpacity)|\(p.collapseSmall)|\(p.squeezeBelowMinimum)"
            + "|\(p.tabStyle)|\(p.tabSelectedChip)|\(p.tabChipMargin)|\(p.tabInset)|\(p.tabPadding)|\(p.tabTint)|\(p.tabStripLights)"
            + "|\(p.tabCloseButtons)|\(p.tabCloseOnRight)|\(p.tabGlassOpaqueWhenInactive)|\(p.ignoredApps.sorted())"
        guard look != appliedLook else { return }
        let first = appliedLook == nil
        appliedLook = look
        guard !first else { return }
        DispatchQueue.main.async { [self] in
            for s in NSScreen.screens { engine.arrange(s) }
            tabs.applyAll()
        }
    }

    func flashMap() {
        if let s = engine.focusedScreen { Minimap.shared.flash(engine, on: s) }
    }

    // MARK: Menu

    /// This Display ▸, after its modes: pinning, Dock mode's Desktop tile, and whether Bower arranges this desktop.
    func addDisplayItems(to sub: NSMenu, screen: NSScreen?) {
        guard let screen else { return }
        let st = store.state
        let pin = item(String(localized: "Pin This Display"), #selector(togglePin(_:)))
        pin.state = st.pinned.contains(screen.uuid) ? .on : .off
        pin.representedObject = screen
        sub.addItem(pin)
        if engine.mode(of: screen) == .dock {
            let shown = engine.desktopShown(screen)
            sub.addItem(item(shown ? String(localized: "Hide Desktop Tile") : String(localized: "Show Desktop Tile"),
                             #selector(menuToggleDesktop)))
            sub.addItem(item(String(localized: "Float All Windows on the Desktop Tile"), #selector(menuFloatAll)))
        }
        if SkyLight.available {
            let here = item(String(localized: "Use Bower on This Desktop"), #selector(menuArrangeHere))
            here.state = engine.arrangesHere ? .on : .off
            sub.addItem(here)
        }
    }

    /// The front app ▸: which layout its new windows open in, and whether Bower arranges it at all.
    func addAppItem(to menu: NSMenu) {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let st = store.state
        // A browser window of a profile ("… - Microsoft Edge - Product") routes that profile on its own.
        let profile = AX.focusedWindow().flatMap { $0.bundleID == id ? profileName(of: $0.title, app: $0.appName) : nil }
        let key = routeKey(id, profile: profile)
        let name = app.localizedName ?? AppInfo.name(id)
        let top = NSMenuItem(title: name + (profile.map { " · \($0)" } ?? ""), action: nil, keyEquivalent: "")
        top.image = app.icon.map { i in let c = i.copy() as! NSImage; c.size = NSSize(width: 16, height: 16); return c }
        let sub = NSMenu()
        sub.addItem(.sectionHeader(title: String(localized: "New windows open in")))
        for (i, l) in st.layouts.enumerated() {
            let it = item("\(i + 1)  \(l.name)", #selector(routeApp(_:)))
            it.tag = i
            it.representedObject = key
            it.state = st.routes[key] == i ? .on : .off
            sub.addItem(it)
        }
        sub.addItem(.separator())
        let ignored = st.prefs.ignoredApps.contains(id)
        let it = item(ignored ? String(localized: "Arrange “\(name)” Again") : String(localized: "Don’t Arrange “\(name)”"), #selector(menuIgnore(_:)))
        it.representedObject = id
        sub.addItem(it)
        top.submenu = sub
        menu.addItem(top)
    }

    /// Go ▸: the overview, back and forward, and saved views.
    func addGoItem(to menu: NSMenu) {
        let st = store.state
        let go = NSMenuItem(title: String(localized: "Go"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        sub.addItem(item(String(localized: "Show Overview"), #selector(menuEverything)))
        let back = item(String(localized: "Go Back"), #selector(menuBack))
        back.isEnabled = engine.canGoBack
        sub.addItem(back)
        let fwd = item(String(localized: "Go Forward"), #selector(menuForward))
        fwd.isEnabled = engine.canGoForward
        sub.addItem(fwd)
        sub.addItem(.separator())
        sub.addItem(.sectionHeader(title: String(localized: "Saved Views")))
        for (n, v) in st.prefs.views.sorted(by: { $0.key < $1.key }) {
            let it = item(String(localized: "View \(n): \(v.name)"), #selector(menuGoView(_:)))
            it.tag = n
            let forget = item(String(localized: "Forget View \(n)"), #selector(menuForgetView(_:)))
            forget.tag = n
            forget.isAlternate = true
            forget.keyEquivalentModifierMask = .option
            sub.addItem(it)
            sub.addItem(forget)
        }
        sub.addItem(item(String(localized: "Save This View"), #selector(menuSaveView)))
        go.submenu = sub
        menu.addItem(go)
    }

    func addHelpItems(to menu: NSMenu) {
        let help = NSMenuItem(title: String(localized: "Help"), action: nil, keyEquivalent: "")
        let hMenu = NSMenu()
        hMenu.addItem(item(String(localized: "Getting Started"), #selector(menuGettingStarted)))
        hMenu.addItem(item(String(localized: "What’s New"), #selector(menuWhatsNew)))
        hMenu.addItem(item(String(localized: "Read the Guide"), #selector(menuGuide)))
        hMenu.addItem(.separator())
        hMenu.addItem(item(String(localized: "Report a Problem…"), #selector(menuReport)))
        if updates.available == nil { hMenu.addItem(item(String(localized: "Check for Updates…"), #selector(menuCheckUpdates))) }
        help.submenu = hMenu
        menu.addItem(help)
        // A waiting update stays in sight, outside Help.
        if let u = updates.available { menu.addItem(item(String(localized: "Update to Bower \(u.version)…"), #selector(menuUpdate))) }
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        return it
    }

    @objc func menuEverything() { overview.toggle() }
    @objc func menuBack() { engine.goBack() }
    @objc func menuForward() { engine.goForward() }
    @objc private func menuSaveView() { engine.saveView((1...9).first { store.state.prefs.views[$0] == nil } ?? 9) }
    @objc func menuGoView(_ sender: NSMenuItem) { engine.goToView(sender.tag) }
    @objc private func menuForgetView(_ sender: NSMenuItem) { engine.forgetView(sender.tag) }
    @objc private func menuToggleDesktop() { if let s = NSScreen.underMouse { engine.toggleDesktop(s) } }
    @objc private func menuFloatAll() { if let s = NSScreen.underMouse { engine.floatAll(s) } }
    @objc private func menuArrangeHere() { engine.setArrangesHere(!engine.arrangesHere); refreshStatus() }
    @objc private func menuIgnore(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        engine.setIgnored(id, !store.state.prefs.ignoredApps.contains(id))
    }
    @objc func menuGettingStarted() { lessons.start(.gettingStarted) }
    @objc private func menuWhatsNew() { lessons.start(.whatsNew) }
    @objc private func menuGuide() { NSWorkspace.shared.open(URL(string: "https://truthofmatthew.com/projects/bower/help/")!) }
    @objc private func menuCheckUpdates() { updates.check(prefs: store.state.prefs, manual: true) { [weak self] in self?.refreshStatus() } }
    @objc private func menuUpdate() { updates.openDownload() }

    @objc func menuReport() {
        let key = "report"
        extraWindows[key]?.close()
        let w = HostedWindow(title: String(localized: "Report a Problem"), size: CGSize(width: 480, height: 400), bareTitlebar: true) {
            ReportView(state: store.state) { [weak self] in self?.extraWindows[key]?.close() }
        }
        extraWindows[key] = w
        w.show()
    }

    // MARK: Commands by URL

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let c = Command(url: url) else { Log.info("URL not understood: \(url.absoluteString)"); continue }
            run(c)
        }
    }

    func run(_ c: Command) {
        switch c {
        case .layout(let n): engine.switchTo(n)
        case .send(let n): engine.sendFocused(to: n)
        case .next: engine.step(1)
        case .previous: engine.step(-1)
        case .snap(let a): if let w = AX.focusedWindow() { engine.snap(w, a) }
        case .wheel: wheel.toggle()
        case .bar: bar.toggle()
        case .mode(let m): if let s = engine.focusedScreen { engine.setMode(m, for: s) }
        case .workspace(let name): engine.loadWorkspace(named: name)
        case .saveWorkspace: engine.saveWorkspace(named: store.state.currentWorkspace ?? String(localized: "Workspace \(store.state.workspaces.count + 1)"))
        case .view(let n): engine.goToView(n)
        case .saveView(let n): engine.saveView(n)
        case .everything: overview.toggle()
        case .back: engine.goBack()
        case .forward: engine.goForward()
        case .stepIn: engine.stepIn()
        case .stepOut: engine.stepOut()
        case .frame: if let w = AX.focusedWindow() { engine.frameToggle(w) }
        case .focus(let d): engine.neighbour(["left": .left, "right": .right, "up": .up][d] ?? .down)
        case .arrange: engine.arrangeIntoTiles(everywhere: false)
        case .arrangeAll: engine.arrangeIntoTiles(everywhere: true)
        case .split: engine.splitWithFinder()
        case .desktop: if let s = engine.focusedScreen { engine.toggleDesktop(s) }
        case .float: if let w = AX.focusedWindow() { engine.toggleFloat(w) }
        case .floatAll: if let s = engine.focusedScreen { engine.floatAll(s) }
        case .retile: if let s = engine.focusedScreen { engine.retile(s) }
        case .settings: openSettings()
        }
    }
}
