import AppKit

// Private, but works with SIP on (AeroSpace and Rectangle use it): maps an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// A standard window of another app. Frames are in AX coordinates: global, top-left origin.
struct Win {
    let el: AXUIElement
    let id: CGWindowID
    let pid: pid_t
    let bundleID: String?
    let appName: String

    var key: String { String(id) }
    var title: String { (AX.value(el, kAXTitleAttribute) as String?).flatMap { $0.isEmpty ? nil : $0 } ?? appName }
    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
    /// The open document's file URL, for apps that report one (TextEdit, Pages, Xcode…).
    var document: String? { (AX.value(el, kAXDocumentAttribute) as String?).flatMap { $0.isEmpty ? nil : $0 } }
    /// The app's own name for the window, when it sets one; stays the same across launches.
    var identifier: String? { (AX.value(el, kAXIdentifierAttribute) as String?).flatMap { $0.isEmpty ? nil : $0 } }
    /// When the window's app started, so a record can tell a relaunch from the same run.
    var appLaunched: Date? { NSRunningApplication(processIdentifier: pid)?.launchDate }
    /// The smallest size the window took when asked for less (cached per app by `AppLimits`).
    var minSize: CGSize? { bundleID.flatMap { AppLimits.min[$0] } }

    var frame: CGRect? {
        guard let pos: CGPoint = AX.value(el, kAXPositionAttribute),
              let size: CGSize = AX.value(el, kAXSizeAttribute) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    func setFrame(_ r: CGRect) {
        AX.wrote(key)
        // Position, size, position: a window can't grow past the screen edge before it has moved.
        AX.set(el, kAXPositionAttribute, r.origin)
        AX.set(el, kAXSizeAttribute, r.size)
        AX.set(el, kAXPositionAttribute, r.origin)
        AppLimits.learn(self, asked: r.size)
    }

    func move(to p: CGPoint) { AX.wrote(key); AX.set(el, kAXPositionAttribute, p) }

    /// The window's title-bar area (AX coordinates): where a drag moves it and a double-click zooms it.
    var titleBar: CGRect? {
        guard let f = frame else { return nil }
        // Toolbars merged into the title bar make it taller; the standard is 28 pt.
        let h: CGFloat = (AX.value(el, "AXToolbar") as AXUIElement?) != nil ? 52 : 28
        return CGRect(x: f.minX, y: f.minY, width: f.width, height: h)
    }

    /// The frame of one of the red, yellow or green buttons.
    func button(_ attr: String) -> CGRect? {
        guard let b: AXUIElement = AX.value(el, attr), let p: CGPoint = AX.value(b, kAXPositionAttribute),
              let s: CGSize = AX.value(b, kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }

    func focus() {
        NSRunningApplication(processIdentifier: pid)?.activate()
        // A launcher-script app's NSRunningApplication can't activate (its pid reads -1); Accessibility can.
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    func raise() { AXUIElementPerformAction(el, kAXRaiseAction as CFString) }
}

enum AX {
    static var trusted: Bool { AXIsProcessTrusted() }

    /// When Bower last moved or resized each window: the AX notifications that follow are its own, not the user's.
    private(set) static var writes: [String: Date] = [:]
    static func wrote(_ key: String) { writes[key] = Date() }
    static func recentlyWrote(_ key: String, within t: TimeInterval = 1.0) -> Bool {
        writes[key].map { Date().timeIntervalSince($0) < t } ?? false
    }

    /// The window under a point: its ID, owner and bounds (AX coordinates), from the window server alone. Cheap
    /// enough for every click, unlike asking Accessibility.
    static func hit(_ p: CGPoint) -> (id: CGWindowID, pid: pid_t, bounds: CGRect)? {
        let me = ProcessInfo.processInfo.processIdentifier
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me, let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b), r.contains(p), let id = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            return (id, pid, r)
        }
        return nil
    }

    /// One window by ID, asking only its own app.
    static func window(id: CGWindowID, pid: pid_t) -> Win? {
        guard let app = NSRunningApplication(processIdentifier: pid) ?? apps().first(where: { $0.pid == pid })?.app else { return nil }
        let list: [AXUIElement] = value(AXUIElementCreateApplication(pid), kAXWindowsAttribute) ?? []
        for el in list {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(el, &wid) == .success, wid == id { return win(el, pid, app) }
        }
        return nil
    }

    /// The window under a point (AX coordinates), front to back, from the window server.
    static func windowID(at p: CGPoint) -> CGWindowID? {
        let me = ProcessInfo.processInfo.processIdentifier
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) != me, let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b), r.contains(p) else { continue }
            return w[kCGWindowNumber as String] as? CGWindowID
        }
        return nil
    }

    static func promptForAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func value<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &raw) == .success, let raw else { return nil }
        if CFGetTypeID(raw) == AXValueGetTypeID() {
            let v = raw as! AXValue
            switch AXValueGetType(v) {
            case .cgPoint: var p = CGPoint.zero; AXValueGetValue(v, .cgPoint, &p); return p as? T
            case .cgSize: var s = CGSize.zero; AXValueGetValue(v, .cgSize, &s); return s as? T
            default: return nil
            }
        }
        return raw as? T
    }

    static func set(_ el: AXUIElement, _ attr: String, _ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(el, attr as CFString, v) }
    }

    static func set(_ el: AXUIElement, _ attr: String, _ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(el, attr as CFString, v) }
    }

    private static func win(_ el: AXUIElement, _ pid: pid_t, _ app: NSRunningApplication) -> Win? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(el, &id) == .success, id != 0,
              (value(el, kAXSubroleAttribute) as String?) == kAXStandardWindowSubrole,
              (value(el, kAXMinimizedAttribute) as Bool?) != true,
              (value(el, "AXFullScreen") as Bool?) != true else { return nil }
        return Win(el: el, id: id, pid: pid, bundleID: app.bundleIdentifier,
                   appName: app.localizedName ?? "")
    }

    /// Every standard, non-minimized, non-fullscreen window of every regular app that isn't hidden.
    static func windows() -> [Win] {
        let me = ProcessInfo.processInfo.processIdentifier
        return apps()
            .filter { !$0.app.isHidden && $0.pid != me }
            .flatMap { pid, app -> [Win] in
                let list: [AXUIElement] = value(AXUIElementCreateApplication(pid), kAXWindowsAttribute) ?? []
                return list.compactMap { win($0, pid, app) }
            }
    }

    /// Regular apps and their real process IDs. An app started by a launcher script (an exec'ing shell script as its
    /// executable) reports pid -1, even when looked up by its real pid, so the owners of windows supply the pid.
    static func apps() -> [(pid: pid_t, app: NSRunningApplication)] {
        var byPID: [pid_t: NSRunningApplication] = [:]
        for a in NSWorkspace.shared.runningApplications where a.processIdentifier > 0 { byPID[a.processIdentifier] = a }
        let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, byPID[pid] == nil,
                  let a = NSRunningApplication(processIdentifier: pid) else { continue }
            byPID[pid] = a
        }
        return byPID.filter { $0.value.activationPolicy == .regular }.map { ($0.key, $0.value) }
    }

    /// The app with keyboard focus, asked of Accessibility since `frontmostApplication` can carry pid -1 (see `apps`).
    /// While a launcher-script app is in front, that question fails too, so the owner of the front window answers.
    static func frontApp() -> (pid: pid_t, app: NSRunningApplication)? {
        var raw: CFTypeRef?
        var pid: pid_t = 0
        if AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &raw) == .success,
           let el = raw, AXUIElementGetPid(el as! AXUIElement, &pid) == .success, pid > 0 {
            return NSRunningApplication(processIdentifier: pid).map { (pid, $0) }
        }
        let me = ProcessInfo.processInfo.processIdentifier
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let p = w[kCGWindowOwnerPID as String] as? pid_t, p != me,
                  let a = NSRunningApplication(processIdentifier: p), a.activationPolicy == .regular else { continue }
            return (p, a)
        }
        return nil
    }

    /// The focused window when it's in macOS full screen (which `windows()` leaves out), with its window ID.
    static func focusedFullScreenWindow() -> (AXUIElement, CGWindowID)? {
        guard let (pid, _) = frontApp(), let w: AXUIElement = value(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute),
              (value(w, "AXFullScreen") as Bool?) == true else { return nil }
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(w, &id) == .success, id != 0 else { return nil }
        return (w, id)
    }

    static func focusedWindow() -> Win? {
        guard let (pid, app) = frontApp(), pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        guard let w: AXUIElement = value(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else { return nil }
        return win(w, pid, app)
    }

    /// Window IDs front to back, used as "most recently focused first".
    static func zOrder() -> [CGWindowID] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    }
}

