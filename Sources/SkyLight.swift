import AppKit

/// Desktops (Spaces) and which windows are on them, from the window server's private SkyLight calls.
///
/// Accessibility only sees the current desktop; these see all of them. Every symbol is looked up at runtime, and
/// a missing one makes the answer nil, never a crash: the features that need it simply don't show.
enum SkyLight {
    private static let lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let lib, let p = dlsym(lib, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias ActiveSpace = @convention(c) (Int32) -> UInt64
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    private static let cid: Int32? = sym("SLSMainConnectionID", MainConnection.self)?()

    static var available: Bool { cid != nil && sym("SLSCopyManagedDisplaySpaces", CopyDisplaySpaces.self) != nil }

    struct Space: Equatable, Hashable {
        var id: UInt64
        /// Stable across restarts while the desktop exists.
        var uuid: String
        /// 0 is a normal desktop, 4 a full-screen app's.
        var type: Int
        var display: String
        var index: Int
        var isFullScreen: Bool { type == 4 }
        var key: String { uuid.isEmpty ? String(id) : uuid }
    }

    /// Every display's desktops in order, and which one is showing on each.
    static func spaces() -> (all: [Space], current: [String: UInt64]) {
        guard let cid, let f = sym("SLSCopyManagedDisplaySpaces", CopyDisplaySpaces.self),
              let list = f(cid)?.takeRetainedValue() as? [[String: Any]] else { return ([], [:]) }
        var all: [Space] = [], current: [String: UInt64] = [:]
        for d in list {
            let display = d["Display Identifier"] as? String ?? ""
            for (i, s) in (d["Spaces"] as? [[String: Any]] ?? []).enumerated() {
                let id = (s["id64"] as? UInt64) ?? UInt64(s["ManagedSpaceID"] as? Int ?? 0)
                all.append(Space(id: id, uuid: s["uuid"] as? String ?? "", type: s["type"] as? Int ?? 0, display: display, index: i))
            }
            if let c = d["Current Space"] as? [String: Any] {
                current[display] = (c["id64"] as? UInt64) ?? UInt64(c["ManagedSpaceID"] as? Int ?? 0)
            }
        }
        return (all, current)
    }

    /// The desktop showing on the display under the pointer (or the main display).
    static func activeSpace() -> Space? {
        let s = spaces()
        guard !s.all.isEmpty else { return nil }
        let display = NSScreen.underMouse.map(\.uuid) ?? ""
        let id = s.current[display] ?? s.current.values.first
        if let id, let sp = s.all.first(where: { $0.id == id }) { return sp }
        if let f = sym("SLSGetActiveSpace", ActiveSpace.self), let cid { return s.all.first { $0.id == f(cid) } }
        return nil
    }

    /// The desktop a window is on, whichever desktop is showing.
    static func space(of window: CGWindowID) -> UInt64? {
        guard let cid, let f = sym("SLSCopySpacesForWindows", CopySpacesForWindows.self),
              let ids = f(cid, 0x7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return nil }
        return ids.first?.uint64Value
    }

    /// Every window of a regular app on every desktop, from the window server: id, owner, title (when Screen
    /// Recording is allowed), frame, and desktop. Minimized and hidden ones included.
    struct WindowInfo {
        var id: CGWindowID
        var pid: pid_t
        var app: String
        var title: String
        var frame: CGRect
        var space: UInt64?
        var onScreen: Bool
    }

    static func allWindows() -> [WindowInfo] {
        let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let me = ProcessInfo.processInfo.processIdentifier
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0, let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
                  r.width > 60, r.height > 40 else { return nil }
            return WindowInfo(id: id, pid: pid, app: w[kCGWindowOwnerName as String] as? String ?? "",
                              title: w[kCGWindowName as String] as? String ?? "", frame: r, space: space(of: id),
                              onScreen: w[kCGWindowIsOnscreen as String] as? Bool ?? false)
        }
    }

    /// Lets Bower set the pointer's shape while another app is in front (gap handles, drag previews).
    static func allowCursorInBackground() {
        guard let cid, let f = sym("CGSSetConnectionProperty", SetProperty.self) ?? sym("SLSSetConnectionProperty", SetProperty.self) else { return }
        let r = f(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        Log.info(r == 0 ? "CURSOR set in the background" : "CURSOR can't be set in the background (error \(r))")
    }
}

extension Engine {
    /// The desktop showing now, as a key that lasts across restarts.
    var spaceKey: String? { SkyLight.activeSpace()?.key }

    /// Whether Bower arranges windows on the desktop showing now (Use Bower on This Desktop).
    var arrangesHere: Bool {
        guard let k = spaceKey else { return true }
        if state.prefs.offSpaces.contains(k) { return false }
        if state.prefs.arrangeDesktops == .all || state.prefs.onSpaces.contains(k) { return true }
        // "First desktop only": each display's first desktop.
        return SkyLight.activeSpace()?.index == 0
    }

    func setArrangesHere(_ on: Bool) {
        guard let k = spaceKey else { return }
        setPrefs { p in
            if on { p.offSpaces.remove(k); p.onSpaces.insert(k) } else { p.offSpaces.insert(k); p.onSpaces.remove(k) }
        }
        if on { for s in NSScreen.screens { arrange(s) } }
    }
}
