import AppKit
import QuartzCore

/// A line or a soft glow round the focused window (Settings › Appearance › Focused window). Drawn in a click-through
/// panel just above normal windows, which follows the window as it moves and resizes. It steps aside while the window
/// is parked, while Bower's own animations run, while the overview is open, and for full-screen windows.
final class FocusRing {
    static let shared = FocusRing()

    private var panel: OverlayPanel?
    private let root = CALayer()
    private let line = CAShapeLayer()
    private let cutout = CAShapeLayer()
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    /// The window the ring is round, so a move of it is followed without asking which window has focus.
    private var current: Win?
    private weak var engine: Engine?
    private var suppressed: () -> Bool = { false }
    private var started = false
    private var recheck: DispatchWorkItem?

    /// `suppressed`: Bower has something over the windows (the overview), so the ring waits.
    func start(engine: Engine, suppressed: @escaping () -> Bool) {
        self.engine = engine
        self.suppressed = suppressed
        guard !started else { return refresh() }
        started = true
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.accessibilityDisplayOptionsDidChangeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    /// Looks again at which window has focus and where it is.
    func refresh() {
        guard started, let engine, engine.state.prefs.focusRing else { return stop() }
        follow(AX.frontApp()?.pid)
        current = AX.focusedWindow()
        place()
    }

    private func place() {
        guard let engine, let w = current else { return hide() }
        // Waits out the overview and Bower's own moves, then looks again.
        if suppressed() || Motion.shared.animating {
            hide()
            return later()
        }
        guard let f = w.frame, !engine.isParked(f), f.width > 1, f.height > 1 else { return hide() }
        show(f, engine.state.prefs)
    }

    private func later() {
        recheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        recheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Watches the front app: focus moving to another of its windows, and its windows moving or resizing.
    private func follow(_ pid: pid_t?) {
        guard let pid, pid != observedPID, pid != ProcessInfo.processInfo.processIdentifier else { return }
        unobserve()
        observedPID = pid
        var obs: AXObserver?
        guard AXObserverCreate(pid, { _, element, note, refcon in
            guard let refcon else { return }
            Unmanaged<FocusRing>.fromOpaque(refcon).takeUnretainedValue().changed(element, note as String)
        }, &obs) == .success, let obs else { return }
        let app = AXUIElementCreateApplication(pid)
        let me = Unmanaged.passUnretained(self).toOpaque()
        for note in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXWindowMovedNotification,
                     kAXWindowResizedNotification, kAXWindowMiniaturizedNotification] {
            AXObserverAddNotification(obs, app, note as CFString, me)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
    }

    private func unobserve() {
        if let o = observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode) }
        observer = nil
        observedPID = 0
    }

    private func changed(_ element: AXUIElement, _ note: String) {
        // The ringed window moving: follow it without asking Accessibility which window has focus.
        if note == kAXWindowMovedNotification || note == kAXWindowResizedNotification {
            if let w = current, CFEqual(w.el, element) { place() }
            return
        }
        refresh()
    }

    private func stop() {
        recheck?.cancel()
        unobserve()
        current = nil
        hide()
    }

    private func hide() { panel?.orderOut(nil) }

    // MARK: Drawing

    private func makePanel() -> OverlayPanel {
        let p = OverlayPanel(level: NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1))
        // Hidden by Mission Control with the windows, rather than left standing over it.
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let host = NSView()
        host.wantsLayer = true
        host.layer = root
        root.addSublayer(line)
        line.fillColor = nil
        line.lineJoin = .round
        // Only outside the window: the ring never covers what's in it.
        cutout.fillRule = .evenOdd
        root.mask = cutout
        p.contentView = host
        panel = p
        return p
    }

    /// `f`: the window's frame, AX coordinates.
    private func show(_ f: CGRect, _ p: Prefs) {
        let panel = self.panel ?? makePanel()
        let wasHidden = !panel.isVisible
        // Reduce Transparency: a solid line instead of a glow.
        let halo = p.focusRingStyle == .halo && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let t = CGFloat(min(max(p.focusRingWidth, 1), 12))
        let pad = halo ? t * 4 + 6 : t + 2
        let frame = NSScreen.appKit(f).insetBy(dx: -pad, dy: -pad)
        let bounds = CGRect(origin: .zero, size: frame.size)
        let window = bounds.insetBy(dx: pad, dy: pad)
        let radius: CGFloat = 10
        let colour = Self.colour(p.focusRingColour)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = bounds
        line.frame = bounds
        cutout.frame = bounds
        let ring = window.insetBy(dx: -t / 2, dy: -t / 2)
        line.path = CGPath(roundedRect: ring, cornerWidth: radius + t / 2, cornerHeight: radius + t / 2, transform: nil)
        line.lineWidth = t
        line.strokeColor = colour.copy(alpha: halo ? 0.55 : 1)
        line.shadowColor = colour
        line.shadowOpacity = halo ? 1 : 0
        line.shadowRadius = halo ? t * 2 + 2 : 0
        line.shadowOffset = .zero
        let mask = CGMutablePath()
        mask.addRect(bounds)
        mask.addPath(CGPath(roundedRect: window, cornerWidth: radius, cornerHeight: radius, transform: nil))
        cutout.path = mask
        CATransaction.commit()

        panel.setFrame(frame, display: true)
        if wasHidden {
            panel.alphaValue = Theme.reduceMotion ? 1 : 0
            panel.orderFrontRegardless()
            if !Theme.reduceMotion {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    ctx.timingFunction = Theme.easeOut
                    panel.animator().alphaValue = 1
                }
            }
        }
    }

    /// The ring sits over other apps' windows, so it follows macOS's light or dark, not Bower's own windows' setting.
    static func colour(_ c: FocusRingColour) -> CGColor {
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let ns: NSColor
        switch c {
        case .accent: ns = dark ? Theme.hex(0x3FD3C2) : Theme.hex(0x0B7A72)
        case .blue: ns = .systemBlue
        case .purple: ns = .systemPurple
        case .pink: ns = .systemPink
        case .orange: ns = .systemOrange
        case .yellow: ns = .systemYellow
        case .green: ns = .systemGreen
        }
        var cg = ns.cgColor
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance { cg = ns.cgColor }
        return cg
    }
}
