import AppKit

/// The Snap Wheel: Wheel.dc.html, WheelScale.dc.html and WheelDesktop.dc.html.
final class WheelController {
    typealias Hit = WheelGeometry.Hit
    typealias Arc = WheelGeometry.Arc

    struct Inner { let action: SnapAction; let glyph: CGRect }

    static let inner: [Inner] = [
        Inner(action: .topHalf, glyph: CGRect(x: 0, y: 0, width: 1, height: 0.5)),
        Inner(action: .topRight, glyph: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
        Inner(action: .rightHalf, glyph: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)),
        Inner(action: .bottomRight, glyph: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
        Inner(action: .bottomHalf, glyph: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)),
        Inner(action: .bottomLeft, glyph: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
        Inner(action: .leftHalf, glyph: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
        Inner(action: .topLeft, glyph: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
    ]

    private static let thirds: [SnapAction] = [.firstThird, .centerThird, .lastThird]

    private let engine: Engine
    private let preview: SnapPreview
    private let layoutGhost = LayoutGhost()
    private let panel: WheelPanel
    private let view = WheelView()
    private var target: Win?
    private var screen: NSScreen?
    private var sticky = false
    private var openedAt = Date()
    private var openedMouse = NSPoint.zero
    private var arcDwell: DispatchWorkItem?
    private var arcAnim: Timer?

    var isOpen: Bool { panel.isVisible }
    var onOpen: () -> Void = {}
    var onSettings: () -> Void = {}
    var onRecipe: () -> Void = {}

    init(engine: Engine, preview: SnapPreview) {
        self.engine = engine
        self.preview = preview
        panel = WheelPanel(view: view)
        panel.onKey = { [weak self] in self?.key($0) }
        panel.onResign = { [weak self] in if self?.sticky == true { self?.close() } }
        view.onMove = { [weak self] in self?.hover(at: $0) }
        view.onClick = { [weak self] in self?.hover(at: $0); self?.release() }
    }

    /// The outer slots, from Settings › Snap Wheel. `nil` is a hidden slot.
    private func slot(_ i: Int) -> WheelAction? { engine.state.wheelSlots.indices.contains(i) ? engine.state.wheelSlots[i] : nil }
    private func hasArc(_ i: Int) -> Bool { slot(i)?.hasArc ?? false }

    /// AI Recipe needs an endpoint and model (Settings › AI).
    private func disabled(_ i: Int) -> Bool { slot(i) == .recipe && !engine.state.ai.configured }

    // MARK: Open and close

    /// `sticky`: opened from the keyboard or a click, so it stays open until a click, Return or Esc.
    /// `atPointer`: opened with the mouse or trackpad, so it acts on the window under the pointer (over the desktop,
    /// the focused one); from the keyboard, on the focused window.
    func open(sticky: Bool, atPointer: Bool = false) {
        let p = CGEvent(source: nil)?.location
        target = (atPointer ? p.flatMap(AX.hit).flatMap { AX.window(id: $0.id, pid: $0.pid) } : nil) ?? AX.focusedWindow()
        screen = NSScreen.underMouse
        self.sticky = sticky
        openedAt = Date()
        view.model = WheelView.Model()
        view.model.slots = engine.state.wheelSlots
        view.model.disabled = Set((0..<8).filter(disabled))
        refreshCaption()

        preview.hide()
        layoutGhost.hide()
        let m = NSEvent.mouseLocation
        openedMouse = m
        let c = WheelGeometry.center, size = WheelGeometry.panelSize
        var f = NSRect(x: m.x - c.x, y: m.y - (size.height - c.y), width: size.width, height: size.height)
        // Near a screen edge the wheel moves inward rather than getting cut off.
        if let v = (NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
            f.origin.x = min(max(f.minX, v.minX), v.maxX - f.width)
            f.origin.y = min(max(f.minY, v.minY), v.maxY - f.height)
        }
        panel.setFrame(f, display: false)
        panel.prepareAppearance()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.animateOpen(instant: sticky)
        onOpen()
    }

    /// The shortcut again: closes the wheel, or, when the pointer has moved since it opened, brings it to the pointer.
    func toggle(atPointer: Bool = false) {
        let m = NSEvent.mouseLocation
        if isOpen, hypot(m.x - openedMouse.x, m.y - openedMouse.y) < 40 { close() } else { open(sticky: true, atPointer: atPointer) }
    }

    func close() {
        arcDwell?.cancel()
        arcAnim?.invalidate()
        preview.hide()
        layoutGhost.hide()
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            ctx.timingFunction = Theme.easeOut
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in panel.orderOut(nil) })
    }

    // MARK: Pointer

    /// `p` is in the wheel view's flipped coordinates.
    func hover(at p: CGPoint) {
        let hit = WheelGeometry.hit(p, arc: view.model.arc)
        guard hit != view.model.hover else { return }
        view.model.hover = hit
        view.model.focus = nil
        switch hit {
        case .outer(let i) where hasArc(i):
            if view.model.arc?.parent != i { scheduleArc(for: i) }
        case .arc:
            break
        default:
            arcDwell?.cancel()
            if view.model.arc != nil { setArc(nil) }
        }
        refreshCaption()
        refreshGhost()
        view.needsDisplay = true
    }

    /// Global AppKit point, from the middle-button event tap.
    func hover(global g: CGPoint) {
        hover(at: CGPoint(x: g.x - panel.frame.minX, y: panel.frame.maxY - g.y))
    }

    /// Mouse-up after a press-drag-release, or a click in sticky mode.
    func release() {
        let hit = view.model.hover
        switch hit {
        case .cancel, .none:
            // A quick click without moving leaves the wheel open for a second, deliberate click.
            if !sticky, Date().timeIntervalSince(openedAt) < 0.3 { sticky = true } else { close() }
        case .outer(let i) where hasArc(i):
            sticky = true
            arcDwell?.cancel()
            setArc(arc(for: i))
        default:
            run(hit)
        }
    }

    // MARK: Keyboard

    private func key(_ e: NSEvent) {
        let m = view.model
        let cur = m.focus ?? m.hover
        switch Int(e.keyCode) {
        case 53:  // Esc
            if let arc = m.arc { setArc(nil); setFocus(.outer(arc.parent)) } else { close() }
        case 36, 76:  // Return, Enter
            if case .outer(let i) = cur, hasArc(i) { setArc(arc(for: i)); setFocus(.arc(0)) } else { run(cur) }
        case 48:  // Tab
            switch cur {
            case .inner(let i): setFocus(.outer(i))
            case .outer(let i): setArc(nil); setFocus(.inner(i))
            default: setFocus(.outer(0))
            }
        case 123, 124, 125, 126:
            let forward = e.keyCode == 124 || e.keyCode == 125
            switch cur {
            case .inner(let i): setFocus(.inner((i + (forward ? 1 : 7)) % 8))
            case .outer(let i):
                if e.keyCode == 124, hasArc(i) { setArc(arc(for: i)); setFocus(.arc(0)) } else {
                    setArc(nil)
                    setFocus(.outer((i + (forward ? 1 : 7)) % 8))
                }
            case .arc(let i):
                guard let arc = m.arc else { return }
                setFocus(.arc(min(max(i + (forward ? 1 : -1), 0), arc.count - 1)))
            default:
                // First arrow picks the wedge in that direction: ↑ top, → right, ↓ bottom, ← left.
                setFocus(.inner([123: 6, 124: 2, 125: 4, 126: 0][Int(e.keyCode)]!))
            }
        default:
            break
        }
    }

    private func setFocus(_ f: Hit) {
        view.model.focus = f
        view.model.hover = .none
        refreshCaption()
        refreshGhost()
        view.needsDisplay = true
    }

    // MARK: Arcs

    private func arc(for slot: Int) -> Arc {
        switch self.slot(slot) {
        case .layouts, .send: .layouts(slot)
        case .mode: .modes(slot)
        default: .three(slot)
        }
    }

    /// 150 ms dwell, then 100 ms opacity and radius 146 → 154.
    private func scheduleArc(for slot: Int) {
        arcDwell?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.view.model.hover == .outer(slot) else { return }
            self.setArc(self.arc(for: slot))
        }
        arcDwell = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func setArc(_ arc: Arc?) {
        arcAnim?.invalidate()
        view.model.arc = arc
        view.model.arcProgress = 0
        if let arc { fillArcLabels(arc) }
        refreshCaption()
        view.needsDisplay = true
        guard arc != nil else { return }
        let start = Date(), duration = Theme.reduceMotion ? 0.08 : 0.1
        arcAnim = Timer.scheduledTimer(withTimeInterval: 1 / 120, repeats: true) { [weak self] t in
            let k = min(Date().timeIntervalSince(start) / duration, 1)
            self?.view.model.arcProgress = CGFloat(1 - pow(1 - k, 3))  // ease-out cubic
            self?.view.needsDisplay = true
            if k >= 1 { t.invalidate() }
        }
    }

    private func fillArcLabels(_ arc: Arc) {
        let st = engine.state
        switch slot(arc.parent) {
        case .layouts, .send:
            view.model.arcLabels = (1...9).map(String.init)
            view.model.arcCurrent = slot(arc.parent) == .layouts ? st.current : nil
            view.model.arcDim = Set((0..<9).filter { $0 != st.current && st.layouts[$0].isUntitled })
        case .mode:
            let current = screen.map(engine.mode(of:)) ?? .native
            let all = WindowMode.allCases
            view.model.arcLabels = [String(localized: "Native"), String(localized: "Bento"), String(localized: "Tabs"), String(localized: "Dock")]
                .enumerated().map { all[$0.offset] == current ? $0.element + " ✓" : $0.element }
            view.model.arcCurrent = all.firstIndex(of: current)
            view.model.arcDim = []
        default:
            view.model.arcLabels = [String(localized: "First"), String(localized: "Center"), String(localized: "Last")]
            view.model.arcCurrent = nil
            view.model.arcDim = []
        }
    }

    // MARK: Caption and ghost

    private func refreshCaption() {
        let m = view.model
        let st = engine.state
        let focused = m.focus != nil
        var cap: (String, String)
        switch m.focus ?? m.hover {
        case .inner(let i):
            cap = (Self.inner[i].action.title, Self.inner[i].action.shortcut)
        case .outer(let i) where disabled(i):
            cap = (String(localized: "AI Recipe needs an endpoint · Settings › AI"), "⌘,")
        case .outer(let i):
            cap = slot(i).map { ($0.title, $0.key) } ?? (String(localized: "Hidden slot"), "")
        case .arc(let i):
            switch m.arc.flatMap({ slot($0.parent) }) {
            case .layouts: cap = (String(localized: "Layout \(i + 1) · \(st.layouts[i].name)"), "⌥\(i + 1)")
            case .send: cap = (String(localized: "Send to Layout \(i + 1) · \(st.layouts[i].name)"), "⇧⌥\(i + 1)")
            case .mode: cap = (String(localized: "\(WindowMode.allCases[i].title) on this display"), "↩")
            default: cap = (Self.thirds[i].title, Self.thirds[i].shortcut)
            }
        default:
            cap = (String(localized: "Release on an action"), String(localized: "esc"))
        }
        if focused { cap = (String(localized: "\(cap.0) · arrows move, Return runs"), "↩") }
        view.model.caption = cap
        if case .outer(let i) = m.focus ?? m.hover { view.model.captionDimmed = disabled(i) || slot(i) == nil } else { view.model.captionDimmed = false }
    }

    private func snapAction(_ hit: Hit) -> SnapAction? {
        switch hit {
        case .inner(let i): return Self.inner[i].action
        case .outer(let i) where slot(i) == .maximize: return .maximize
        case .arc(let i) where view.model.arc.flatMap({ slot($0.parent) }) == .thirds: return Self.thirds[i]
        default: return nil
        }
    }

    private func refreshGhost() {
        // Pointing at a layout in the Layouts or Send arc shows what that layout holds.
        if case .arc(let i) = view.model.focus ?? view.model.hover,
           let parent = view.model.arc.flatMap({ slot($0.parent) }), parent == .layouts || parent == .send,
           let s = screen ?? NSScreen.main {
            preview.hide()
            return layoutGhost.show(i, windows: engine.windows(in: i, on: s), on: s)
        }
        layoutGhost.hide()
        guard let w = target, let a = snapAction(view.model.focus ?? view.model.hover),
              let t = engine.target(a, for: w) else { return preview.hide() }
        let scale = t.screen.backingScaleFactor
        preview.show(t.frame, caption: (a.title, "\(Int(t.frame.width * scale)) × \(Int(t.frame.height * scale))"))
    }

    // MARK: Actions

    /// The action fires at t = 0; the wheel fades out over 60 ms after it.
    private func run(_ hit: Hit) {
        let arc = view.model.arc
        var ran = true
        switch hit {
        case .inner(let i): if let w = target { engine.snap(w, Self.inner[i].action) }
        case .outer(let i):
            switch slot(i) {
            case .settings: onSettings()
            case .recipe: if engine.state.ai.configured { onRecipe() } else { ran = false }
            case let a? where !a.hasArc: engine.perform(a, on: target, screen: screen)
            default: ran = false  // hidden slot
            }
        case .arc(let i):
            switch arc.flatMap({ slot($0.parent) }) {
            case .layouts: engine.switchTo(i)
            case .send: if let w = target { engine.send(w, to: i) }
            case .mode: if let s = screen { engine.setMode(WindowMode.allCases[i], for: s) } else { ran = false }
            case .thirds: if let w = target { engine.snap(w, Self.thirds[i]) }
            default: ran = false
            }
        default: ran = false
        }
        if !ran, !sticky { return close() }
        if !ran { return }
        preview.hide()
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.06; panel.animator().alphaValue = 0 },
                                             completionHandler: { [panel] in panel.orderOut(nil) })
    }
}

