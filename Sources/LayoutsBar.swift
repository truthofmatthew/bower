import SwiftUI
import UniformTypeIdentifiers

/// LayoutsBar.dc.html: a floating HUD strip at the top of the active display.
/// Click a chip or press its number to switch; drag a window's icon onto a chip to assign it.
final class LayoutsBar {
    private let engine: Engine
    private let model = BarModel()
    private lazy var panel = BarPanel(model: model)

    init(engine: Engine) {
        self.engine = engine
        // Switching can hand focus to another app (an empty layout activates Finder), so the bar closes first.
        model.switchTo = { [weak self] n in self?.close(); self?.engine.switchTo(n) }
        model.assign = { [weak self] key, n in self?.assign(key, to: n) }
        model.togglePin = { [weak self] in
            guard let self, let s = self.model.screen else { return }
            self.engine.togglePin(s)
            self.reload()
        }
        panel.onKey = { [weak self] in self?.key($0) }
        panel.onResign = { [weak self] in self?.close() }
    }

    var isOpen: Bool { panel.isVisible }

    func toggle() { isOpen ? close() : open() }

    func open() {
        model.screen = NSScreen.underMouse
        model.focus = nil
        reload()
        // SwiftUI lays out the new chips on the next pass; measure after it.
        DispatchQueue.main.async { [self] in show() }
    }

    private func show() {
        guard let s = model.screen else { return }
        panel.contentView!.layoutSubtreeIfNeeded()
        let size = panel.contentView!.fittingSize
        let v = s.visibleFrame
        // The view keeps 4 pt above the bar for its edge, so the bar itself sits 12 pt below the menu bar.
        let frame = NSRect(x: v.midX - size.width / 2, y: v.maxY - 8 - size.height, width: size.width, height: size.height)
        // Opened from the keyboard (⌥↑), many times a day: it appears at once rather than easing in.
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.08; panel.animator().alphaValue = 0 },
                                             completionHandler: { [panel] in panel.orderOut(nil) })
    }

    private func reload() {
        let st = engine.state
        let groups = engine.windowsByLayout()
        model.current = st.current
        model.chips = st.layouts.enumerated().map { i, l in
            BarModel.Chip(n: i, name: l.name, windows: (groups[i] ?? []).map(BarModel.Item.init))
        }
        model.unassigned = (groups[nil] ?? []).map(BarModel.Item.init)
        model.pinned = model.screen.map { st.pinned.contains($0.uuid) } ?? false
        model.screenName = model.screen?.localizedName ?? ""
    }

    private func assign(_ key: String, to n: Int) {
        if let w = AX.windows().first(where: { $0.key == key }) { engine.send(w, to: n) }
        reload()
    }

    private func key(_ e: NSEvent) {
        let chars = e.charactersIgnoringModifiers ?? ""
        if let d = Int(chars), (1...9).contains(d) { return model.switchTo(d - 1) }
        switch Int(e.keyCode) {
        case 53: close()
        case 123: model.focus = max((model.focus ?? model.current) - 1, 0)
        case 124: model.focus = min((model.focus ?? model.current) + 1, 8)
        case 36, 49: if let f = model.focus { model.switchTo(f) }
        case 126 where e.modifierFlags.contains(.option): close()
        default: break
        }
    }
}

final class BarModel: ObservableObject {
    struct Item: Identifiable {
        let id: String
        let title: String
        let icon: NSImage?
        init(_ w: Win) { id = w.key; title = w.title; icon = w.icon }
        init(id: String, title: String, icon: NSImage?) { self.id = id; self.title = title; self.icon = icon }
    }

    struct Chip: Identifiable {
        let n: Int
        let name: String
        let windows: [Item]
        var id: Int { n }
    }

    @Published var chips: [Chip] = []
    @Published var unassigned: [Item] = []
    @Published var current = 0
    @Published var focus: Int?
    @Published var pinned = false
    @Published var dragging: Item?
    @Published var dropTarget: Int?
    var screen: NSScreen?
    var screenName = ""
    var switchTo: (Int) -> Void = { _ in }
    var assign: (String, Int) -> Void = { _, _ in }
    var togglePin: () -> Void = {}
}

