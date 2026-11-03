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

    var frame: CGRect? {
        guard let pos: CGPoint = AX.value(el, kAXPositionAttribute),
              let size: CGSize = AX.value(el, kAXSizeAttribute) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    func setFrame(_ r: CGRect) {
        // Position, size, position: a window can't grow past the screen edge before it has moved.
        AX.set(el, kAXPositionAttribute, r.origin)
        AX.set(el, kAXSizeAttribute, r.size)
        AX.set(el, kAXPositionAttribute, r.origin)
    }

    func move(to p: CGPoint) { AX.set(el, kAXPositionAttribute, p) }

    func focus() {
        NSRunningApplication(processIdentifier: pid)?.activate()
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    func raise() { AXUIElementPerformAction(el, kAXRaiseAction as CFString) }
}

enum AX {
    static var trusted: Bool { AXIsProcessTrusted() }

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

    private static func win(_ el: AXUIElement, _ app: NSRunningApplication) -> Win? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(el, &id) == .success, id != 0,
              (value(el, kAXSubroleAttribute) as String?) == kAXStandardWindowSubrole,
              (value(el, kAXMinimizedAttribute) as Bool?) != true,
              (value(el, "AXFullScreen") as Bool?) != true else { return nil }
        return Win(el: el, id: id, pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                   appName: app.localizedName ?? "")
    }

    /// Every standard, non-minimized, non-fullscreen window of every regular app that isn't hidden.
    static func windows() -> [Win] {
        let me = ProcessInfo.processInfo.processIdentifier
        return apps()
            .filter { !$0.isHidden && $0.processIdentifier != me }
            .flatMap { app -> [Win] in
                let el = AXUIElementCreateApplication(app.processIdentifier)
                let list: [AXUIElement] = value(el, kAXWindowsAttribute) ?? []
                return list.compactMap { win($0, app) }
            }
    }

    /// Regular apps with a usable process ID. An app started by a launcher script (an exec'ing shell script as its
    /// executable) is listed with pid -1, so the owners of on-screen-layer windows fill in the real process.
    static func apps() -> [NSRunningApplication] {
        var byPID: [pid_t: NSRunningApplication] = [:]
        for a in NSWorkspace.shared.runningApplications where a.processIdentifier > 0 { byPID[a.processIdentifier] = a }
        let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, byPID[pid] == nil,
                  let a = NSRunningApplication(processIdentifier: pid) else { continue }
            byPID[pid] = a
        }
        return byPID.values.filter { $0.activationPolicy == .regular }
    }

    /// The app with keyboard focus, asked of Accessibility since `frontmostApplication` can carry pid -1 (see `apps`).
    static func frontApp() -> NSRunningApplication? {
        var raw: CFTypeRef?
        var pid: pid_t = 0
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &raw) == .success,
              let el = raw, AXUIElementGetPid(el as! AXUIElement, &pid) == .success else { return NSWorkspace.shared.frontmostApplication }
        return NSRunningApplication(processIdentifier: pid)
    }

    static func focusedWindow() -> Win? {
        guard let app = frontApp(),
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        guard let w: AXUIElement = value(el, kAXFocusedWindowAttribute) else { return nil }
        return win(w, app)
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