// MARK: - Panel

final class WheelPanel: NSPanel {
    var onKey: (NSEvent) -> Void = { _ in }
    var onResign: () -> Void = {}
    private let container = NSView()
    private let disc = NSVisualEffectView()
    private let shadow = CALayer()
    private let wheel: WheelView

    init(view: WheelView) {
        wheel = view
        super.init(contentRect: NSRect(origin: .zero, size: WheelGeometry.panelSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        container.frame = NSRect(origin: .zero, size: WheelGeometry.panelSize)
        container.wantsLayer = true
        // Disc: r 150 centred at (210, 210) from the top, i.e. y 100–400 from the bottom.
        let discFrame = NSRect(x: 60, y: WheelGeometry.panelSize.height - 360, width: 300, height: 300)
        shadow.frame = container.bounds
        shadow.shadowPath = CGPath(ellipseIn: discFrame, transform: nil)
        shadow.shadowOffset = CGSize(width: 0, height: -18)
        shadow.shadowRadius = 24
        shadow.shadowOpacity = 1
        container.layer?.addSublayer(shadow)
        disc.frame = discFrame
        disc.material = .hudWindow
        disc.blendingMode = .behindWindow
        disc.state = .active
        disc.maskImage = NSImage(size: discFrame.size, flipped: false) { r in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: r).fill()
            return true
        }
        container.addSubview(disc)
        view.frame = container.bounds
        container.addSubview(view)
        contentView = container
    }

    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { onKey(event) }
    override func resignKey() { super.resignKey(); onResign() }

    func prepareAppearance() {
        appearance = NSApp.effectiveAppearance
        // Increase Contrast / Reduce Transparency: an opaque disc drawn by the view instead of blur.
        disc.isHidden = Theme.highContrast
        shadow.shadowColor = WheelPalette.current(NSApp.effectiveAppearance).shadow.cgColor
        wheel.needsDisplay = true
    }

    /// 120 ms ease-out, opacity 0 → 1 and scale 0.92 → 1. Reduce Motion: 80 ms linear, opacity only.
    /// `instant` (opened from the keyboard): no animation, since it's repeated many times a day.
    func animateOpen(instant: Bool) {
        if instant { alphaValue = 1; return }
        let reduce = Theme.reduceMotion
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduce ? 0.08 : 0.12
            ctx.timingFunction = reduce ? CAMediaTimingFunction(name: .linear) : Theme.easeOut
            animator().alphaValue = 1
        }
        guard !reduce, let layer = container.layer else { return }
        // View-backed layers anchor at the bottom-left, so scale about the wheel's centre (the cursor) explicitly.
        let c = CGPoint(x: WheelGeometry.center.x, y: WheelGeometry.panelSize.height - WheelGeometry.center.y)
        var from = CATransform3DMakeTranslation(c.x, c.y, 0)
        from = CATransform3DScale(from, 0.92, 0.92, 1)
        from = CATransform3DTranslate(from, -c.x, -c.y, 0)
        let a = CABasicAnimation(keyPath: "sublayerTransform")
        a.fromValue = from
        a.toValue = CATransform3DIdentity
        a.duration = 0.12
        a.timingFunction = Theme.easeOut
        layer.add(a, forKey: "open")
    }
}