private final class BarPanel: NSPanel {
    var onKey: (NSEvent) -> Void = { _ in }
    var onResign: () -> Void = {}

    init(model: BarModel) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: BarView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { onKey(event) }
    override func resignKey() { super.resignKey(); onResign() }
}

// MARK: - Views

private enum BarColors {
    private static func dyn(_ d: NSColor, _ l: NSColor) -> Color { Color(nsColor: NSColor(name: nil) { Theme.isDark($0) ? d : l }) }
    static let label = dyn(Theme.rgba(255, 255, 255, 0.92), Theme.rgba(0, 0, 0, 0.88))
    static let label2 = dyn(Theme.rgba(235, 235, 245, 0.64), Theme.rgba(60, 60, 67, 0.74))
    static let label3 = dyn(Theme.rgba(235, 235, 245, 0.38), Theme.rgba(60, 60, 67, 0.40))
    static let hair = dyn(Theme.rgba(255, 255, 255, 0.14), Theme.rgba(0, 0, 0, 0.12))
    static let fill = dyn(Theme.rgba(255, 255, 255, 0.08), Theme.rgba(0, 0, 0, 0.05))
    static let fill2 = dyn(Theme.rgba(255, 255, 255, 0.14), Theme.rgba(0, 0, 0, 0.09))
    static let hud = dyn(Theme.rgba(36, 36, 40, 0.72), Theme.rgba(250, 250, 252, 0.78))
    static let hudSolid = dyn(Theme.hex(0x2A2A2E), Theme.hex(0xF4F4F6))
    static let accent = dyn(Theme.hex(0x3FD3C2), Theme.hex(0x0B7A72))
    static let accentFill = dyn(Theme.rgba(63, 211, 194, 0.22), Theme.rgba(11, 122, 114, 0.15))
    static let onAccent = dyn(Theme.hex(0x04231F), Theme.hex(0xFFFFFF))
    static let shadow = dyn(Theme.rgba(0, 0, 0, 0.45), Theme.rgba(0, 0, 0, 0.18))
}

