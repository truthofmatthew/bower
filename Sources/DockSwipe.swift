import AppKit

/// Takes macOS's own sideways Spaces swipe and uses it to move between layouts, so the two never both happen.
///
/// The Dock gets trackpad swipes as event type 30 (Dock control), with type 29 (gesture) around them. An active
/// session tap reads them first: a sideways swipe Bower can act on is dropped, so macOS never sees it, and runs
/// `onStep` when the fingers lift. A swipe Bower can't use (no layout that way, fn held, turned off) is handed
/// back to macOS untouched, including the events held while deciding.
///
/// Fields, as macOS fills them (not public; read the same way by other window managers):
/// 110 = HID event type (23 is a Dock swipe), 123 = motion (1 sideways, 2 up and down), 132 = phase
/// (1 began, 2 changed, 4 ended, 8 cancelled), 124 = progress, 129 = velocity.
final class DockSwipe {
    static let shared = DockSwipe()

    /// Whether to act on swipes at all (Settings › Gestures).
    var enabled: () -> Bool = { false }
    /// Whether there's a layout in that direction (+1 next, -1 previous); if not, macOS gets the swipe.
    var canStep: (Int) -> Bool = { _ in true }
    var onStep: (Int) -> Void = { _ in }
    /// Swiping up the way Mission Control opens: Bower's overview instead, when that's on.
    var takesMissionControl: () -> Bool = { false }
    var onMissionControl: () -> Void = {}
    var inverted: () -> Bool = { false }
    /// Live progress while Bower owns a swipe (-1…1), for the slide animation.
    var onProgress: (Double) -> Void = { _ in }
    private(set) var running = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private enum Owner { case undecided, bower, macOS }
    private var owner = Owner.macOS
    private var held: [CGEvent] = []
    private var progress = 0.0
    private var velocity = 0.0
    private var vertical = false

    private static let dockControl = CGEventType(rawValue: 30)!
    private static let gesture = CGEventType(rawValue: 29)!
    private enum F {
        static let hidType = CGEventField(rawValue: 110)!
        static let motion = CGEventField(rawValue: 123)!
        static let progress = CGEventField(rawValue: 124)!
        static let velocity = CGEventField(rawValue: 129)!
        static let phase = CGEventField(rawValue: 132)!
    }
    private static let dockSwipe: Int64 = 23

