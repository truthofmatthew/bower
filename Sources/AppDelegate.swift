import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = Store(directory: Diagnostics.storeDirectory)
    lazy var engine = Engine(store: store)
    let preview = SnapPreview()
    let toast = Toast()
    lazy var wheel = WheelController(engine: engine, preview: preview)
    private let middle = MiddleClickTap()
    let watcher = WindowWatcher()
    private var lastSpaceChange = Date.distantPast
    let shortcutCenter = ShortcutCenter()
    lazy var tabs = TabsController(engine: engine)
    private let keyTap = KeyTap()
    var statusItem: NSStatusItem!
    private var keySnap: (win: Win, action: SnapAction)?
    private var signalSource: DispatchSourceSignal?
    lazy var bar = LayoutsBar(engine: engine)
    let firstRun = FirstRunModel()
    private var firstRunWindow: HostedWindow?
    private var settingsWindow: HostedWindow?
    private var saveWindow: HostedWindow?
    private var workspacesWindow: HostedWindow?
    lazy var overview = Overview(engine: engine)
    lazy var dockDrag = DockDrag(engine: engine)
    lazy var zoomGestures = ZoomGestures(engine: engine, overview: overview)
    lazy var missionControl = MissionControl(engine: engine, overview: overview)
    lazy var menuStrip = MenuStrip(app: self)
    lazy var lessons = Lessons(engine: engine)
    let updates = Updates()
    var extraWindows: [String: HostedWindow] = [:]
    /// The settings that change how windows are laid out or drawn, as last applied.
    var appliedLook: String?

    @objc private func showSaveWorkspace() {
        saveWindow?.close()
        let st = store.state
        let w = HostedWindow(title: String(localized: "Save Workspace"), size: CGSize(width: 640, height: 190), bareTitlebar: true, hideButtons: true) {
            SaveWorkspaceView(summary: engine.workspaceSummary(),
                              save: { [weak self] name in self?.engine.saveWorkspace(named: name); self?.saveWindow?.close() },
                              cancel: { [weak self] in self?.saveWindow?.close() },
                              name: st.currentWorkspace ?? String(localized: "Workspace \(st.workspaces.count + 1)"))
        }
        saveWindow = w
        w.show()
    }

    private var recipeWindow: HostedWindow?

    @objc private func newRecipe() { showRecipe(nil) }

    @objc private func openRecipe(_ sender: NSMenuItem) { showRecipe(sender.representedObject as? String) }

    /// Recipe.dc.html's sheet, as its own window since Bower has no main window to attach it to.
    private func showRecipe(_ name: String?) {
        recipeWindow?.close()
        let model = RecipeModel(name: name, engine: engine)
        let w = HostedWindow(title: String(localized: "Recipe"), size: CGSize(width: 1020, height: 604), bareTitlebar: true, hideButtons: true) {
            RecipeEditorView(model: model) { [weak self] in self?.recipeWindow?.close() }
        }
        recipeWindow = w
        w.show()
    }

    @objc private func loadWorkspace(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { engine.loadWorkspace(named: name) }
    }

    @objc private func showWorkspaces() {
        if workspacesWindow == nil {
            workspacesWindow = HostedWindow(title: String(localized: "Workspaces"), size: CGSize(width: 640, height: 280)) {
                WorkspaceListView(store: store,
                                  load: { [weak self] in self?.engine.loadWorkspace(named: $0) },
                                  update: { [weak self] in self?.engine.saveWorkspace(named: $0) },
                                  deleteAction: { [weak self] in self?.engine.deleteWorkspace(named: $0) })
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        workspacesWindow?.show()
    }
    private static let onboardedKey = "onboarded"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.glyph
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        engine.onChange = { [weak self] in self?.refreshStatus() }
        engine.onHUD = { [weak self] text in
            guard let s = self?.engine.focusedScreen else { return }
            self?.toast.show(text, on: s)
        }
        engine.onPutBack = { [weak self] n in
            guard let s = NSScreen.main else { return }
            self?.toast.show(n == 1 ? String(localized: "1 window put back") : String(localized: "\(n) windows put back"), on: s)
        }
        engine.onRetile = { [weak self] n, s in
            self?.toast.show(n == 1 ? String(localized: "Retiled · 1 window on \(s.localizedName)")
                                       : String(localized: "Retiled · \(n) windows on \(s.localizedName)"), on: s)
        }
        refreshStatus()
        registerHotkeys()
        engine.onShortcutsChanged = { [weak self] in self?.registerHotkeys() }
        shortcutCenter.suspend = { Hotkeys.shared.removeAll() }
        shortcutCenter.resume = { [weak self] in self?.registerHotkeys() }
        wheel.onOpen = { [weak self] in self?.firstRun.wheelOpened = true; self?.lessons.did("wheel") }
        engine.onDid = { [weak self] in self?.lessons.did($0) }
        wheel.onSettings = { [weak self] in self?.openSettings() }
        wheel.onRecipe = { [weak self] in self?.showRecipe(nil) }

        middle.enabled = { [weak self] in self?.store.state.middleClickWheel ?? true }
        middle.onDown = { [weak self] in
            guard let self, !self.wheel.isOpen else { return }
            self.wheel.open(sticky: false, atPointer: true)
        }
        middle.onDrag = { [weak self] in self?.wheel.hover(global: $0) }
        middle.onUp = { [weak self] in
            guard let self, self.wheel.isOpen else { return }
            self.wheel.hover(global: NSEvent.mouseLocation)
            self.wheel.release()
        }

        // `pkill` sends SIGTERM, which skips applicationWillTerminate; route it through terminate so windows unpark.
        signal(SIGTERM, SIG_IGN)
        signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signalSource?.setEventHandler { NSApp.terminate(nil) }
        signalSource?.resume()

        // A diagnostics run (-dumpAX, -dumpLayout) only reads and quits, so it leaves the running copy alone.
        // exit, not terminate: the quit routine would unpark the running copy's windows and give back its shortcuts.
        if Diagnostics.handleLaunchArguments(store: store, engine: engine) { exit(0) }
        // Hosting the unit tests: leave the running copy, its windows and its shortcuts alone.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        Diagnostics.quitOtherCopies()
        Log.info("PERMISSIONS accessibility=\(AX.trusted) screen-recording=\(Capture.allowed)")
        if AX.trusted { start() } else { waitForAccess() }
        if !AX.trusted || !UserDefaults.standard.bool(forKey: Self.onboardedKey) { showFirstRun() } else { lessons.offerWhatsNew() }
        menuStrip.refresh()
        updates.start(prefs: { [weak self] in self?.store.state.prefs ?? Prefs() }, found: { [weak self] in self?.menuStrip.refresh() })
    }

    private func showFirstRun() {
        let w = HostedWindow(title: String(localized: "Welcome to Bower"), size: CGSize(width: 640, height: 680), bareTitlebar: true) {
            FirstRunView(model: firstRun, close: { [weak self] in
                UserDefaults.standard.set(true, forKey: Self.onboardedKey)
                self?.firstRunWindow?.close()
                self?.lessons.start(.gettingStarted)
            }, skip: { [weak self] in
                UserDefaults.standard.set(true, forKey: Self.onboardedKey)
                self?.firstRunWindow?.close()
            }, turnOffConflicts: { [weak self] in
                guard let self else { return }
                Conflict.active.forEach { $0.turnOff(self.engine) }
            })
        }
        firstRunWindow = w
        w.show()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = HostedWindow(title: String(localized: "Bower Settings"), size: CGSize(width: 760, height: 560), bareTitlebar: true) {
                SettingsView(store: store, engine: engine, shortcuts: shortcutCenter,
                             openReport: { [weak self] in self?.menuReport() },
                             openLessons: { [weak self] in self?.menuGettingStarted() },
                             setMissionControl: { [weak self] on in
                                 self?.missionControl.setOn(on)
                                 self?.registerHotkeys()
                             })
            }
        }
        settingsWindow?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        missionControl.giveBack()
        tabs.hideAll()
        if AX.trusted { engine.unparkAll() }
        store.flush()
    }

    /// FirstRun.dc.html: Bower polls the permission once a second and moves on by itself.
    private func waitForAccess() {
        // A first launch gets the welcome window's own button; a returning user who lost access gets the system prompt.
        if UserDefaults.standard.bool(forKey: Self.onboardedKey) { AX.promptForAccess() }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard AX.trusted else { return }
            t.invalidate()
            self?.start()
        }
    }

    private func start() {
        firstRun.trusted = true
        engine.recover()
        middle.start()
        engine.keepParked = { [weak self] k in
            guard let self else { return false }
            return self.tabs.isInactiveTab(k) || self.engine.live.dockHidden.contains(k)
        }
        engine.onWindowsChanged = { [weak self] in self?.tabs.applyAll() }
        AppLimits.onRaise = { [weak self] in
            guard let engine = self?.engine else { return }
            for s in NSScreen.screens where [.dock, .bento].contains(engine.mode(of: s)) { engine.arrange(s) }
        }
        keyTap.combo = { [weak self] in self?.store.state.combo(.nextTab) }
        keyTap.handle = { [weak self] in self?.tabs.cycleFocusedGroup() ?? false }
        keyTap.start()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tabs.focusChanged()
        }
        TrackpadTap.shared.enabled = { [weak self] in self?.store.state.trackpadTapOn ?? false }
        TrackpadTap.shared.onTap = { [weak self] in self?.wheel.toggle(atPointer: true) }  // like the shortcut: open, move, or close
        // macOS's own Spaces swipe, taken over when it uses the fingers chosen; otherwise Bower reads the trackpad.
        TrackpadTap.shared.swipeEnabled = { [weak self] in
            guard let self, self.store.state.swipeLayouts else { return false }
            return !(DockSwipe.shared.running && DockSwipe.system(fingers: self.store.state.prefs.swipeFingers).spaces)
        }
        TrackpadTap.shared.swipeFingers = { [weak self] in self?.store.state.prefs.swipeFingers ?? 3 }
        TrackpadTap.shared.onSwipe = { [weak self] d in self?.swiped(d) }
        TrackpadTap.shared.start()
        DockSwipe.shared.enabled = { [weak self] in
            guard let self else { return false }
            return self.store.state.swipeLayouts && !self.wheel.isOpen
                && DockSwipe.system(fingers: self.store.state.prefs.swipeFingers).spaces
        }
        DockSwipe.shared.canStep = { [weak self] d in self?.engine.canStep(d) ?? false }
        DockSwipe.shared.onStep = { [weak self] d in self?.swiped(d) }
        DockSwipe.shared.inverted = { [weak self] in self?.store.state.prefs.swipeInvert ?? false }
        DockSwipe.shared.takesMissionControl = { [weak self] in self?.store.state.prefs.replaceMissionControl ?? false }
        DockSwipe.shared.onMissionControl = { [weak self] in self?.overview.toggle() }
        DockSwipe.shared.start()
        EventTap.shared.start()
        dockDrag.install()
        tabs.installGroupButtons()
        Motion.shared.installInterrupt(engine)
        zoomGestures.install()
        SkyLight.allowCursorInBackground()
        missionControl.start()
        watcher.onResized = { [weak self] el in
            guard let self, let w = AX.windows().first(where: { CFEqual($0.el, el) }) else { return }
            self.engine.userResized(w)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            self?.lastSpaceChange = Date()
            // Entering full screen lands on a new desktop; give the animation a moment before reading the window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.engine.catchFullScreen() }
            // Browsers put their parked windows back on screen a little after a desktop change; park them again.
            for t in [1.2, 3.0] { DispatchQueue.main.asyncAfter(deadline: .now() + t) { self?.engine.reparkStrays() } }
        }
        watcher.onChange = { [weak self] in self?.engine.windowsChanged() }
        watcher.start()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                                          queue: .main) { [weak self] n in
            guard let self, Date().timeIntervalSince(self.watcher.lastClosed) > 1,
                  Date().timeIntervalSince(self.lastSpaceChange) > 1.5,  // macOS activates apps during a desktop change
                  let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  // A launcher-script app arrives with pid -1; its bundle ID still finds the real process.
                  let pid = app.processIdentifier > 0 ? app.processIdentifier
                      : AX.apps().first(where: { $0.app.bundleIdentifier == app.bundleIdentifier })?.pid,
                  pid != ProcessInfo.processInfo.processIdentifier else { return }
            self.engine.follow(pid: pid)
            self.tabs.reveal(pid: pid)
        }
        engine.windowsChanged()  // windows that came back after a restart find their layouts
        // Display recovery: remember what's on each display, and react when one connects or disconnects.
        engine.snapshotDisplays()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.engine.snapshotDisplays() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.engine.displaysChanged()
        }
        refreshStatus()
    }

    // MARK: Hotkeys

    /// Registers every shortcut row from Settings › Shortcuts. Two rows on one combination, or a combination
    /// another app owns, are reported as conflicts instead.
    func registerHotkeys() {
        Hotkeys.shared.removeAll()
        let st = store.state
        var owner: [Combo: ShortcutID] = [:]
        var conflicts: [ShortcutID: String] = [:]
        for id in ShortcutID.allCases where id != .nextTab {  // ⌃Tab goes through the key tap, so it can pass through
            for (i, c) in st.bindings(id).enumerated() {
                if let other = owner[c], other != id {
                    conflicts[id] = String(localized: "Also used by \(other.title)")
                    conflicts[other] = conflicts[other] ?? String(localized: "Also used by \(id.title)")
                    continue
                }
                owner[c] = id
                if register(id, i, c) == OSStatus(eventHotKeyExistsErr) { conflicts[id] = String(localized: "Already used by another app") }
            }
        }
        // "Show Bower's overview instead": Bower answers macOS's Mission Control keys while it holds them.
        if st.prefs.replaceMissionControl, let c = MissionControl.missionControlKeys() {
            _ = Hotkeys.shared.add(c.key, c.mods) { [weak self] in self?.overview.toggle() }
        }
        shortcutCenter.conflicts = conflicts
    }

    private func register(_ id: ShortcutID, _ i: Int, _ c: Combo) -> OSStatus {
        let hk = Hotkeys.shared
        func snap(_ actions: [SnapAction]) -> OSStatus {
            let a = actions[i]
            return hk.add(c.key, c.mods, down: { [weak self] in self?.snapDown(a) }, up: { [weak self] in self?.snapUp(a) })
        }
        switch id {
        case .wheel:
            return hk.add(c.key, c.mods) { [weak self] in self?.wheel.toggle() }
        case .layoutsBar: return hk.add(c.key, c.mods) { [weak self] in self?.bar.toggle() }
        case .switchLayout:
            return hk.add(c.key, c.mods) { [weak self] in
                guard let self else { return }
                self.engine.switchTo(i)
                self.firstRun.pressed.insert(i)
                self.firstRun.lastSwitch = "\(i + 1) · \(self.store.state.layouts[i].name)"
            }
        case .sendLayout: return hk.add(c.key, c.mods) { [weak self] in self?.engine.sendFocused(to: i) }
        case .saveWorkspace: return hk.add(c.key, c.mods) { [weak self] in self?.showSaveWorkspace() }
        case .cycleLayouts: return hk.add(c.key, c.mods) { [weak self] in self?.engine.cycle() }
        case .emptyLayout: return hk.add(c.key, c.mods) { [weak self] in self?.engine.switchToEmptyLayout() }
        case .focus:
            let dir: [Engine.Direction] = [.left, .right, .up, .down]
            return hk.add(c.key, c.mods) { [weak self] in self?.engine.neighbour(dir[i]); self?.flashMap() }
        case .retile:
            return hk.add(c.key, c.mods) { [weak self] in
                guard let self else { return }
                let s = AX.focusedWindow().flatMap { $0.frame }.flatMap { NSScreen.containing(ax: $0) } ?? NSScreen.underMouse
                if let s { self.engine.retile(s) }
            }
        case .maximize: return snap([.maximize])
        case .halvesLR: return snap([.leftHalf, .rightHalf])
        case .halvesTB: return snap([.topHalf, .bottomHalf])
        case .quarters: return snap([.topLeft, .topRight, .bottomLeft, .bottomRight])
        case .thirds: return snap([.firstThird, .centerThird, .lastThird])
        case .twoThirds: return snap([.firstTwoThirds, .lastTwoThirds])
        case .nextTab: return noErr
        case .everything: return hk.add(c.key, c.mods) { [weak self] in self?.overview.toggle(); self?.lessons.did("everything") }
        case .stepIn: return hk.add(c.key, c.mods) { [weak self] in self?.engine.stepIn(); self?.flashMap() }
        case .stepOut: return hk.add(c.key, c.mods) { [weak self] in self?.engine.stepOut(); self?.flashMap() }
        case .frame:
            return hk.add(c.key, c.mods) { [weak self] in
                if let w = AX.focusedWindow() { self?.engine.frameToggle(w); self?.lessons.did("frame") }
            }
        case .back: return hk.add(c.key, c.mods) { [weak self] in self?.engine.goBack() }
        case .forward: return hk.add(c.key, c.mods) { [weak self] in self?.engine.goForward() }
        case .goView: return hk.add(c.key, c.mods) { [weak self] in self?.engine.goToView(i + 1) }
        case .saveView: return hk.add(c.key, c.mods) { [weak self] in self?.engine.saveView(i + 1); self?.lessons.did("saveView") }
        case .desktop: return hk.add(c.key, c.mods) { [weak self] in if let s = self?.engine.focusedScreen { self?.engine.toggleDesktop(s) } }
        case .arrange: return hk.add(c.key, c.mods) { [weak self] in self?.engine.arrangeIntoTiles(everywhere: false) }
        case .split: return hk.add(c.key, c.mods) { [weak self] in self?.engine.splitWithFinder() }
        case .float: return hk.add(c.key, c.mods) { [weak self] in if let w = AX.focusedWindow() { self?.engine.toggleFloat(w) } }
        }
    }

    /// The preview fades in on key-down; the window lands on key-up.
    private func snapDown(_ action: SnapAction) {
        guard keySnap?.action != action, let w = AX.focusedWindow(), let t = engine.target(action, for: w) else { return }
        keySnap = (w, action)
        preview.show(t.frame)
    }

    private func snapUp(_ action: SnapAction) {
        guard let s = keySnap, s.action == action else { return }
        keySnap = nil
        engine.snap(s.win, action)
        preview.hide()
    }

    // MARK: Status item

    /// AppIcon.dc.html's 18 pt template glyph: "M3 15.5V9a6 6 0 0 1 12 0v6.5" over two posts.
    private static let glyph: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 3, y: 15.5))
            p.line(to: NSPoint(x: 3, y: 9))
            p.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 6, startAngle: 180, endAngle: 360, clockwise: false)
            p.line(to: NSPoint(x: 15, y: 15.5))
            p.lineWidth = 1.6
            p.lineCapStyle = .round
            NSColor.black.setStroke()
            p.stroke()
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 6, y: 10.5, width: 2.6, height: 5), xRadius: 0.6, yRadius: 0.6).fill()
            NSBezierPath(roundedRect: NSRect(x: 9.4, y: 10.5, width: 2.6, height: 5), xRadius: 0.6, yRadius: 0.6).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Bower"
        return img
    }()

    func refreshStatus() {
        menuStrip.refresh()
        applyPrefsIfChanged()
        let st = store.state
        let n = st.current + 1
        let title: String
        switch st.statusStyle {
        case .numberAndName: title = "\(n) · \(st.layouts[st.current].name)"
        case .iconOnly: title = ""
        case .numberOnly: title = "\(n)"
        case .windowCount:
            let c = AX.trusted ? engine.windowCount(in: st.current) : 0
            title = c == 1 ? String(localized: "1 window") : String(localized: "\(c) windows")
        }
        // Update reminders put a dot on the item while an update waits.
        let dot = st.prefs.updateReminders && updates.available != nil ? " •" : ""
        statusItem.button?.title = title + dot
        let off = AX.trusted && !engine.arrangesHere
        statusItem.button?.appearsDisabled = off
        statusItem.button?.toolTip = off ? String(localized: "Bower: off on this desktop")
            : updates.available.map { String(localized: "Bower: update to \($0.version) waiting") }
        statusItem.button?.setAccessibilityLabel(String(localized: "Bower, layout \(n), \(st.layouts[st.current].name)"))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let st = store.state

        menu.addItem(.sectionHeader(title: String(localized: "Layouts")))
        for (i, l) in st.layouts.enumerated() {
            let item = NSMenuItem(title: "\(i + 1)  \(l.name)", action: #selector(switchLayout(_:)), keyEquivalent: "\(i + 1)")
            item.keyEquivalentModifierMask = .option
            item.target = self
            item.tag = i
            item.state = i == st.current ? .on : .off
            if i != st.current, l.isUntitled {
                item.attributedTitle = NSAttributedString(string: item.title, attributes: [.foregroundColor: NSColor.tertiaryLabelColor])
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let screen = NSScreen.underMouse
        let displayItem = NSMenuItem(title: String(localized: "This Display"), action: nil, keyEquivalent: "")
        let dMenu = modeMenu(for: screen)
        addDisplayItems(to: dMenu, screen: screen)
        displayItem.submenu = dMenu
        menu.addItem(displayItem)
        addAppItem(to: menu)
        addGoItem(to: menu)

        let workspaces = NSMenuItem(title: String(localized: "Workspaces"), action: nil, keyEquivalent: "")
        let wsMenu = NSMenu()
        let saveItem = NSMenuItem(title: String(localized: "Save Current Workspace…"), action: #selector(showSaveWorkspace), keyEquivalent: "s")
        saveItem.keyEquivalentModifierMask = [.control, .option]
        saveItem.target = self
        wsMenu.addItem(saveItem)
        if !store.state.workspaces.isEmpty {
            wsMenu.addItem(.separator())
            for ws in store.state.workspaces {
                let it = NSMenuItem(title: ws.name, action: #selector(loadWorkspace(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = ws.name
                it.state = ws.name == store.state.currentWorkspace ? .on : .off
                wsMenu.addItem(it)
            }
        }
        wsMenu.addItem(.separator())
        let all = NSMenuItem(title: String(localized: "Show All Workspaces…"), action: #selector(showWorkspaces), keyEquivalent: "")
        all.target = self
        wsMenu.addItem(all)
        workspaces.submenu = wsMenu
        menu.addItem(workspaces)

        let recipes = NSMenuItem(title: String(localized: "Recipes"), action: nil, keyEquivalent: "")
        let rMenu = NSMenu()
        let new = NSMenuItem(title: String(localized: "New Recipe…"), action: #selector(newRecipe), keyEquivalent: "")
        new.target = self
        rMenu.addItem(new)
        let names = RecipeFiles.names()
        if !names.isEmpty { rMenu.addItem(.separator()) }
        for n in names {
            let it = NSMenuItem(title: n, action: #selector(openRecipe(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = n
            rMenu.addItem(it)
        }
        recipes.submenu = rMenu
        menu.addItem(recipes)
        menu.addItem(.separator())

        addHelpItems(to: menu)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: String(localized: "About Bower"), action: #selector(about), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: String(localized: "Quit Bower"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func modeMenu(for screen: NSScreen?) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        guard let screen else { return sub }
        sub.addItem(.sectionHeader(title: screen.localizedName))
        let current = engine.mode(of: screen)
        for m in WindowMode.allCases {
            let it = NSMenuItem(title: m.title, action: #selector(setMode(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = (m, screen)
            it.state = m == current ? .on : .off
            sub.addItem(it)
        }
        sub.addItem(.separator())
        let all = NSMenuItem(title: String(localized: "Same for All Displays"), action: #selector(sameForAll(_:)), keyEquivalent: "")
        all.target = self
        all.representedObject = current
        all.isEnabled = NSScreen.screens.contains { engine.mode(of: $0) != current }
        sub.addItem(all)
        return sub
    }

    @objc private func switchLayout(_ sender: NSMenuItem) { engine.switchTo(sender.tag) }

    @objc func routeApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        // Choosing the checked layout again removes the route.
        engine.route(bundleID: id, to: store.state.routes[id] == sender.tag ? nil : sender.tag)
    }

    @objc func togglePin(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? NSScreen { engine.togglePin(s) }
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        if let (m, s) = sender.representedObject as? (WindowMode, NSScreen) { engine.setMode(m, for: s) }
    }

    @objc private func sameForAll(_ sender: NSMenuItem) {
        if let m = sender.representedObject as? WindowMode { engine.setModeForAllDisplays(m) }
    }

    private var aboutWindow: NSWindow?

    /// The same About window as Magpie's: icon, version, who made it, GitHub and website.
    @objc private func about() {
        if aboutWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = String(localized: "About Bower")
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace]
            [.miniaturizeButton, .zoomButton].forEach { window.standardWindowButton($0)?.isHidden = true }
            window.center()
            aboutWindow = window
        }
        NSApp.activate()
        aboutWindow?.makeKeyAndOrderFront(nil)
        aboutWindow?.orderFrontRegardless()
    }
}