struct BarView: View {
    @ObservedObject var model: BarModel
    @State private var hover: Int?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(model.chips) { chip in layoutChip(chip) }
                BarColors.hair.frame(width: 1, height: 40).padding(.horizontal, 4)
                unassignedChip
                pinChip
            }
            .padding(6)
            .background(BarMaterial().clipShape(RoundedRectangle(cornerRadius: 16)))
            .background(RoundedRectangle(cornerRadius: 16).fill(BarColors.hud))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(BarColors.hair, lineWidth: 0.5))
            .shadow(color: BarColors.shadow, radius: 20, y: 14)

            if model.pinned {
                // "LG UltraFine is pinned." bubble under the pin chip, 300 wide.
                (Text("\(model.screenName) is pinned. ").bold().foregroundColor(BarColors.label)
                    + Text("It keeps its windows when you switch layouts on other displays. Click to unpin."))
                    .font(.system(size: 12)).lineSpacing(3).foregroundStyle(BarColors.label2)
                    .frame(width: 276, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(BarColors.hud))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BarColors.hair, lineWidth: 0.5))
                    .shadow(color: BarColors.shadow, radius: 20, y: 14)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let item = model.dragging, let n = model.dropTarget, n < model.chips.count {
                Text("Assign “\(item.title)” to \(n + 1) · \(model.chips[n].name)")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(BarColors.hud))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BarColors.hair, lineWidth: 0.5))
            }
        }
        .padding(EdgeInsets(top: 4, leading: 24, bottom: 36, trailing: 24))  // room for the shadow
        .foregroundStyle(BarColors.label)
    }

    private func layoutChip(_ chip: BarModel.Chip) -> some View {
        let cur = chip.n == model.current
        let drop = model.dropTarget == chip.n && model.dragging != nil && !cur
        let empty = chip.windows.isEmpty && !drop
        return Button { model.switchTo(chip.n) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("\(chip.n + 1)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(cur ? BarColors.onAccent : BarColors.label)
                        .frame(width: 18, height: 18)
                        .background(cur ? BarColors.accent : BarColors.fill2, in: RoundedRectangle(cornerRadius: 5))
                    Text(chip.name)
                        .font(.system(size: 12, weight: empty ? .medium : .semibold))
                        .foregroundStyle(cur ? BarColors.accent : empty ? BarColors.label3 : BarColors.label)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 0)
                iconStack(chip.windows, slot: drop)
            }
            .padding(.vertical, 7).padding(.horizontal, 8)
            .frame(width: 96, height: 56, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(
                cur ? BarColors.accentFill : drop ? BarColors.fill2 : hover == chip.n ? BarColors.fill : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(drop ? BarColors.accent : .clear, lineWidth: 1.5))
            .overlay(RoundedRectangle(cornerRadius: 10).inset(by: -2).strokeBorder(model.focus == chip.n ? BarColors.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 ? chip.n : (hover == chip.n ? nil : hover) }
        .onDrop(of: [.plainText], delegate: ChipDrop(n: chip.n, model: model))
        .accessibilityLabel(cur ? "Layout \(chip.n + 1), \(chip.name), current" : "Layout \(chip.n + 1), \(chip.name)")
    }

    /// Up to 4 icons at −4 pt overlap; a 5th becomes "+n".
    private func iconStack(_ items: [BarModel.Item], slot: Bool) -> some View {
        HStack(spacing: -4) {
            ForEach(items.prefix(4)) { item in
                Group {
                    if let icon = item.icon { Image(nsImage: icon).resizable() } else { BarColors.fill2 }
                }
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).inset(by: -0.75).stroke(BarColors.hudSolid, lineWidth: 1.5))
                .help(item.title)
                .onDrag {
                    model.dragging = item
                    return NSItemProvider(object: item.id as NSString)
                }
            }
            if items.count > 4 {
                Text("+\(items.count - 4)").font(.system(size: 10, weight: .semibold)).foregroundStyle(BarColors.label2).padding(.leading, 8)
            }
            if slot {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(BarColors.accent, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .frame(width: 16, height: 16)
                    .padding(.leading, items.isEmpty ? 0 : 10)
            }
        }
        .frame(height: 18)
    }

    private var unassignedChip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Glyph(d: "M2.5 10.5h3.5l1 2h4l1-2h3.5M2.5 10.5 4.5 4h9l2 6.5v3.5h-13z", grid: 18, size: 18, width: 1.4)
                Text("Unassigned").font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            iconStack(model.unassigned, slot: false)
        }
        .padding(.vertical, 7).padding(.horizontal, 8)
        .frame(width: 112, height: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unassigned windows, \(model.unassigned.count)")
    }

    private var pinChip: some View {
        Button(action: model.togglePin) {
            HStack(spacing: 6) {
                Glyph(d: "M10.5 1.5 14.5 5.5 12 6.5 9.5 9l.5 3.5-1 1-3-3-3.5 3.5M5.5 10.5l-3-3 1-1L7 7l2.5-2.5 1-2.5", size: 16, width: 1.4)
                if model.pinned { Text("Pinned").font(.system(size: 12, weight: .semibold)) }
            }
            .foregroundStyle(model.pinned ? BarColors.accent : BarColors.label)
            .frame(width: model.pinned ? 92 : 40, height: 56)
            .background(RoundedRectangle(cornerRadius: 10).fill(model.pinned ? BarColors.accentFill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.pinned ? "Unpin this display" : "Pin this display")
        .accessibilityLabel(model.pinned ? "Display pinned, click to unpin" : "Pin this display")
    }
}

private struct ChipDrop: DropDelegate {
    let n: Int
    let model: BarModel

    func dropEntered(info: DropInfo) { model.dropTarget = n }
    func dropExited(info: DropInfo) { if model.dropTarget == n { model.dropTarget = nil } }

    func performDrop(info: DropInfo) -> Bool {
        defer { model.dropTarget = nil; model.dragging = nil }
        guard let key = model.dragging?.id else { return false }
        model.assign(key, n)
        return true
    }
}

/// `.mat`: blur 30 · saturate 180% → the HUD material behind the window.
private struct BarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