extension NSScreen {
    /// Stable across reconnects, unlike the display ID.
    var uuid: String {
        let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        guard let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "\(id)" }
        return CFUUIDCreateString(nil, u) as String
    }

    /// Converts an AppKit (bottom-left origin) rect to AX coordinates.
    static func ax(_ r: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    /// AX and AppKit flips are their own inverse.
    static func appKit(_ r: CGRect) -> CGRect { ax(r) }

    var axFrame: CGRect { NSScreen.ax(frame) }
    var axVisibleFrame: CGRect { NSScreen.ax(visibleFrame) }

    static func containing(ax r: CGRect) -> NSScreen? {
        let c = CGPoint(x: r.midX, y: r.midY)
        return screens.first { $0.axFrame.contains(c) }
            ?? screens.max { $0.axFrame.intersection(r).area < $1.axFrame.intersection(r).area }
    }

    static var underMouse: NSScreen? {
        screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? main
    }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

/// The smallest size each app lets its windows take, learned when a window comes out bigger than asked.
/// Kept for the session; Dock mode uses it to lay windows out without fighting their app.
enum AppLimits {
    static var min: [String: CGSize] = [:]
    /// The last size asked of each window, so a later ask makes an earlier check moot.
    private static var asks: [CGWindowID: CGSize] = [:]

    static func learn(_ w: Win, asked: CGSize) {
        guard let b = w.bundleID else { return }
        asks[w.id] = asked
        // A window just opened, or an app that's busy, can take a moment to resize: look a little later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard asks[w.id] == asked else { return }
            asks[w.id] = nil
            guard let got = w.frame?.size else { return }
            let m = min[b] ?? .zero
            var n = m
            // Bigger than asked: that's as small as it goes. As asked: the limit, if any, is no more than that.
            n.width = got.width > asked.width + 2 ? max(m.width, got.width) : Swift.min(m.width, got.width)
            n.height = got.height > asked.height + 2 ? max(m.height, got.height) : Swift.min(m.height, got.height)
            if n != m { min[b] = n }
        }
    }
}
