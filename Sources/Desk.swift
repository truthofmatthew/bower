import AppKit

enum WindowMode: String, Codable, CaseIterable {
    case native, bento, tabs, dock

    var title: String {
        switch self {
        case .native: String(localized: "Native")
        case .bento: String(localized: "Bento Box")
        case .tabs: String(localized: "Tabs")
        case .dock: String(localized: "Dock")
        }
    }
}

enum StatusStyle: String, Codable {
    case numberAndName, iconOnly, numberOnly, windowCount
}

struct Layout: Codable {
    var name: String
    /// Window Mode per display UUID. Missing means Native.
    var modes: [String: WindowMode] = [:]
    var lastFocused: String?

    static var untitled: String { String(localized: "Untitled") }
    /// Also true for "Untitled" saved before the app was translated.
    var isUntitled: Bool { name == Layout.untitled || name == "Untitled" }
}

/// Everything Bower remembers, saved as readable JSON in ~/Library/Application Support/Bower/state.json.
struct DeskState: Codable {
    var layouts: [Layout] = [String(localized: "Mail"), String(localized: "Design"), String(localized: "Dev"),
                             String(localized: "Comms"), String(localized: "Research"), String(localized: "Music"),
                             Layout.untitled, Layout.untitled, Layout.untitled].map { Layout(name: $0) }
    var current = 0
    /// Window ID → layout index.
    var assignment: [String: Int] = [:]
    /// Window ID → frame it returns to when its layout is shown again (AX coordinates).
    var saved: [String: CGRect] = [:]
    /// Bundle ID → layout index for new windows.
    var routes: [String: Int] = [:]
    var pinned: Set<String> = []
    var statusStyle: StatusStyle = .numberAndName
    var hideOtherLayouts = true
    var workspaces: [Workspace] = []
    /// Name of the workspace last saved or loaded.
    var currentWorkspace: String?
    /// Displays that were disconnected, with what was on them.
    var shelf: [ShelfEntry] = []
    /// The AI Recipes endpoint. The API key lives in the Keychain, never here.
    var ai = AISettings()
    /// Off lets the middle button through to apps (for example, opening links in a new browser tab).
    var middleClickWheel = true
    /// Three-finger tap opens the Snap Wheel. nil: on, unless macOS uses that tap for Look Up.
    var trackpadTapWheel: Bool?
    /// A three-finger swipe left or right moves to the next or previous layout.
    var swipeLayouts = false
    /// The green button fills the screen in the window's layout instead of giving it a full-screen desktop of its own.
    var keepFullScreenHere = true
    /// The last known app, title, layout and frame of each open window, so it can be found again after a restart.
    var records: [String: WindowRecord] = [:]
    /// Windows whose app quit (or whose Mac restarted). A matching window that opens later goes back to its place.
    var orphans: [WindowRecord] = []
    /// "When an app in a layout isn't running": keep its Bento tile empty, or let other windows use it.
    var keepEmptySpace = true
    /// The Snap Wheel's outer ring, clockwise from the top. `nil` is a hidden slot.
    var wheelSlots: [WheelAction?] = WheelAction.defaults
    /// Shortcut rows changed from their defaults, by ShortcutID.
    var shortcuts: [String: Combo] = [:]
    /// Shortcut rows cleared with ⌫.
    var clearedShortcuts: Set<String> = []
    var isoKeyboard = false
    /// Tabs Mode groups, keyed "layout|display UUID".
    var tabs: [String: TabGroups] = [:]
    /// Dock mode trees, keyed "layout|display UUID".
    var docks: [String: DockLayout] = [:]
    var prefs = Prefs.releaseDefaults
}

extension DeskState {
    var trackpadTapOn: Bool { trackpadTapWheel ?? !TrackpadTap.systemUsesThreeFingerTap }
}

struct AISettings: Codable, Equatable {
    var preset = AIPreset.ollama
    var endpoint = AIPreset.ollama.endpoint
    var model = ""

    var configured: Bool { !endpoint.isEmpty && !model.isEmpty }
}

enum AIPreset: String, Codable, CaseIterable {
    case ollama = "Ollama", lmStudio = "LM Studio", custom = "OpenAI-compatible"

    var title: String { self == .custom ? String(localized: "OpenAI-compatible") : rawValue }

    var endpoint: String {
        switch self {
        case .ollama: "http://localhost:11434/v1"
        case .lmStudio: "http://localhost:1234/v1"
        case .custom: ""
        }
    }
}

