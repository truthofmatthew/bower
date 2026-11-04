import AppKit

/// One active session tap for the mouse: title-bar drags (docking), double-clicks on a title bar (framing a
/// window), clicks on the green button (floating), ⌘⇧-drags (zoom to a rectangle), and a click that ends an
/// animation. Handlers return true to swallow the event; they must be quick, as every click waits on them.
///
/// Points are AX coordinates (top-left origin), the same as window frames.
final class EventTap {
    static let shared = EventTap()

    struct Handler {
        var down: (CGPoint, CGEvent) -> Bool = { _, _ in false }
        var dragged: (CGPoint, CGEvent) -> Bool = { _, _ in false }
        var up: (CGPoint, CGEvent) -> Bool = { _, _ in false }
        var scroll: (CGEvent) -> Bool = { _ in false }
        var magnify: (CGEvent) -> Bool = { _ in false }
    }

    private var handlers: [(name: String, h: Handler)] = []
    private var tap: CFMachPort?
    /// A swallowed mouse-down swallows its mouse-up too, so the app never sees half a click.
    private var swallowingUp = false

    func add(_ name: String, _ h: Handler) {
        handlers.removeAll { $0.name == name }
        handlers.append((name, h))
    }

    func start() {
        guard tap == nil else { return }
        var mask: CGEventMask = 0
        for t: CGEventType in [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .scrollWheel] { mask |= 1 << t.rawValue }
        mask |= 1 << 29  // gestures: pinch (magnify) arrives inside these
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: { _, type, e, refcon in
            Unmanaged<EventTap>.fromOpaque(refcon!).takeUnretainedValue().handle(type, e)
        }, userInfo: me) else {
            Log.info("event tap not installed")
            return
        }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    /// Marks events Bower posts itself (a click handed back after all), so the tap lets them through.
    static let replayMark: Int64 = 0xB0E1

    /// Posts a held mouse-down and its mouse-up again, for a press Bower took and then didn't use.
    static func replay(_ events: [CGEvent]) {
        for e in events {
            e.setIntegerValueField(.eventSourceUserData, value: replayMark)
            e.post(tap: .cgSessionEventTap)
        }
    }

    private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(e)
        if e.getIntegerValueField(.eventSourceUserData) == Self.replayMark { return pass }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .leftMouseDown:
            let p = e.location
            for h in handlers where h.h.down(p, e) { swallowingUp = true; return nil }
            swallowingUp = false
        case .leftMouseDragged:
            let p = e.location
            for h in handlers where h.h.dragged(p, e) { return nil }
        case .leftMouseUp:
            let p = e.location
            var swallow = swallowingUp
            for h in handlers where h.h.up(p, e) { swallow = true }
            swallowingUp = false
            if swallow { return nil }
        case .scrollWheel:
            for h in handlers where h.h.scroll(e) { return nil }
        default:
            if type.rawValue == 29, let ns = NSEvent(cgEvent: e), ns.type == .magnify {
                for h in handlers where h.h.magnify(e) { return nil }
            }
        }
        return pass
    }
}

extension CGEvent {
    var clicks: Int64 { getIntegerValueField(.mouseEventClickState) }
    var fn: Bool { flags.contains(.maskSecondaryFn) }
    var option: Bool { flags.contains(.maskAlternate) }
    var shift: Bool { flags.contains(.maskShift) }
    var command: Bool { flags.contains(.maskCommand) }
}
