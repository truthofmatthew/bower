import AppKit

/// A three-finger tap on the trackpad opens the Snap Wheel (Paneo's "flick the trackpad"); a three-finger swipe
/// left or right changes layout.
///
/// macOS has no public API for raw trackpad touches, so this reads them from the private MultitouchSupport
/// framework, loaded at runtime. If the framework or its symbols are missing, the gesture is simply unavailable.
final class TrackpadTap {
    static let shared = TrackpadTap()

    var onTap: () -> Void = {}
    var enabled: () -> Bool = { true }
    /// +1 for a swipe to the left (the next layout, as desktops move), -1 to the right.
    var onSwipe: (Int) -> Void = { _ in }
    var swipeEnabled: () -> Bool = { false }
    private(set) var available = false

    // MultitouchSupport's per-finger record, laid out as in its C headers (96 bytes).
    private struct Finger {
        var frame: Int32
        var timestamp: Double
        var identifier: Int32
        var state: Int32
        var unknown1: Int32
        var unknown2: Int32
        var x: Float, y: Float, vx: Float, vy: Float  // normalized position and velocity
        var size: Float
        var zero1: Int32
        var angle: Float, majorAxis: Float, minorAxis: Float
        var mmX: Float, mmY: Float, mmVX: Float, mmVY: Float
        var zero2: (Int32, Int32)
        var unknown3: Float
    }

    private typealias Callback = @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void

    // Gesture state; only touched on the framework's callback thread.
    private var started: Double?
    private var maxFingers = 0
    private var origin: [Int32: (Float, Float)] = [:]
    private var last: [Int32: (Float, Float)] = [:]
    private var moved: Float = 0

    /// Whether macOS already uses a three-finger tap (System Settings › Trackpad › Look up & data detectors).
    /// Whether macOS moves between desktops with a three-finger horizontal swipe (Trackpad › More Gestures).
    static var systemUsesThreeFingerSwipe: Bool {
        ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"].contains {
            UserDefaults(suiteName: $0)?.integer(forKey: "TrackpadThreeFingerHorizSwipeGesture") == 2
        }
    }

    static var systemUsesThreeFingerTap: Bool {
        ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"].contains {
            UserDefaults(suiteName: $0)?.integer(forKey: "TrackpadThreeFingerTapGesture") == 2
        }
    }

    /// Each finger's travel across the pad (0–1 units) → +1 for a swipe left, -1 for right, nil for no swipe.
    /// A swipe's average travel is mostly sideways and covers an eighth of the pad.
    static func swipe(_ travel: [(Float, Float)]) -> Int? {
        guard !travel.isEmpty else { return nil }
        let dx = travel.map(\.0).reduce(0, +) / Float(travel.count), dy = travel.map(\.1).reduce(0, +) / Float(travel.count)
        guard abs(dx) > 0.12, abs(dx) > 2 * abs(dy) else { return nil }
        return dx < 0 ? 1 : -1
    }

    func start() {
        guard !available,
              let lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY),
              let createSym = dlsym(lib, "MTDeviceCreateList"),
              let registerSym = dlsym(lib, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(lib, "MTDeviceStart") else { return }
        let createList = unsafeBitCast(createSym, to: CreateList.self)
        let register = unsafeBitCast(registerSym, to: Register.self)
        let startDevice = unsafeBitCast(startSym, to: Start.self)
        guard let devices = createList()?.takeRetainedValue() as? [AnyObject], !devices.isEmpty else { return }
        for d in devices {
            let ptr = Unmanaged.passUnretained(d).toOpaque()
            register(ptr) { _, data, count, timestamp, _ in
                TrackpadTap.shared.frame(data, Int(count), timestamp)
                return 0
            }
            startDevice(ptr, 0)
        }
        available = true
    }

    private func frame(_ data: UnsafeMutableRawPointer?, _ count: Int, _ time: Double) {
        let fingers = data.map { UnsafeBufferPointer(start: $0.assumingMemoryBound(to: Finger.self), count: count) }
        if count > 0 {
            if started == nil { started = time; maxFingers = 0; origin = [:]; last = [:]; moved = 0 }
            maxFingers = max(maxFingers, count)
            for f in fingers ?? UnsafeBufferPointer(start: nil, count: 0) {
                if let o = origin[f.identifier] { moved = max(moved, hypot(f.x - o.0, f.y - o.1)) } else { origin[f.identifier] = (f.x, f.y) }
                last[f.identifier] = (f.x, f.y)
            }
            return
        }
        // All fingers lifted: exactly three, quick, and barely moving is a tap; swipes move, clicks press longer.
        defer { started = nil }
        guard let t0 = started, maxFingers == 3 else { return }
        if time - t0 < 0.3, moved < 0.04 {
            DispatchQueue.main.async { if self.enabled() { self.onTap() } }
            return
        }
        let travel = origin.compactMap { id, o in last[id].map { ($0.0 - o.0, $0.1 - o.1) } }
        guard time - t0 < 1.2, let d = Self.swipe(travel) else { return }
        DispatchQueue.main.async { if self.swipeEnabled() { self.onSwipe(d) } }
    }
}