extension DeskState {
    /// Every key is optional, so a state.json written by an older version still loads instead of resetting.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ value: inout T) throws {
            if let v = try c.decodeIfPresent(T.self, forKey: key) { value = v }
        }
        try read(.layouts, &layouts); try read(.current, &current); try read(.assignment, &assignment)
        try read(.saved, &saved); try read(.routes, &routes); try read(.pinned, &pinned)
        try read(.statusStyle, &statusStyle); try read(.hideOtherLayouts, &hideOtherLayouts)
        try read(.workspaces, &workspaces); try read(.shelf, &shelf); try read(.ai, &ai); try read(.middleClickWheel, &middleClickWheel)
        trackpadTapWheel = try c.decodeIfPresent(Bool.self, forKey: .trackpadTapWheel)
        try read(.swipeLayouts, &swipeLayouts); try read(.keepFullScreenHere, &keepFullScreenHere)
        try read(.records, &records); try read(.orphans, &orphans); try read(.keepEmptySpace, &keepEmptySpace)
        try read(.wheelSlots, &wheelSlots); try read(.shortcuts, &shortcuts)
        try read(.clearedShortcuts, &clearedShortcuts); try read(.isoKeyboard, &isoKeyboard)
        try read(.tabs, &tabs); try read(.docks, &docks); try read(.prefs, &prefs)
        currentWorkspace = try c.decodeIfPresent(String.self, forKey: .currentWorkspace)
    }
}

/// A window as Bower can find it again after its app or the Mac restarts: by app and title, not by window ID.
struct WindowRecord: Codable {
    var bundleID: String
    var title: String
    var layout: Int
    /// AX coordinates; for the shelf, relative to the display's top-left.
    var frame: CGRect
    var key: String?
    /// UUID of the display it was on.
    var display: String?
    /// The app's process when the record was made; a new process means the app quit, even if it relaunched at once.
    var pid: Int32?
    /// The open document and the app's own window name, when the app reports them: the surest way to know a window again.
    var document: String?
    var identifier: String?
    /// When the window was closed (for "Also when reopened", kept a day).
    var closedAt: Date?
}

/// A window and a record are the same one: same app and AXIdentifier, or same open document.
func sameIdentity(_ w: Win, _ r: WindowRecord) -> Bool {
    guard r.bundleID == w.bundleID else { return false }
    if let i = r.identifier, i == w.identifier { return true }
    if let d = r.document, d == w.document { return true }
    return false
}

struct DisplayRecord: Codable {
    var uuid: String
    var name: String
    var size: CGSize
}

/// Workspaces.dc.html: a snapshot of every layout on every display.
struct Workspace: Codable {
    var name: String
    var saved: Date
    var layouts: [Layout]
    var current: Int
    var displays: [DisplayRecord]
    var windows: [WindowRecord]
    var pinned: Set<String>
    var routes: [String: Int]

    var layoutsInUse: Int { Set(windows.map(\.layout)).count }
    var apps: Int { Set(windows.map(\.bundleID)).count }
}

/// SetDisplays.dc.html's Offline shelf: a disconnected display and the windows that were on it.
struct ShelfEntry: Codable {
    var display: DisplayRecord
    var lastSeen: Date
    var windows: [WindowRecord]
    /// The display's Window Mode in each layout.
    var modes: [Int: WindowMode]
}

/// Edge and Chrome end a window's title with " - <app> - <profile>". That end stays put while the page changes,
/// so it tells a browser's profile windows apart after the browser reopens.
func profileSuffix(of title: String, app: String) -> String? {
    title.range(of: " - \(app) - ", options: .backwards).map { String(title[$0.lowerBound...]) }
}

/// Same app, and the record's title ends with the window's profile.
func sameProfile(_ w: Win, _ r: WindowRecord) -> Bool {
    r.bundleID == w.bundleID && profileSuffix(of: w.title, app: w.appName).map(r.title.hasSuffix) == true
}

extension Array where Element == WindowRecord {
    /// Pairs live windows with records: same window ID first, then same app and title, then same profile, then same app.
    func match(_ wins: [Win]) -> [(Win, WindowRecord)] {
        var left = self
        var out: [(Win, WindowRecord)] = []
        let passes: [(Win, WindowRecord) -> Bool] = [
            { w, r in r.key == w.key },
            sameIdentity,
            { w, r in r.bundleID == w.bundleID && r.title == w.title },
            sameProfile,
            { w, r in r.bundleID == w.bundleID }
        ]
        var unmatched = wins
        for pass in passes {
            unmatched = unmatched.filter { w in
                guard let i = left.firstIndex(where: { pass(w, $0) }) else { return true }
                out.append((w, left.remove(at: i)))
                return false
            }
        }
        return out
    }
}

final class Store: ObservableObject {
    @Published private(set) var state: DeskState
    private let url: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Bower", isDirectory: true)) {
        url = directory.appendingPathComponent("state.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        state = (try? JSONDecoder().decode(DeskState.self, from: Data(contentsOf: url))) ?? DeskState()
    }

    private var savePending = false

    /// Changes are written once per run-loop pass, so a layout switch touching many windows writes once.
    func update(_ change: (inout DeskState) -> Void) {
        change(&state)
        guard !savePending else { return }
        savePending = true
        DispatchQueue.main.async { self.flush() }
    }

    func flush() {
        savePending = false
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(state).write(to: url, options: .atomic)
    }
}
