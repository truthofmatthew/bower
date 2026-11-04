import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Overview

/// Everything at a glance: each display shows its windows of a layout, smaller, with the layouts (and any
/// full-screen apps) along the top. Click a window to go to it; drag a rectangle to zoom to what it frames;
/// ⌥-drag a window onto another to swap them, or onto a layout to send it there. Esc closes.
final class Overview {
    private unowned let engine: Engine
    private var panels: [OverviewPanel] = []
    var isOpen: Bool { !panels.isEmpty }

    init(engine: Engine) { self.engine = engine }

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard !isOpen else { return }
        engine.zoomOutAll()
        for s in NSScreen.screens {
            let model = OverviewModel(engine: engine, screen: s, close: { [weak self] in self?.close() })
            let p = OverviewPanel(screen: s, root: OverviewView(model: model))
            p.onEscape = { [weak self] in self?.close() }
            panels.append(p)
            model.load()
        }
        NSApp.activate()
        panels.forEach { $0.makeKeyAndOrderFront(nil); $0.orderFrontRegardless() }
        (panels.first { $0.screen == NSScreen.underMouse } ?? panels.first)?.makeKey()
    }

    func close() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }
}

private final class OverviewPanel: NSPanel {
    var onEscape: () -> Void = {}

    init<V: View>(screen s: NSScreen, root: V) {
        super.init(contentRect: s.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = NSHostingView(rootView: root)
        setFrame(s.frame, display: false)
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape { onEscape() } else { super.keyDown(with: event) }
    }
}

final class OverviewModel: ObservableObject {
    struct Item: Identifiable {
        let id: String
        let win: Win
        /// 0…1 within the display's visible frame.
        let rect: CGRect
    }

    let engine: Engine
    let screen: NSScreen
    let close: () -> Void
    @Published var layout: Int
    @Published var items: [Item] = []
    @Published var images: [CGWindowID: NSImage] = [:]
    @Published var fullScreen: [SkyLight.WindowInfo] = []
    @Published var hovered: String?

    init(engine: Engine, screen: NSScreen, close: @escaping () -> Void) {
        self.engine = engine
        self.screen = screen
        self.close = close
        layout = engine.state.current
    }

    /// Layouts with a name or windows, plus the current one.
    var layouts: [Int] {
        let used = Set(engine.state.assignment.values)
        return (0..<9).filter { !engine.state.layouts[$0].isUntitled || used.contains($0) || $0 == engine.state.current }
    }

    func load() {
        let v = screen.axVisibleFrame
        items = engine.windows(in: layout, on: screen).map { w, f in
            Item(id: w.key, win: w, rect: CGRect(x: (f.minX - v.minX) / v.width, y: (f.minY - v.minY) / v.height,
                                                 width: f.width / v.width, height: f.height / v.height))
        }
        if screen == NSScreen.main {
            let fs = Set(SkyLight.spaces().all.filter(\.isFullScreen).map(\.id))
            fullScreen = SkyLight.allWindows().filter { $0.space.map(fs.contains) == true }
        }
        let ids = items.map(\.win.id)
        Task {
            let imgs = await Capture.images(ids, maxSide: 700)
            await MainActor.run {
                self.images = imgs.mapValues { NSImage(cgImage: $0, size: .zero) }
            }
        }
    }

    func show(_ n: Int) {
        layout = n
        load()
    }

    func go(_ item: Item) {
        close()
        if layout != engine.state.current { engine.switchTo(layout) }
        item.win.focus()
    }

    func goFullScreen(_ w: SkyLight.WindowInfo) {
        close()
        NSRunningApplication(processIdentifier: w.pid)?.activate()
    }

    /// ⌥-drag: onto another window swaps them (Dock mode); onto a layout sends it there.
    func rearrange(_ item: Item, toLayout n: Int?, onto other: Item?) {
        if let n {
            engine.send(item.win, to: n)
        } else if let other, engine.mode(of: screen) == .dock {
            engine.updateDock(screen) { $0.root.swap(item.id, other.id) }
            engine.arrangeDock(screen)
        }
        load()
    }

