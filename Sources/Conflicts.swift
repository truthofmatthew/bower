import AppKit

/// macOS's own ways of moving windows, which fight Bower's arranging: edge tiling, "Click wallpaper to reveal
/// desktop" and Stage Manager. Bower only turns them off when you press the button, remembers what it changed,
/// and turns them back on with one more press (do that before uninstalling).
enum Conflict: String, CaseIterable, Identifiable {
    case edgeTiling, clickWallpaper, stageManager

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edgeTiling: String(localized: "Edge tiling")
        case .clickWallpaper: String(localized: "Click wallpaper to reveal desktop")
        case .stageManager: String(localized: "Stage Manager")
        }
    }

    var what: String {
        switch self {
        case .edgeTiling: String(localized: "snaps a window to half the screen when you drag it to an edge. Holding ⌥ to tile still works.")
        case .clickWallpaper: String(localized: "sweeps every window aside when you click the desktop.")
        case .stageManager: String(localized: "gathers windows into its own stacks at the side.")
        }
    }

    private static let domain = "com.apple.WindowManager"

    /// The WindowManager keys behind each one, and the value that means "off".
    private var keys: [(String, Int)] {
        switch self {
        case .edgeTiling: [("EnableTilingByEdgeDrag", 0), ("EnableTopTilingByEdgeDrag", 0)]
        case .clickWallpaper: [("EnableStandardClickToShowDesktop", 0)]
        case .stageManager: [("GloballyEnabled", 0)]
        }
    }

    private static func read(_ key: String) -> Int? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Int
    }

    private static func write(_ key: String, _ v: Int) {
        CFPreferencesSetAppValue(key as CFString, v as CFNumber, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
    }

    /// On, as macOS sees it. Missing keys are macOS's defaults: tiling and click-to-reveal on (macOS 15+), Stage Manager off.
    var isOn: Bool {
        switch self {
        case .stageManager: (Self.read("GloballyEnabled") ?? 0) != 0
        case .clickWallpaper: (Self.read("EnableStandardClickToShowDesktop") ?? 1) != 0
        case .edgeTiling:
            ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15 && (Self.read("EnableTilingByEdgeDrag") ?? 1) != 0
        }
    }

    static var active: [Conflict] { allCases.filter(\.isOn) }

    /// Turns it off and records the old values, so `turnBackOn` restores exactly what was there.
    func turnOff(_ engine: Engine) {
        var saved: [String: Int] = [:]
        for (k, off) in keys {
            saved[k] = Self.read(k) ?? (k == "GloballyEnabled" ? 0 : 1)
            Self.write(k, off)
        }
        engine.setPrefs { p in for (k, v) in saved { p.turnedOff[k] = v } }
        Self.applyNow()
    }

    static func turnBackOn(_ engine: Engine) {
        for (k, v) in engine.state.prefs.turnedOff { write(k, v) }
        engine.setPrefs { $0.turnedOff = [:] }
        applyNow()
    }

    /// WindowManager reads its settings at launch; it restarts by itself when quit, as System Settings does.
    private static func applyNow() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WindowManager"]
        try? task.run()
    }
}