// MARK: - Drawing

class WheelView: NSView {
    typealias Hit = WheelGeometry.Hit

    struct Model {
        var hover: Hit = .none
        var focus: Hit?
        var arc: WheelGeometry.Arc?
        var arcProgress: CGFloat = 0
        var arcLabels: [String] = []
        var arcCurrent: Int?
        var arcDim: Set<Int> = []
        var disabled: Set<Int> = []
        var slots: [WheelAction?] = WheelAction.defaults
        /// Settings › Snap Wheel: hidden slots show a +, and a dragged action's target slot is outlined.
        var editing = false
        var dropSlot: Int?
        var caption = (String(localized: "Release on an action"), String(localized: "esc"))
        var captionDimmed = false
    }

    var model = Model()
    var onMove: (CGPoint) -> Void = { _ in }
    var onClick: (CGPoint) -> Void = { _ in }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { onMove(convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { onMove(convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) { onClick(convert(event.locationInWindow, from: nil)) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let K = WheelPalette.current(effectiveAppearance)
        let hc = Theme.highContrast
        let base = hc ? K.fillHC : K.fill
        let edge: NSColor? = hc ? K.lineHC : nil
        let lab2 = hc ? K.label : K.label2
        let G = WheelGeometry.self
        let c = G.center

        // Disc: the blur view sits underneath; Increase Contrast draws it opaque here. 0.5 pt hairline either way.
        let discRect = CGRect(x: c.x - 150, y: c.y - 150, width: 300, height: 300)
        // The editor has no blur view behind it, so it draws the disc's tint itself.
        if hc || model.editing { fill(ctx, CGPath(ellipseIn: discRect, transform: nil), hc ? K.hudHC : K.hud) }
        stroke(ctx, CGPath(ellipseIn: discRect.insetBy(dx: -0.25, dy: -0.25), transform: nil), hc ? K.lineHC : K.line, 0.5)

        // Third arc
        if let arc = model.arc {
            let k = model.arcProgress
            ctx.saveGState()
            ctx.setAlpha(k)
            let grow = Theme.reduceMotion ? 0 : (1 - k) * -8  // r 146 → 154
            let r0 = arc.r0 + grow, r1 = arc.r1 + grow
            let half = G.rad(arc.step / 2)
            for i in 0..<arc.count {
                let a = arc.angle(i)
                let hov = model.hover == .arc(i) || model.focus == .arc(i)
                let cur = model.arcCurrent == i
                let dim = model.arcDim.contains(i)
                let path = G.sector(r0, r1, a - half, a + half)
                fill(ctx, path, hov && !dim ? K.accent : cur ? K.subCur : K.sub)
                stroke(ctx, path, hc ? K.lineHC : K.line, hc ? 1 : 0.5)
                let color = hov && !dim ? K.on : cur ? K.accent : dim ? K.label3 : K.label
                let label = i < model.arcLabels.count ? model.arcLabels[i] : ""
                text(label, at: G.point((r0 + r1) / 2, a), size: arc.count == 9 ? 14 : 12, weight: .semibold, color: color)
            }
            ctx.restoreGState()
        }

        // Inner ring: 8 wedges, each with a small screen glyph.
        for (i, w) in WheelController.inner.enumerated() {
            let a = G.angle(i)
            let hov = model.hover == .inner(i), foc = model.focus == .inner(i)
            let path = G.slotSector(i, G.inner)
            fill(ctx, path, hov ? K.accent : foc ? K.tint : base)
            if let edge, !hov { stroke(ctx, path, edge, 1) }
            if foc { stroke(ctx, G.sector(41, 87, a - G.rad(22.5), a + G.rad(22.5)), K.accent, 2) }
            let p = G.point(G.innerGlyphRadius, a)
            stroke(ctx, CGPath(roundedRect: CGRect(x: p.x - 9, y: p.y - 6, width: 18, height: 12), cornerWidth: 2, cornerHeight: 2, transform: nil),
                   hov ? K.on : lab2, 1.2)
            let f = w.glyph
            let g = CGRect(x: p.x - 7 + f.minX * 14, y: p.y - 4 + f.minY * 8, width: f.width * 14, height: f.height * 8)
            fill(ctx, CGPath(roundedRect: g, cornerWidth: 0.75, cornerHeight: 0.75, transform: nil), hov ? K.on : foc ? K.accent : K.label)
        }

        // Outer ring: 8 actions with 16 pt icons; ▸ marker on the ones with an arc.
        for i in 0..<8 {
            let a = G.angle(i)
            let action = i < model.slots.count ? model.slots[i] : nil
            let hidden = action == nil
            let drop = model.dropSlot == i
            let hov = model.hover == .outer(i) && !model.disabled.contains(i) && !hidden
            let foc = model.focus == .outer(i)
            let tinted = model.arc?.parent == i
            let disabled = model.disabled.contains(i)
            let path = G.slotSector(i, G.outer)
            if hidden && !drop {
                // A hidden slot: an empty dashed wedge.
                ctx.saveGState()
                ctx.setLineDash(phase: 0, lengths: [4, 3])
                stroke(ctx, path, K.label3, 1.5)
                ctx.restoreGState()
            } else {
                fill(ctx, path, hov ? K.accent : tinted || foc || drop ? K.tint : disabled ? K.fill2 : base)
                if drop {
                    ctx.saveGState()
                    ctx.setLineDash(phase: 0, lengths: [4, 3])
                    stroke(ctx, path, K.accent, 1.5)
                    ctx.restoreGState()
                } else if let edge, !hov { stroke(ctx, path, edge, 1) }
            }
            if foc { stroke(ctx, G.sector(95, 145, a - G.rad(22.5), a + G.rad(22.5)), K.accent, 2) }
            let ic = hov ? K.on : tinted || drop ? K.accent : disabled || hidden ? K.label3 : K.label
            let p = G.point(G.outerGlyphRadius, a)
            var t = CGAffineTransform(translationX: p.x - 8, y: p.y - 8)
            if let icon = (hidden ? (model.editing ? Icon.path(Icon.plus) : nil) : action?.icon)?.copy(using: &t) {
                ctx.addPath(icon)
                ctx.setStrokeColor(ic.cgColor)
                ctx.setLineWidth(1.5)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.strokePath()
            }
            if action?.hasArc == true {
                let chev = CGMutablePath()
                chev.move(to: G.point(143, a))
                chev.addLine(to: G.point(137.5, a - 3 / 137.5))
                chev.addLine(to: G.point(137.5, a + 3 / 137.5))
                chev.closeSubpath()
                fill(ctx, chev, ic)
            }
        }

        // Cancel centre
        let centre = CGPath(ellipseIn: CGRect(x: c.x - 32, y: c.y - 32, width: 64, height: 64), transform: nil)
        fill(ctx, centre, base)
        if let edge { stroke(ctx, centre, edge, 1) }
        let x = CGMutablePath()
        x.move(to: CGPoint(x: c.x - 5.5, y: c.y - 5.5)); x.addLine(to: CGPoint(x: c.x + 5.5, y: c.y + 5.5))
        x.move(to: CGPoint(x: c.x + 5.5, y: c.y - 5.5)); x.addLine(to: CGPoint(x: c.x - 5.5, y: c.y + 5.5))
        ctx.setLineCap(.round)
        stroke(ctx, x, lab2, 1.6)

        drawCaption(ctx, K, hc)
    }

    /// 28 pt pill, top 62 pt below the disc: padding 0 6 0 12, gap 8, radius 14.
    private func drawCaption(_ ctx: CGContext, _ K: WheelPalette, _ hc: Bool) {
        let (title, key) = model.caption
        let t = attributed(title, 12, .medium, model.captionDimmed ? K.label2 : K.label)
        let k = attributed(key.isEmpty ? "·" : key, 11, .semibold, K.label2)
        let badge = CGSize(width: k.size().width + 12, height: k.size().height + 4)
        let w = 12 + t.size().width + 8 + badge.width + 6
        let pill = CGRect(x: WheelGeometry.center.x - w / 2, y: 422, width: w, height: 28)
        let path = CGPath(roundedRect: pill, cornerWidth: 14, cornerHeight: 14, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: K.shadow.cgColor)
        fill(ctx, path, hc ? K.hudHC : K.cap)
        ctx.restoreGState()
        stroke(ctx, path, hc ? K.lineHC : K.line, 0.5)
        t.draw(at: CGPoint(x: pill.minX + 12, y: pill.midY - t.size().height / 2))
        let b = CGRect(x: pill.maxX - 6 - badge.width, y: pill.midY - badge.height / 2, width: badge.width, height: badge.height)
        fill(ctx, CGPath(roundedRect: b, cornerWidth: 5, cornerHeight: 5, transform: nil), K.fill2)
        k.draw(at: CGPoint(x: b.minX + 6, y: b.minY + 2))
    }

    private func attributed(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }

    private func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let a = attributed(s, size, weight, color)
        let sz = a.size()
        a.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2))
    }

    func fill(_ ctx: CGContext, _ path: CGPath, _ color: NSColor) {
        ctx.addPath(path)
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
    }

    func stroke(_ ctx: CGContext, _ path: CGPath, _ color: NSColor, _ width: CGFloat) {
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }
}

// MARK: - Middle click

/// Middle-button press, drag and release, swallowed so the app under the cursor doesn't also get them.
/// Active event taps on mouse events are covered by the Accessibility permission.
final class MiddleClickTap {
    var enabled: () -> Bool = { true }
    var onDown: () -> Void = {}
    var onDrag: (CGPoint) -> Void = { _ in }
    var onUp: () -> Void = {}
    private var tap: CFMachPort?

    func start() {
        guard tap == nil else { return }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseDragged, .otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, type, event, refcon in
            Unmanaged<MiddleClickTap>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard enabled(), event.getIntegerValueField(.mouseEventButtonNumber) == 2 else { return Unmanaged.passUnretained(event) }
        switch type {
        case .otherMouseDown: onDown()
        case .otherMouseDragged: onDrag(NSEvent.mouseLocation)
        default: onUp()
        }
        return nil
    }
}
