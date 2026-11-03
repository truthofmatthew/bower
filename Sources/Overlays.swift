import AppKit

/// A click-through, non-activating panel that floats over every app.
class OverlayPanel: NSPanel {
    init(level: NSWindow.Level) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
}

// MARK: - Snap preview

/// SnapPreview.dc.html: the target frame inset 6 pt, radius 10, accent fill and 1.5 pt stroke,
/// a 1 pt outer keyline, and an optional caption pill (wheel ghost only).
final class SnapPreview {
    private let panel = OverlayPanel(level: .popUpMenu)
    private let view = SnapPreviewView()
    private var visible = false
    private var dwell: DispatchWorkItem?

    init() { panel.contentView = view }

    /// `target` is the window's landing frame in AX coordinates; the preview draws 6 pt inside it.
    func show(_ target: CGRect, caption: (String, String)? = nil) {
        // The 1 pt keyline sits outside the 6 pt inset.
        let frame = NSScreen.appKit(target).insetBy(dx: 5, dy: 5)
        view.caption = caption
        view.needsDisplay = true
        dwell?.cancel()
        if visible {
            if Theme.reduceMotion {
                panel.setFrame(frame, display: true)
            } else {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.09
                    ctx.timingFunction = Theme.easeInOut
                    panel.animator().setFrame(frame, display: true)
                }
            }
            return
        }
        visible = true
        let work = DispatchWorkItem { [self] in
            panel.setFrame(frame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Theme.reduceMotion ? 0.08 : 0.12
                ctx.timingFunction = Theme.reduceMotion ? nil : Theme.easeOut
                panel.animator().alphaValue = 1
            }
        }
        dwell = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    func hide() {
        dwell?.cancel()
        guard visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Theme.reduceMotion ? 0.08 : 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [self] in if !visible { panel.orderOut(nil) } })
    }
}

private final class SnapPreviewView: NSView {
    var caption: (String, String)?

    override func draw(_ dirtyRect: NSRect) {
        let p = SnapPalette.current(effectiveAppearance)
        let hc = Theme.highContrast
        let keyline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10.5, yRadius: 10.5)
        keyline.lineWidth = 1
        p.keyline.setStroke()
        keyline.stroke()

        let body = bounds.insetBy(dx: 1, dy: 1)
        (hc ? p.fillHC : p.fill).setFill()
        NSBezierPath(roundedRect: body, xRadius: 10, yRadius: 10).fill()

        let sw: CGFloat = hc ? 2 : 1.5
        let edge = NSBezierPath(roundedRect: body.insetBy(dx: sw / 2, dy: sw / 2), xRadius: 10 - sw / 2, yRadius: 10 - sw / 2)
        edge.lineWidth = sw
        (hc ? p.stroke.withAlphaComponent(1) : p.stroke).setStroke()
        edge.stroke()

        let inner = NSBezierPath(roundedRect: body.insetBy(dx: sw + 0.5, dy: sw + 0.5), xRadius: 8, yRadius: 8)
        inner.lineWidth = 1
        p.innerKeyline.setStroke()
        inner.stroke()

        guard let (title, size) = caption else { return }
        let t = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: p.label])
        let s = NSAttributedString(string: size, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: p.label2])
        let w = 12 + t.size().width + 8 + s.size().width + 6
        let pill = NSRect(x: bounds.midX - w / 2, y: bounds.midY - 14, width: w, height: 28)
        p.hud.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 14, yRadius: 14).fill()
        let hair = NSBezierPath(roundedRect: pill.insetBy(dx: 0.25, dy: 0.25), xRadius: 14, yRadius: 14)
        hair.lineWidth = 0.5
        p.hair.setStroke()
        hair.stroke()
        t.draw(at: NSPoint(x: pill.minX + 12, y: pill.midY - t.size().height / 2))
        s.draw(at: NSPoint(x: pill.minX + 12 + t.size().width + 8, y: pill.midY - s.size().height / 2))
    }
}

// MARK: - Retile toast

/// Bento.dc.html: bottom-centre of the display, 64 pt above the Dock. Fades in 150 ms, holds 1.4 s, fades out 200 ms.
final class Toast {
    private let panel = OverlayPanel(level: .statusBar)
    private let effect = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private var hideWork: DispatchWorkItem?
    private var generation = 0

