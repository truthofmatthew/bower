import SwiftUI

/// SetWheel.dc.html: the wheel at 90% on a stage, a palette of actions to drag onto outer slots,
/// and the selected slot's card.
struct WheelEditorTab: View {
    @ObservedObject var store: Store
    let engine: Engine
    @State private var selected: Int?
    @State private var dropSlot: Int?
    @State private var dragName: String?

    private var slots: [WheelAction?] { store.state.wheelSlots }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            EditableWheel(slots: slots, selected: selected, dropSlot: dropSlot, dragName: dragName)
                .frame(width: 378, height: 414)
                // Clicks and drops land on a plain SwiftUI layer over the drawing, mapped back through the wheel geometry.
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { tap in
                            let p = CGPoint(x: tap.location.x / 0.9, y: tap.location.y / 0.9)
                            if case .outer(let i) = WheelGeometry.hit(p, arc: nil) { selected = i } else { selected = nil }
                        })
                        .onDrop(of: [.plainText], delegate: WheelDrop(dropSlot: $dropSlot, dragName: $dragName, slots: slots) { put($1, in: $0) })
                }
                .frame(width: 400, height: 448)
                .background(Palette.stage, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.hair, lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 8) {
                GroupHeading(text: "Actions · drag onto an outer slot")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(WheelAction.allCases, id: \.self) { a in action(a) }
                }
                Text("Greyed actions are already on the wheel. The inner ring always holds the eight snap targets. Drop onto the centre to cancel a drag.")
                    .font(.system(size: 11)).foregroundStyle(Palette.label2).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2).padding(.top, 2)
                Spacer(minLength: 0)
                slotCard
            }
        }
        .frame(height: 448)
    }

    /// `.act`: 30 tall, radius 7, 16 pt icon; greyed once it's on the wheel.
    private func action(_ a: WheelAction) -> some View {
        let used = slots.contains(a)
        return HStack(spacing: 7) {
            Image(nsImage: Self.icon(a)).renderingMode(.template)
            Text(a.paletteTitle).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .foregroundStyle(used ? Palette.label3 : Palette.label)
        .padding(.horizontal, 9).frame(height: 30)
        .background(Palette.group, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.hair, lineWidth: 0.5))
        .help(used ? "\(a.title) is on the wheel. Drag it to move it." : "Drag onto an outer slot, or select a slot and click")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(selected == nil ? "Select a slot first" : "Puts it in slot \((selected ?? 0) + 1)")
        .contentShape(Rectangle())
        // Click puts the action in the selected slot: the editor also works without dragging (keyboard, VoiceOver).
        .onTapGesture { if let i = selected { put(a, in: i) } }
        .onDrag {
            dragName = a.title
            return NSItemProvider(object: a.rawValue as NSString)
        }
    }

    @ViewBuilder private var slotCard: some View {
        if let i = selected {
            let a = slots[i]
            VStack(alignment: .leading, spacing: 8) {
                Text("Slot \(i + 1) · \(a?.title ?? String(localized: "hidden"))").fontWeight(.semibold)
                Text(a == nil ? "A hidden slot draws as an empty dashed wedge and does nothing on release."
                     : "Release on this slot to run \(a!.title). Drag another action here to replace it.")
                    .font(.system(size: 11)).foregroundStyle(Palette.label2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(a == nil ? "Show Slot" : "Hide Slot") {
                        var s = slots
                        // Showing a hidden slot brings back its default action if that isn't elsewhere on the wheel.
                        s[i] = a == nil ? WheelAction.defaults[i].flatMap { slots.contains($0) ? nil : $0 } ?? firstUnused() : nil
                        engine.setWheelSlots(s)
                    }
                    .buttonStyle(BowerButton())
                    Button("Restore Defaults") { engine.setWheelSlots(WheelAction.defaults) }.buttonStyle(BowerButton())
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.group, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.hair, lineWidth: 0.5))
        } else {
            HStack {
                Text("Click a slot to hide it, show it, or fill it from the list.").font(.system(size: 11)).foregroundStyle(Palette.label2)
                Spacer()
                Button("Restore Defaults") { engine.setWheelSlots(WheelAction.defaults) }.buttonStyle(BowerButton())
            }
        }
    }

    private func put(_ a: WheelAction, in i: Int) {
        var s = slots
        if let old = s.firstIndex(of: a) { s[old] = nil }  // an action lives in one slot
        s[i] = a
        engine.setWheelSlots(s)
        selected = i
    }

    private func firstUnused() -> WheelAction? { WheelAction.allCases.first { !slots.contains($0) } }

    static func icon(_ a: WheelAction) -> NSImage {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.addPath(a.icon)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.4)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// Turns a drop location on the 378 × 414 wheel into an outer slot, using the wheel's geometry at 90%.
private struct WheelDrop: DropDelegate {
    @Binding var dropSlot: Int?
    @Binding var dragName: String?
    let slots: [WheelAction?]
    let drop: (Int, WheelAction) -> Void

    private func slot(_ info: DropInfo) -> Int? {
        let p = CGPoint(x: info.location.x / 0.9, y: info.location.y / 0.9)
        if case .outer(let i) = WheelGeometry.hit(p, arc: nil) { return i }
        return nil
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText]) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropSlot = slot(info)
        return DropProposal(operation: dropSlot == nil ? .forbidden : .copy)
    }
    func dropExited(info: DropInfo) { dropSlot = nil }

    func performDrop(info: DropInfo) -> Bool {
        defer { dropSlot = nil; dragName = nil }
        guard let i = slot(info), let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let raw = obj as? String, let a = WheelAction(rawValue: raw) else { return }
            DispatchQueue.main.async { drop(i, a) }
        }
        return true
    }
}

/// The live wheel's drawing, at 90% (420 × 460 drawn into 378 × 414), with the drop target outlined.
private struct EditableWheel: NSViewRepresentable {
    let slots: [WheelAction?]
    let selected: Int?
    let dropSlot: Int?
    let dragName: String?

    func makeNSView(context: Context) -> EditableWheelView {
        let v = EditableWheelView(frame: NSRect(x: 0, y: 0, width: 378, height: 414))
        v.bounds = NSRect(origin: .zero, size: WheelGeometry.panelSize)
        return v
    }

    func updateNSView(_ v: EditableWheelView, context: Context) {
        v.model.slots = slots
        v.model.editing = true
        v.model.focus = selected.map { .outer($0) }
        v.model.dropSlot = dropSlot
        // WheelScale's edit state: "Drop “Center” to replace Retile".
        if let i = dropSlot {
            let name = dragName ?? String(localized: "action")
            v.model.caption = (slots[i].map { String(localized: "Drop “\(name)” to replace \($0.title)") } ?? String(localized: "Drop “\(name)” on slot \(i + 1)"), "")
        } else {
            v.model.caption = (String(localized: "Drag an action onto an outer slot"), "")
        }
        v.needsDisplay = true
    }
}

/// The wheel's drawing; selection and drops are handled by the SwiftUI layer above it.
final class EditableWheelView: WheelView {
    override func updateTrackingAreas() {}
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