    /// Installs the tap; false without Accessibility or if macOS refuses (then the MultitouchSupport swipe is used).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return running }
        let mask = CGEventMask(1 << 30) | CGEventMask(1 << 29)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: { proxy, type, event, refcon in
            let me = Unmanaged<DockSwipe>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(proxy, type, event)
        }, userInfo: me) else {
            Log.info("swipe: tap not installed")
            return false
        }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        running = true
        return true
    }

    func stop() {
        guard let t = tap else { return }
        CGEvent.tapEnable(tap: t, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        running = false
    }

    private func handle(_ proxy: CGEventTapProxy, _ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(e)
        }
        // Gesture envelopes travel with whatever the swipe's owner decided.
        if type == Self.gesture { return owner == .bower ? nil : Unmanaged.passUnretained(e) }
        guard type == Self.dockControl, e.getIntegerValueField(F.hidType) == Self.dockSwipe else { return Unmanaged.passUnretained(e) }

        let phase = e.getIntegerValueField(F.phase)
        if phase == 1 {
            held = []
            progress = 0
            velocity = 0
            vertical = e.getIntegerValueField(F.motion) == 2
            // fn keeps macOS's own swipe, as Trellis does.
            let fn = e.flags.contains(.maskSecondaryFn)
            owner = fn || !(vertical ? takesMissionControl() : enabled()) ? .macOS : .undecided
        }
        if owner == .macOS { return Unmanaged.passUnretained(e) }

        progress = e.getDoubleValueField(F.progress)
        velocity = e.getDoubleValueField(F.velocity)

        if owner == .undecided {
            if vertical {
                owner = .bower
            } else if abs(progress) > 0.001 {
                // The direction is known once the fingers move: keep the swipe only if there's a layout that way.
                if canStep(direction(progress)) {
                    owner = .bower
                } else {
                    owner = .macOS
                    for h in held { h.tapPostEvent(proxy) }
                    held = []
                    return Unmanaged.passUnretained(e)
                }
            } else if phase == 4 || phase == 8 {
                // Ended without moving: macOS gets the whole gesture back, so the Dock isn't left mid-swipe.
                owner = .macOS
                for h in held { h.tapPostEvent(proxy) }
                held = []
                return Unmanaged.passUnretained(e)
            } else {
                if let copy = e.copy() { held.append(copy) }
                return nil
            }
        }

        if !vertical { DispatchQueue.main.async { [p = progress] in self.onProgress(p) } }
        if phase == 4 || phase == 8 {
            let p = progress, v = velocity, up = vertical
            DispatchQueue.main.async {
                if phase == 8 { self.onProgress(0); return }
                if up {
                    // Up is a negative progress; a short flick counts as much as a long push.
                    if p < -0.1 || v < -0.5 { self.onMissionControl() }
                } else if abs(p) > 0.15 || abs(v) > 0.5 {
                    self.onStep(self.direction(abs(p) > 0.15 ? p : v))
                } else {
                    self.onProgress(0)
                }
            }
            held = []
        }
        return nil
    }

    /// +1 (the next layout) for a swipe to the left, as desktops move.
    private func direction(_ p: Double) -> Int {
        let d = p > 0 ? 1 : -1
        return inverted() ? -d : d
    }

    // MARK: macOS trackpad settings

    private static let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]

    /// macOS's own trackpad gesture setting, from either the built-in or the Bluetooth trackpad's domain.
    static func trackpad(_ key: String) -> Int? {
        for d in domains { if let v = UserDefaults(suiteName: d)?.object(forKey: key) as? Int { return v } }
        return nil
    }

    /// Which swipes macOS currently uses `n` fingers for.
    struct SystemGestures: Equatable {
        var spaces = false        // sideways: switch between full-screen apps and desktops
        var missionControl = false // up and down: Mission Control and App Exposé
        var appsAndDesktop = false // four-finger pinch: Launchpad / show desktop
        var threeFingerDrag = false
    }

    static func system(fingers n: Int) -> SystemGestures {
        var g = SystemGestures()
        if n == 3 {
            g.spaces = trackpad("TrackpadThreeFingerHorizSwipeGesture") == 2
            g.missionControl = trackpad("TrackpadThreeFingerVertSwipeGesture") == 2
            g.threeFingerDrag = trackpad("TrackpadThreeFingerDrag") == 1
        } else {
            g.spaces = (trackpad("TrackpadFourFingerHorizSwipeGesture") ?? 2) == 2
            g.missionControl = (trackpad("TrackpadFourFingerVertSwipeGesture") ?? 2) == 2
            g.appsAndDesktop = (trackpad("TrackpadFourFingerPinchGesture") ?? 2) == 2
        }
        return g
    }

    /// What Settings says about taking the swipe over, in plain words, for the fingers chosen.
    static func explanation(fingers n: Int, missionControl: Bool) -> (text: String, needsSettings: Bool) {
        let g = system(fingers: n)
        if n == 3, g.threeFingerDrag {
            return (String(localized: "Needs three-finger drag turned off, in macOS Accessibility settings › Pointer Control › Trackpad Options."), true)
        }
        if !g.spaces {
            return (n == 3 ? String(localized: "Needs three-finger swipes turned on for switching desktops, in macOS Trackpad Settings › More Gestures. Until then Bower reads the swipe itself.")
                           : String(localized: "Needs four-finger swipes turned on for switching desktops, in macOS Trackpad Settings › More Gestures. Until then Bower reads the swipe itself."), true)
        }
        let what: String
        switch (n, missionControl && g.missionControl) {
        case (3, false): what = String(localized: "Three-finger swipes will move between layouts instead of switching desktops. Past the last layout, they switch desktops as before. Hold fn for macOS's own swipe.")
        case (3, true): what = String(localized: "Three-finger swipes will move between layouts, and swiping up shows Bower's overview instead of Mission Control. Hold fn for macOS's own.")
        case (_, false): what = String(localized: "Four-finger swipes will move between layouts instead of switching desktops. Past the last layout, they switch desktops as before. Hold fn for macOS's own swipe.")
        default: what = String(localized: "Four-finger swipes will move between layouts, and swiping up shows Bower's overview instead of Mission Control. Hold fn for macOS's own.")
        }
        return (what, false)
    }
}