    /// A rectangle drawn over the desk (0…1 units): zoom to the windows it frames.
    func zoom(to r: CGRect) {
        let v = screen.axVisibleFrame
        let ax = CGRect(x: v.minX + r.minX * v.width, y: v.minY + r.minY * v.height, width: r.width * v.width, height: r.height * v.height)
        close()
        if layout != engine.state.current { engine.switchTo(layout) }
        engine.zoom(to: ax)
    }
}

struct OverviewView: View {
    @ObservedObject var model: OverviewModel
    @State private var marquee: CGRect?
    @State private var dragging: (id: String, offset: CGSize)?

    private static let chipWidth: CGFloat = 132

    var body: some View {
        ZStack(alignment: .top) {
            VisualEffect(material: .fullScreenUI).ignoresSafeArea()
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 18) {
                topBar
                GeometryReader { geo in desk(in: geo.size) }
                Text("Click a window to go to it  ·  Drag a rectangle to zoom to it  ·  ⌥-drag to rearrange  ·  Esc to close")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 48).padding(.top, 36).padding(.bottom, 24)
        }
        .environment(\.colorScheme, .dark)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            ForEach(model.layouts, id: \.self) { n in
                Button { model.show(n) } label: {
                    VStack(spacing: 4) {
                        Text("\(n + 1)").font(.system(size: 18, weight: .semibold))
                        Text(model.engine.state.layouts[n].name).font(.system(size: 11)).lineLimit(1)
                    }
                    .frame(width: Self.chipWidth, height: 56)
                    .background(n == model.layout ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Layout \(n + 1), \(model.engine.state.layouts[n].name)")
            }
            ForEach(model.fullScreen, id: \.id) { w in
                Button { model.goFullScreen(w) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 14))
                        Text(w.app).font(.system(size: 11)).lineLimit(1)
                    }
                    .frame(width: Self.chipWidth, height: 56)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Full screen: \(w.title.isEmpty ? w.app : w.title)"))
            }
        }
        .foregroundStyle(.white)
    }

    private func desk(in size: CGSize) -> some View {
        let v = model.screen.axVisibleFrame
        let scale = min(size.width / v.width, size.height / v.height)
        let deskSize = CGSize(width: v.width * scale, height: v.height * scale)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05))
                .frame(width: deskSize.width, height: deskSize.height)
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { g in marquee = CGRect(origin: g.startLocation, size: .zero).union(CGRect(origin: g.location, size: .zero)) }
                    .onEnded { _ in
                        if let m = marquee, m.width > 20, m.height > 20 {
                            model.zoom(to: CGRect(x: m.minX / deskSize.width, y: m.minY / deskSize.height,
                                                  width: m.width / deskSize.width, height: m.height / deskSize.height))
                        }
                        marquee = nil
                    })
            ForEach(model.items) { item in tile(item, deskSize) }
            if let m = marquee {
                Rectangle().fill(Color.accentColor.opacity(0.15)).overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                    .frame(width: m.width, height: m.height).offset(x: m.minX, y: m.minY).allowsHitTesting(false)
            }
            if model.items.isEmpty {
                Text("No windows in this layout on this display").font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                    .frame(width: deskSize.width, height: deskSize.height)
            }
        }
        .frame(width: deskSize.width, height: deskSize.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ item: OverviewModel.Item, _ desk: CGSize) -> some View {
        let r = CGRect(x: item.rect.minX * desk.width, y: item.rect.minY * desk.height,
                       width: item.rect.width * desk.width, height: item.rect.height * desk.height).insetBy(dx: 3, dy: 3)
        let off = dragging?.id == item.id ? dragging!.offset : .zero
        let p = model.engine.state.prefs
        return ZStack {
            if let img = model.images[item.win.id] {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color(nsColor: Capture.tint(for: item.win.pid, amount: p.appColourAmount, on: p.appColours))
                if let icon = item.win.icon { Image(nsImage: icon).resizable().frame(width: 48, height: 48) }
            }
        }
        .frame(width: max(r.width, 1), height: max(r.height, 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(model.hovered == item.id ? Color.accentColor : Color.white.opacity(0.2),
                                                                 lineWidth: model.hovered == item.id ? 3 : 1))
        .overlay(alignment: .bottom) {
            if model.hovered == item.id {
                Text(item.win.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule()).padding(8)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .offset(x: r.minX + off.width, y: r.minY + off.height)
        .onHover { model.hovered = $0 ? item.id : (model.hovered == item.id ? nil : model.hovered) }
        .onTapGesture { model.go(item) }
        .gesture(DragGesture(minimumDistance: 6)
            .onChanged { g in if NSEvent.modifierFlags.contains(.option) { dragging = (item.id, g.translation) } }
            .onEnded { g in
                defer { dragging = nil }
                guard dragging != nil else { return }
                let end = CGPoint(x: r.midX + g.translation.width, y: r.midY + g.translation.height)
                if end.y < -18 {
                    // Over the layouts along the top (fixed-width chips from the desk's left edge).
                    let i = Int((end.x + 48) / (Self.chipWidth + 8))
                    if model.layouts.indices.contains(i) { model.rearrange(item, toLayout: model.layouts[i], onto: nil) }
                    return
                }
                let other = model.items.first { o in
                    o.id != item.id && CGRect(x: o.rect.minX * desk.width, y: o.rect.minY * desk.height,
                                              width: o.rect.width * desk.width, height: o.rect.height * desk.height).contains(end)
                }
                if let other { model.rearrange(item, toLayout: nil, onto: other) }
            })
        .accessibilityElement()
        .accessibilityLabel("\(item.win.appName), \(item.win.title)")
        .accessibilityAddTraits(.isButton)
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

// MARK: - Minimap

/// A small map of the display's Dock tree, shown for a moment while moving around it.
final class Minimap {
    static let shared = Minimap()
    private let panel = OverlayPanel(level: .statusBar)
    private var hide: DispatchWorkItem?

    func flash(_ engine: Engine, on s: NSScreen) {
        guard engine.mode(of: s) == .dock else { return }
        let d = engine.dockLayout(s)
        let r = engine.dockRect(s)
        let solved = d.root.solve(in: r, gap: CGFloat(engine.state.prefs.gap))
        let zoomKeys = Set(d.zoom.flatMap { d.root[$0]?.keys } ?? d.root.keys)
        let focused = AX.focusedWindow()?.key
        let size = CGSize(width: 180, height: 180 * r.height / max(r.width, 1))
        panel.contentView = NSHostingView(rootView: MinimapView(frames: solved.frames, area: r, inView: zoomKeys, focused: focused).frame(width: size.width, height: size.height))
        let v = s.visibleFrame
        panel.setFrame(NSRect(x: v.maxX - size.width - 20, y: v.minY + 20, width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hide?.cancel()
        let work = DispatchWorkItem { [panel] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }, completionHandler: { panel.orderOut(nil) })
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}

private struct MinimapView: View {
    let frames: [String: CGRect]
    let area: CGRect
    let inView: Set<String>
    let focused: String?

    var body: some View {
        GeometryReader { g in
            let sx = g.size.width / max(area.width, 1), sy = g.size.height / max(area.height, 1)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
                ForEach(Array(frames.keys), id: \.self) { k in
                    let f = frames[k]!
                    RoundedRectangle(cornerRadius: 3)
                        .fill(k == focused ? Color.accentColor : Color.primary.opacity(inView.contains(k) ? 0.35 : 0.12))
                        .frame(width: max(f.width * sx - 2, 1), height: max(f.height * sy - 2, 1))
                        .offset(x: (f.minX - area.minX) * sx + 1, y: (f.minY - area.minY) * sy + 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Pinch, pan and zoom to a rectangle

/// ⌥-pinch anywhere (or a plain pinch over bare desktop) steps in and out a level; pinching out at the top
/// opens the overview. ⌥ with a two-finger pan moves to the neighbouring window. ⌘⇧-drag a rectangle to zoom
/// to what it frames (⌘⌥⇧ works too; Esc cancels).
final class ZoomGestures {
    private unowned let engine: Engine
    private unowned let overview: Overview
    private var pinch: CGFloat = 0
    private var pan = CGSize.zero
    private var marqueeStart: CGPoint?
    private let marquee = OverlayPanel(level: .popUpMenu)
    private var escMonitor: Any?

    init(engine: Engine, overview: Overview) {
        self.engine = engine
        self.overview = overview
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        v.layer?.borderColor = NSColor.controlAccentColor.cgColor
        v.layer?.borderWidth = 1.5
        marquee.contentView = v
    }

    func install() {
        var h = EventTap.Handler()
        h.magnify = { [weak self] e in self?.magnify(e) ?? false }
        h.scroll = { [weak self] e in self?.scroll(e) ?? false }
        h.down = { [weak self] p, e in self?.marqueeDown(p, e) ?? false }
        h.dragged = { [weak self] p, _ in self?.marqueeDragged(p) ?? false }
        h.up = { [weak self] p, _ in self?.marqueeUp(p) ?? false }
        EventTap.shared.add("zoom", h)
    }

    private func allowed(_ e: CGEvent) -> Bool {
        let p = engine.state.prefs
        guard p.pinchZoom else { return false }
        if e.option { return true }
        // Without ⌥, only over bare desktop.
        return !p.pinchNeedsOption || AX.windowID(at: e.location) == nil
    }

    private func magnify(_ e: CGEvent) -> Bool {
        guard let ns = NSEvent(cgEvent: e), allowed(e) else { pinch = 0; return false }
        pinch += ns.magnification
        if ns.phase == .ended || ns.phase == .cancelled || abs(pinch) > 0.35 {
            let amount = pinch
            pinch = 0
            DispatchQueue.main.async {
                if amount < -0.2 {
                    // Pinch in: see more.
                    if let s = self.engine.focusedScreen, self.engine.dockLayout(s).zoom != nil { self.engine.stepOut() } else { self.overview.open() }
                } else if amount > 0.2 {
                    if self.overview.isOpen { self.overview.close() } else { self.engine.stepIn() }
                }
                if let s = self.engine.focusedScreen { Minimap.shared.flash(self.engine, on: s) }
            }
        }
        return true
    }

    private func scroll(_ e: CGEvent) -> Bool {
        guard e.option, engine.state.prefs.pinchZoom, let ns = NSEvent(cgEvent: e), ns.hasPreciseScrollingDeltas else { pan = .zero; return false }
        let k = CGFloat(engine.state.prefs.panSpeed)
        pan.width += ns.scrollingDeltaX * k
        pan.height += ns.scrollingDeltaY * k
        let threshold: CGFloat = 220
        var dir: Engine.Direction?
        if pan.width > threshold { dir = .left } else if pan.width < -threshold { dir = .right }
        else if pan.height > threshold { dir = .up } else if pan.height < -threshold { dir = .down }
        if let dir {
            pan = .zero
            DispatchQueue.main.async {
                self.engine.neighbour(dir)
                if let s = self.engine.focusedScreen { Minimap.shared.flash(self.engine, on: s) }
            }
        }
        if ns.phase == .ended || ns.momentumPhase == .ended { pan = .zero }
        return true
    }

    private func marqueeDown(_ p: CGPoint, _ e: CGEvent) -> Bool {
        guard engine.state.prefs.marqueeZoom, e.command, e.shift else { return false }
        marqueeStart = p
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            if Int(ev.keyCode) == kVK_Escape { self?.cancelMarquee() }
        }
        return true
    }

    private func marqueeDragged(_ p: CGPoint) -> Bool {
        guard let s = marqueeStart else { return false }
        let r = CGRect(origin: s, size: .zero).union(CGRect(origin: p, size: .zero))
        marquee.setFrame(NSScreen.appKit(r), display: true)
        marquee.orderFrontRegardless()
        return true
    }

    private func marqueeUp(_ p: CGPoint) -> Bool {
        guard let s = marqueeStart else { return false }
        let r = CGRect(origin: s, size: .zero).union(CGRect(origin: p, size: .zero))
        cancelMarquee()
        if r.width > 30, r.height > 30 { DispatchQueue.main.async { self.engine.zoom(to: r) } }
        return true
    }

    private func cancelMarquee() {
        marqueeStart = nil
        marquee.orderOut(nil)
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }
}

// MARK: - Mission Control

/// "Show Bower's overview instead" of Mission Control: macOS's own Mission Control shortcut is turned off and
/// Bower takes its keys; opened another way (the Dock, a hot corner), Mission Control shows for a moment first,
/// then the overview. Turning it off, or quitting, gives macOS its shortcut back; so does the next launch after a crash.
final class MissionControl {
    private unowned let engine: Engine
    private unowned let overview: Overview
    private var observer: AXObserver?

    private typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32
    private typealias GetValue = @convention(c) (Int32, UnsafeMutablePointer<UInt16>?, UnsafeMutablePointer<UInt16>?, UnsafeMutablePointer<UInt32>?) -> Int32
    private typealias DockNotify = @convention(c) (CFString, Int32) -> Void
    private static let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    private static let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static func sym<T>(_ n: String, _: T.Type) -> T? {
        (dlsym(sky, n) ?? dlsym(cg, n)).map { unsafeBitCast($0, to: T.self) }
    }
    /// Mission Control's own shortcut (⌃↑ by default) in macOS's symbolic hotkeys.
    static let missionControlHotKey: Int32 = 32

    init(engine: Engine, overview: Overview) {
        self.engine = engine
        self.overview = overview
    }

    func start() {
        if engine.state.prefs.replaceMissionControl { take() } else { giveBack() }
        attachToDock()
    }

    func setOn(_ on: Bool) {
        engine.setPrefs { $0.replaceMissionControl = on }
        on ? take() : giveBack()
    }

    /// The keys macOS uses for Mission Control, as Carbon key code and modifiers.
    static func missionControlKeys() -> Combo? {
        guard let f = sym("CGSGetSymbolicHotKeyValue", GetValue.self) else { return nil }
        var key: UInt16 = 0, code: UInt16 = 0, mods: UInt32 = 0
        guard f(missionControlHotKey, &key, &code, &mods) == 0, code != 0xFFFF else { return nil }
        var m = 0
        if mods & 0x40000 != 0 { m |= controlKey }
        if mods & 0x80000 != 0 { m |= optionKey }
        if mods & 0x20000 != 0 { m |= shiftKey }
        if mods & 0x100000 != 0 { m |= cmdKey }
        return Combo(key: Int(code), mods: m)
    }

    private func take() {
        guard let f = Self.sym("CGSSetSymbolicHotKeyEnabled", SetEnabled.self) else { return }
        _ = f(Self.missionControlHotKey, false)
        engine.setPrefs { $0.hotkeysTakenOver = [Int(Self.missionControlHotKey)] }
        Log.info("mission control: shortcut taken over")
    }

    func giveBack() {
        guard !engine.state.prefs.hotkeysTakenOver.isEmpty, let f = Self.sym("CGSSetSymbolicHotKeyEnabled", SetEnabled.self) else { return }
        for k in engine.state.prefs.hotkeysTakenOver { _ = f(Int32(k), true) }
        engine.setPrefs { $0.hotkeysTakenOver = [] }
        Log.info("mission control: shortcut given back")
    }

    /// Opens macOS's real Mission Control (fn, or Bower's overview turned off).
    static func showReal() {
        sym("CoreDockSendNotification", DockNotify.self)?("com.apple.expose.awake" as CFString, 0)
    }

    /// Mission Control opened from the Dock or a hot corner: let it show for a moment, then the overview instead.
    private func attachToDock() {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        var obs: AXObserver?
        guard AXObserverCreate(dock.processIdentifier, { _, _, note, refcon in
            let me = Unmanaged<MissionControl>.fromOpaque(refcon!).takeUnretainedValue()
            guard note as String == "AXExposeShowAllWindows", me.engine.state.prefs.replaceMissionControl else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MissionControl.showReal()  // toggles it closed again
                me.overview.open()
            }
        }, &obs) == .success, let obs else { return }
        let el = AXUIElementCreateApplication(dock.processIdentifier)
        AXObserverAddNotification(obs, el, "AXExposeShowAllWindows" as CFString, Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
    }
}