    init() {
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.borderWidth = 0.5
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16)
        ])
        panel.contentView = effect
    }

    func show(_ text: String, on screen: NSScreen) {
        let dark = Theme.isDark()
        let accent = dark ? WheelPalette.dark.accent : WheelPalette.light.accent
        effect.layer?.borderColor = (dark ? Theme.rgba(255, 255, 255, 0.14) : Theme.rgba(0, 0, 0, 0.12)).cgColor
        icon.image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.addPath(Icon.retile)
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
            return true
        }
        label.stringValue = text
        let width = 12 + 16 + 8 + label.intrinsicContentSize.width + 14
        let v = screen.visibleFrame
        let frame = NSRect(x: v.midX - width / 2, y: v.minY + 64, width: width, height: 36)
        hideWork?.cancel()
        generation += 1
        let shown = generation
        // Rises 8 pt into place, ease-out; Reduce Motion: fade only.
        panel.setFrame(Theme.reduceMotion ? frame : frame.offsetBy(dx: 0, dy: -8), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = Theme.easeOut
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
        let work = DispatchWorkItem { [self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = Theme.easeOut
                panel.animator().alphaValue = 0
            }, completionHandler: { if self.generation == shown { self.panel.orderOut(nil) } })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + 1.4, execute: work)
    }
}

// MARK: - Layout preview

/// What a layout holds, drawn over the real screen while the Snap Wheel points at it: the display dims, and each of
/// the layout's windows appears where it rests, with its app's icon and name and the window's title.
final class LayoutGhost {
    // Just under the wheel, so the wheel stays readable on top.
    private let panel = OverlayPanel(level: NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1))
    private let view = LayoutGhostView()
    private var shown: Int?

    init() { panel.contentView = view }

    func show(_ n: Int, windows: [(win: Win, frame: CGRect)], on s: NSScreen) {
        guard shown != n else { return }
        shown = n
        view.items = windows.map { w in
            let r = NSScreen.appKit(w.frame)
            return .init(rect: r.offsetBy(dx: -s.frame.minX, dy: -s.frame.minY), icon: w.win.icon, app: w.win.appName, title: w.win.title)
        }
        view.empty = String(localized: "Layout \(n + 1) has no windows on this display")
        panel.setFrame(s.frame, display: false)
        view.needsDisplay = true
        guard !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.reduceMotion ? 0.08 : 0.14
            ctx.timingFunction = Theme.reduceMotion ? nil : Theme.easeOut
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard shown != nil else { return }
        shown = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [self] in if shown == nil { panel.orderOut(nil) } })
    }
}

private final class LayoutGhostView: NSView {
    struct Item { let rect: CGRect; let icon: NSImage?; let app: String; let title: String }
    var items: [Item] = []
    var empty = ""

    override func draw(_ dirtyRect: NSRect) {
        let p = SnapPalette.current(effectiveAppearance)
        let dark = Theme.isDark(effectiveAppearance)
        NSColor.black.withAlphaComponent(0.5).setFill()
        bounds.fill()
        guard !items.isEmpty else { return drawPill(empty, at: CGPoint(x: bounds.midX, y: bounds.midY), p) }
        for it in items {
            let r = it.rect.insetBy(dx: 6, dy: 6)
            let body = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
            // Solid, so the windows of the layout on screen now don't show through.
            NSColor(white: dark ? 0.15 : 0.97, alpha: 1).setFill()
            body.fill()
            (Theme.highContrast ? p.stroke.withAlphaComponent(1) : p.stroke).setStroke()
            body.lineWidth = 1.5
            body.stroke()
            // Icon, app name and title near the top, clear of the wheel (which opens mid-screen, at the pointer);
            // the title drops out when the window is too small for it.
            let icon: CGFloat = min(56, r.height * 0.35, r.width * 0.35)
            let name = NSAttributedString(string: it.app, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: p.label])
            let title = NSAttributedString(string: it.title == it.app ? "" : it.title,
                                           attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: p.label2])
            let showTitle = !title.string.isEmpty && r.height > icon + 60
            let h = icon + 8 + name.size().height + (showTitle ? 4 + title.size().height : 0)
            var y = max(r.midY + h / 2, r.maxY - 36) - icon
            it.icon?.draw(in: NSRect(x: r.midX - icon / 2, y: y, width: icon, height: icon))
            y -= 8 + name.size().height
            draw(name, centeredAt: r.midX, y: y, maxWidth: r.width - 24)
            if showTitle { draw(title, centeredAt: r.midX, y: y - 4 - title.size().height, maxWidth: r.width - 24) }
        }
    }

    private func draw(_ s: NSAttributedString, centeredAt x: CGFloat, y: CGFloat, maxWidth: CGFloat) {
        let w = min(s.size().width, max(maxWidth, 0))
        s.draw(with: NSRect(x: x - w / 2, y: y, width: w, height: s.size().height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func drawPill(_ text: String, at c: CGPoint, _ p: SnapPalette) {
        let t = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: p.label])
        let pill = NSRect(x: c.x - t.size().width / 2 - 14, y: c.y - 15, width: t.size().width + 28, height: 30)
        p.hud.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 15, yRadius: 15).fill()
        t.draw(at: NSPoint(x: pill.minX + 14, y: pill.midY - t.size().height / 2))
    }
}
