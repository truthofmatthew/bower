import AppKit

/// Settings and state added with the docking, zoom and gesture features. Kept apart from `DeskState`'s older
/// fields so it reads as one group in state.json; every key is optional, as there.
struct Prefs: Codable {
    // Gestures
    /// Fingers that move between layouts: macOS's own Spaces swipe is taken over when it uses the same count.
    var swipeFingers = 3
    /// Swipe the other way round.
    var swipeInvert = false
    var pinchZoom = true
    /// Without ⌥, a pinch only zooms over bare desktop.
    var pinchNeedsOption = true
    /// Pinch steps a level at a time instead of zooming freely.
    var pinchSteps = true
    var panSpeed = 1.8
    var replaceMissionControl = false
    var marqueeZoom = true

    // Docking (Dock mode)
    var gap = 6.0
    var gapHandles = true
    var gapHandlesAlwaysShown = false
    /// Closing a window gives its space to the whole row, so closing exactly undoes adding it.
    var shareRemovedSpace = true
    var squeezeBelowMinimum = false
    /// A window too small for its tile shows as its app icon until there's room.
    var collapseSmall = true
    var greenButtonFloats = true
    var soleFloatTakesDesktop = true
    var hiddenDesktopReturns = false
    var dockIntoDesktop = false
    var doubleClickFrames = true
    var previewDrags = true
    var previewStyle = PreviewStyle.tinted
    var reflowWhileDragging = true
    var keepPushed = true
    /// Seconds a dragged window waits over a target before the layout makes room.
    var holdDelay = 0.35
    var parkSmall = false
    var arrangeDesktops = ArrangeDesktops.all
    /// Spaces (by ManagedSpaceID) Bower leaves alone, and ones turned on when `arrangeDesktops` is first-only.
    var offSpaces: Set<String> = []
    var onSpaces: Set<String> = []
    var ignoredApps: Set<String> = []
    /// "layout|display" keys whose Desktop tile is hidden.
    var desktopHidden: Set<String> = []
    /// …and whose Desktop tile shows even with nothing floating on it.
    var desktopShown: Set<String> = []

    // Motion and appearance
    var animationSpeed = 1.0
    var interruptAnimations = true
    var redrawWait = 0.5
    var stretchPictures = false
    var dimBehind = false
    var dimOpacity = 0.3
    var dimBlur = 20.0
    var appColours = true
    var appColourAmount = 0.25
    var previewLook = PreviewLook.pictureUnderColour
    /// A line or a soft glow round the focused window.
    var focusRing = false
    var focusRingStyle = FocusRingStyle.outline
    var focusRingColour = FocusRingColour.accent
    var focusRingWidth = 3.0
    /// Light or dark for Bower's own windows; automatic follows macOS.
    var appearance = BowerAppearance.automatic

    // Space kept free along each screen edge (points), for a widget bar or a dock of your own.
    var reserveTop = 0.0
    var reserveBottom = 0.0
    var reserveLeft = 0.0
    var reserveRight = 0.0

    // Tab strips
    var tabStyle = TabStyle.material
    var tabSelectedChip = true
    var tabChipMargin = 4.0
    var tabInset = 2.0
    var tabPadding = 8.0
    var tabTint = 0.0
    var tabStripLights = false
    var tabCloseButtons = true
    var tabCloseOnRight = false
    var tabGlassOpaqueWhenInactive = true
    var tuckStrips = false
    var windowButtonsActOnGroup = true

    // Windows coming back
    var returnWindows = ReturnWindows.afterQuit
    /// Windows closed while their app kept running, for "Also when reopened" (kept a day).
    var closed: [WindowRecord] = []

    // Views and history
    var views: [Int: SavedView] = [:]
    /// No longer used: Back and Forward each have their own switch in the menu bar list. Kept so old files decode.
    var historyButtons = true
    var menuControls: [MenuControl] = [.layout]
    var menuBarFill = 0.12

    // App
    var showAdvanced = false
    /// Off by default: Bower makes no network requests unless asked.
    var checkUpdates = false
    var betaUpdates = false
    var updateReminders = true
    var lessonsDone: Set<String> = []
    var lastWhatsNew = ""
    /// What Bower turned off, so it can be turned back on (also after a crash).
    var turnedOff: [String: Int] = [:]
    var hotkeysTakenOver: [Int] = []

    init() {}
}

enum PreviewStyle: String, Codable, CaseIterable { case tinted, picture }
enum PreviewLook: String, Codable, CaseIterable { case pictureUnderColour, colourAndIcon }
enum ArrangeDesktops: String, Codable, CaseIterable { case firstOnly, all }
enum TabStyle: String, Codable, CaseIterable { case material, glass, solid }
enum ReturnWindows: String, Codable, CaseIterable { case never, afterQuit, alsoReopened }
enum FocusRingStyle: String, Codable, CaseIterable { case outline, halo }
enum FocusRingColour: String, Codable, CaseIterable { case accent, blue, purple, pink, orange, yellow, green }
enum BowerAppearance: String, Codable, CaseIterable { case automatic, light, dark }

