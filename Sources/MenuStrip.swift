import AppKit

/// Menu-bar buttons besides Bower's own item: Everything, back, forward, saved views. They show in the order
/// chosen in Settings, and ⌘-drag moves them like any menu-bar item. Right-clicking one opens Bower's menu.
final class MenuStrip: NSObject {
    private unowned let app: AppDelegate
    private var items: [MenuControl: NSStatusItem] = [:]

    init(app: AppDelegate) { self.app = app }

    func refresh() {
        let p = app.store.state.prefs
        let want = p.menuControls.filter { $0 != .layout && (p.historyButtons || ($0 != .back && $0 != .forward)) }
        for (c, it) in items where !want.contains(c) {
            NSStatusBar.system.removeStatusItem(it)
            items[c] = nil
        }
        // Items made later sit further left; make them right to left so they read in the chosen order.
        for c in want.reversed() where items[c] == nil {
            let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            it.autosaveName = "Bower.\(c.rawValue)"
            it.button?.target = self
            it.button?.action = #selector(clicked(_:))
            it.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            it.button?.identifier = NSUserInterfaceItemIdentifier(c.rawValue)
            items[c] = it
        }
        for (c, it) in items {
            guard let b = it.button else { continue }
            b.image = NSImage(systemSymbolName: symbol(c), accessibilityDescription: c.title)
            b.image?.isTemplate = true
            b.toolTip = c.title
            b.wantsLayer = true
            // "How white the frame round the buttons is."
            b.layer?.cornerRadius = 5
            b.layer?.borderWidth = p.menuBarFill > 0 ? 1 : 0
            b.layer?.borderColor = NSColor.white.withAlphaComponent(p.menuBarFill).cgColor
            switch c {
            case .back: b.appearsDisabled = !app.engine.canGoBack
            case .forward: b.appearsDisabled = !app.engine.canGoForward
            default: break
            }
        }
    }

    private func symbol(_ c: MenuControl) -> String {
        switch c {
        case .layout: "rectangle.split.3x1"
        case .everything: "square.grid.2x2"
        case .back: "chevron.left"
        case .forward: "chevron.right"
        case .views: "bookmark"
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let c = sender.identifier.flatMap({ MenuControl(rawValue: $0.rawValue) }) else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            app.statusItem.button?.performClick(nil)
            return
        }
        switch c {
        case .everything: app.menuEverything()
        case .back: app.menuBack()
        case .forward: app.menuForward()
        case .views:
            let m = NSMenu()
            let views = app.store.state.prefs.views.sorted { $0.key < $1.key }
            if views.isEmpty { m.addItem(NSMenuItem(title: String(localized: "No saved views yet"), action: nil, keyEquivalent: "")) }
            for (n, v) in views {
                let it = NSMenuItem(title: String(localized: "View \(n): \(v.name)"), action: #selector(AppDelegate.menuGoView(_:)), keyEquivalent: "")
                it.target = app
                it.tag = n
                m.addItem(it)
            }
            m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        case .layout: break
        }
        refresh()
    }
}

/// Checks GitHub for a newer release, once a day when turned on, or when asked. Nothing is downloaded: the
/// release page opens in the browser.
final class Updates {
    struct Release { var version: String; var page: URL }
    private(set) var available: Release?
    private var timer: Timer?
    private static let api = URL(string: "https://api.github.com/repos/truthofmatthew/bower/releases?per_page=10")!

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    func start(prefs: @escaping () -> Prefs, found: @escaping () -> Void) {
        let tick = { [weak self] in
            guard prefs().checkUpdates else { return }
            self?.check(prefs: prefs(), manual: false, done: found)
        }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { _ in tick() }
    }

    func check(prefs: Prefs, manual: Bool, done: @escaping () -> Void) {
        URLSession.shared.dataTask(with: Self.api) { data, _, error in
            let list = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]]) ?? []
            let newest = list.first { r in
                (r["draft"] as? Bool) != true && (prefs.betaUpdates || (r["prerelease"] as? Bool) != true)
            }
            DispatchQueue.main.async {
                if let r = newest, let tag = r["tag_name"] as? String, let page = (r["html_url"] as? String).flatMap(URL.init(string:)),
                   Self.newer(tag, than: Self.current) {
                    self.available = Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "v")), page: page)
                } else {
                    self.available = nil
                }
                done()
                guard manual else { return }
                let a = NSAlert()
                if let u = self.available {
                    a.messageText = String(localized: "Bower \(u.version) is out")
                    a.informativeText = String(localized: "You have version \(Self.current).")
                    a.addButton(withTitle: String(localized: "Open the Release Page"))
                    a.addButton(withTitle: String(localized: "Not Now"))
                    if a.runModal() == .alertFirstButtonReturn { self.openDownload() }
                } else {
                    a.messageText = error == nil ? String(localized: "Bower is up to date") : String(localized: "Couldn't reach GitHub")
                    a.informativeText = error == nil ? String(localized: "You have version \(Self.current).")
                                                     : String(localized: "Check your connection and try again.")
                    a.runModal()
                }
            }
        }.resume()
    }

    func openDownload() { if let u = available { NSWorkspace.shared.open(u.page) } }

    /// "v1.10" is newer than "1.9".
    static func newer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
