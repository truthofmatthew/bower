import AppKit
import QuartzCore

/// Moves windows smoothly. A window can't be animated through Accessibility without stutter, so Bower covers
/// the moving windows with pictures of them, puts the real windows in place underneath at once, glides the
/// pictures there, and fades them out once the apps have had `redrawWait` to draw at their new size.
/// Without Screen Recording the pictures are each app's colour and icon. Reduce Motion, or speed 0: no cover.
final class Motion {
    static let shared = Motion()

    private var panel: OverlayPanel?
    private var generation = 0
    private(set) var animating = false

    /// Ends the animation now: a click while windows settle shows them at once.
    func finish() {
        guard animating else { return }
        generation += 1
        panel?.orderOut(nil)
        panel = nil
        animating = false
    }

    func installInterrupt(_ engine: Engine) {
        var h = EventTap.Handler()
        h.down = { [weak engine] _, _ in
            if engine?.state.prefs.interruptAnimations == true { DispatchQueue.main.async { Motion.shared.finish() } }
            return false
        }
        EventTap.shared.add("motion", h)
    }

    func apply(_ moves: [(Win, CGRect)], engine: Engine, animate: Bool = true) {
        let changes = moves.filter { w, f in
            guard let cur = w.frame else { return true }
            return abs(cur.minX - f.minX) > 1 || abs(cur.minY - f.minY) > 1 || abs(cur.width - f.width) > 1 || abs(cur.height - f.height) > 1
        }
        guard !changes.isEmpty else { return }
        let p = engine.state.prefs
        guard animate, p.animationSpeed > 0, !Theme.reduceMotion, changes.count <= 40 else {
            for (w, f) in changes { w.setFrame(f) }
            return
        }
        finish()
        let items = changes.map { w, f in (win: w, from: w.frame.map { engine.isParked($0) ? f : $0 } ?? f, to: f,
                                            entering: w.frame.map(engine.isParked) ?? true) }
        if Capture.allowed, p.previewLook == .pictureUnderColour {
            Task {
                let imgs = await Capture.images(items.map(\.win.id))
                await MainActor.run { self.run(items, imgs, p) }
            }
        } else {
            run(items, [:], p)
        }
    }

    private func run(_ items: [(win: Win, from: CGRect, to: CGRect, entering: Bool)], _ imgs: [CGWindowID: CGImage], _ p: Prefs) {
        generation += 1
        let gen = generation
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let panel = OverlayPanel(level: NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 2))
        panel.setFrame(union, display: false)
        let root = CALayer()
        let host = NSView(frame: CGRect(origin: .zero, size: union.size))
        host.wantsLayer = true
        host.layer = root
        panel.contentView = host
        // AX rect → the panel's own coordinates (bottom-left origin).
        func local(_ r: CGRect) -> CGRect { NSScreen.appKit(r).offsetBy(dx: -union.minX, dy: -union.minY) }

        var layers: [(CALayer, CGRect)] = []
        for it in items {
            let l = CALayer()
            l.cornerRadius = 10
            l.masksToBounds = true
            l.frame = local(it.from)
            if let img = imgs[it.win.id] {
                l.contents = img
                l.contentsGravity = p.stretchPictures ? .resize : .topLeft
                l.contentsScale = 2
                l.backgroundColor = NSColor.windowBackgroundColor.cgColor
            } else {
                l.backgroundColor = Capture.tint(for: it.win.pid, amount: p.appColourAmount, on: p.appColours).withAlphaComponent(0.95).cgColor
                if let icon = it.win.icon {
                    let i = CALayer()
                    i.contents = icon
                    i.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
                    i.position = CGPoint(x: l.bounds.midX, y: l.bounds.midY)
                    i.autoresizingMask = [.layerMinXMargin, .layerMaxXMargin, .layerMinYMargin, .layerMaxYMargin]
                    l.addSublayer(i)
                }
            }
            l.borderWidth = 0.5
            l.borderColor = NSColor.black.withAlphaComponent(0.2).cgColor
            if it.entering { l.opacity = 0 }
            root.addSublayer(l)
            layers.append((l, local(it.to)))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        animating = true
        for it in items { it.win.setFrame(it.to) }

        let duration = 0.3 / max(p.animationSpeed, 0.1)
        CATransaction.flush()  // the starting frames are on screen before they move
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(Theme.easeInOut)  // strong in-out: windows stay on screen as they move
            for (l, to) in layers {
                l.frame = to
                l.opacity = 1
            }
            CATransaction.commit()
        }
        let resized = items.contains { abs($0.from.width - $0.to.width) > 1 || abs($0.from.height - $0.to.height) > 1 }
        let wait = duration + (resized ? p.redrawWait : 0.05)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.generation == gen else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: {
                guard self.generation == gen else { return }
                panel.orderOut(nil)
                self.panel = nil
                self.animating = false
            })
        }
    }

    /// Sliding the whole desk sideways while the layout changes underneath (swipes between layouts).
    func slide(_ d: Int, screen s: NSScreen, engine: Engine) {
        guard engine.state.prefs.animationSpeed > 0, !Theme.reduceMotion else { return }
        let wins = AX.windows().filter { w in w.frame.map { !engine.isParked($0) && NSScreen.containing(ax: $0) == s } ?? false }
        let ids = wins.map(\.id)
        Task {
            let imgs = await Capture.images(ids, maxSide: 800)
            await MainActor.run {
                let panel = OverlayPanel(level: NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 2))
                panel.setFrame(s.frame, display: false)
                let root = CALayer()
                let host = NSView(frame: CGRect(origin: .zero, size: s.frame.size))
                host.wantsLayer = true
                host.layer = root
                panel.contentView = host
                for w in wins {
                    guard let f = w.frame else { continue }
                    let l = CALayer()
                    l.frame = NSScreen.appKit(f).offsetBy(dx: -s.frame.minX, dy: -s.frame.minY)
                    l.cornerRadius = 10
                    l.masksToBounds = true
                    if let img = imgs[w.id] { l.contents = img; l.contentsGravity = .resize } else {
                        l.backgroundColor = Capture.tint(for: w.pid, amount: engine.state.prefs.appColourAmount, on: true).cgColor
                    }
                    root.addSublayer(l)
                }
                panel.orderFrontRegardless()
                CATransaction.flush()
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.28 / max(engine.state.prefs.animationSpeed, 0.1))
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1))
                CATransaction.setCompletionBlock { panel.orderOut(nil) }
                root.sublayers?.forEach { $0.position.x -= CGFloat(d) * s.frame.width; $0.opacity = 0 }
                CATransaction.commit()
            }
        }
    }
}