/// Buttons Bower can put in the menu bar, in the order chosen.
enum MenuControl: String, Codable, CaseIterable {
    case layout, everything, back, forward, views

    var title: String {
        switch self {
        case .layout: String(localized: "Layout")
        case .everything: String(localized: "Overview")
        case .back: String(localized: "Back")
        case .forward: String(localized: "Forward")
        case .views: String(localized: "Saved Views")
        }
    }
}

/// What a saved view (or a history step) brings back: a layout, the part of each display's tree in view, a window.
struct SavedView: Codable, Equatable {
    var name: String
    var layout: Int
    /// Display UUID → zoomed node path in that display's Dock tree; empty is the whole tree.
    var zoom: [String: [Int]] = [:]
    var focused: String?
}

extension Prefs {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func r<T: Decodable>(_ k: CodingKeys, _ v: inout T) { if let x = try? c.decodeIfPresent(T.self, forKey: k) { v = x } }
        r(.swipeFingers, &swipeFingers); r(.swipeInvert, &swipeInvert); r(.pinchZoom, &pinchZoom)
        r(.pinchNeedsOption, &pinchNeedsOption); r(.pinchSteps, &pinchSteps); r(.panSpeed, &panSpeed)
        r(.replaceMissionControl, &replaceMissionControl); r(.marqueeZoom, &marqueeZoom)
        r(.gap, &gap); r(.gapHandles, &gapHandles); r(.gapHandlesAlwaysShown, &gapHandlesAlwaysShown)
        r(.shareRemovedSpace, &shareRemovedSpace); r(.squeezeBelowMinimum, &squeezeBelowMinimum); r(.collapseSmall, &collapseSmall)
        r(.greenButtonFloats, &greenButtonFloats); r(.soleFloatTakesDesktop, &soleFloatTakesDesktop)
        r(.hiddenDesktopReturns, &hiddenDesktopReturns); r(.dockIntoDesktop, &dockIntoDesktop); r(.doubleClickFrames, &doubleClickFrames)
        r(.previewDrags, &previewDrags); r(.previewStyle, &previewStyle); r(.reflowWhileDragging, &reflowWhileDragging)
        r(.keepPushed, &keepPushed); r(.holdDelay, &holdDelay); r(.parkSmall, &parkSmall); r(.arrangeDesktops, &arrangeDesktops)
        r(.offSpaces, &offSpaces); r(.onSpaces, &onSpaces); r(.ignoredApps, &ignoredApps); r(.desktopHidden, &desktopHidden); r(.desktopShown, &desktopShown)
        r(.animationSpeed, &animationSpeed); r(.interruptAnimations, &interruptAnimations); r(.redrawWait, &redrawWait)
        r(.stretchPictures, &stretchPictures); r(.dimBehind, &dimBehind); r(.dimOpacity, &dimOpacity); r(.dimBlur, &dimBlur)
        r(.appColours, &appColours); r(.appColourAmount, &appColourAmount); r(.previewLook, &previewLook)
        r(.focusRing, &focusRing); r(.focusRingStyle, &focusRingStyle); r(.focusRingColour, &focusRingColour)
        r(.focusRingWidth, &focusRingWidth); r(.appearance, &appearance)
        r(.reserveTop, &reserveTop); r(.reserveBottom, &reserveBottom); r(.reserveLeft, &reserveLeft); r(.reserveRight, &reserveRight)
        r(.tabStyle, &tabStyle); r(.tabSelectedChip, &tabSelectedChip); r(.tabChipMargin, &tabChipMargin); r(.tabInset, &tabInset)
        r(.tabPadding, &tabPadding); r(.tabTint, &tabTint); r(.tabStripLights, &tabStripLights); r(.tabCloseButtons, &tabCloseButtons)
        r(.tabCloseOnRight, &tabCloseOnRight); r(.tabGlassOpaqueWhenInactive, &tabGlassOpaqueWhenInactive); r(.tuckStrips, &tuckStrips)
        r(.windowButtonsActOnGroup, &windowButtonsActOnGroup); r(.returnWindows, &returnWindows); r(.closed, &closed)
        r(.views, &views); r(.historyButtons, &historyButtons); r(.menuControls, &menuControls); r(.menuBarFill, &menuBarFill)
        r(.showAdvanced, &showAdvanced); r(.checkUpdates, &checkUpdates); r(.betaUpdates, &betaUpdates)
        r(.updateReminders, &updateReminders); r(.lessonsDone, &lessonsDone); r(.lastWhatsNew, &lastWhatsNew)
        r(.turnedOff, &turnedOff); r(.hotkeysTakenOver, &hotkeysTakenOver)
    }
}

extension Engine {
    /// Changes one or more of the newer settings and tells everything that listens.
    func setPrefs(_ change: (inout Prefs) -> Void) {
        store.update { change(&$0.prefs) }
        onChange()
    }
}
