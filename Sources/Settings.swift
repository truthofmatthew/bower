import ServiceManagement
import SwiftUI

/// The Settings window: SetGeneral / SetLayouts / SetDisplays / SetShortcuts .dc.html.
struct SettingsView: View {
    enum Tab: String, CaseIterable {
        case general = "General", layouts = "Layouts", displays = "Displays", dock = "Dock", gestures = "Gestures",
             appearance = "Appearance", shortcuts = "Shortcuts", wheel = "Snap Wheel", ai = "AI"

        var icon: String {
            switch self {
            case .general: "M10 2.5v2M10 15.5v2M2.5 10h2M15.5 10h2M4.7 4.7l1.4 1.4M13.9 13.9l1.4 1.4M4.7 15.3l1.4-1.4M13.9 6.1l1.4-1.4"
            case .layouts: "M3 3h6v6H3zM11 3h6v6h-6zM3 11h6v6H3zM11 11h6v6h-6z"
            case .displays: "M2.5 3.5h15v10h-15zM7 17h6M10 13.5V17"
            case .dock: "M2.5 3.5h15v13h-15zM10 3.5v13M10 10h7.5"
            case .gestures: "M6 9V4.5a1.5 1.5 0 0 1 3 0V9M9 8V3.5a1.5 1.5 0 0 1 3 0V9M12 8.5V5a1.5 1.5 0 0 1 3 0v6a6 6 0 0 1-12 0V9.5a1.5 1.5 0 0 1 3 0"
            case .appearance: "M10 2.5a7.5 7.5 0 1 0 0 15zM10 2.5v15"
            case .shortcuts: "M2 5.5h16v9H2zM5 8.5h1M8 8.5h1M11 8.5h1M14 8.5h1M6 11.5h8"
            case .wheel: "M10 2.5V7M10 13v4.5M2.5 10H7M13 10h4.5"
            case .ai: "M5 2.5h7l3 3v12H5zM12 2.5v3h3M7.5 9.5h5M7.5 12h5M7.5 14.5h3"
            }
        }

        var title: String {
            switch self {
            case .general: String(localized: "General")
            case .layouts: String(localized: "Layouts")
            case .displays: String(localized: "Displays")
            case .dock: String(localized: "Dock")
            case .gestures: String(localized: "Gestures")
            case .appearance: String(localized: "Appearance")
            case .shortcuts: String(localized: "Shortcuts")
            case .wheel: String(localized: "Snap Wheel")
            case .ai: String(localized: "AI")
            }
        }

        /// Circles the parser doesn't cover, drawn alongside the path (General's hub, the wheel's rings).
        var circles: [CGFloat] {
            switch self {
            case .general: [3.5]
            case .wheel: [7.5, 3]
            default: []
            }
        }

        var available: Bool { true }
    }

    @ObservedObject var store: Store
    let engine: Engine
    var shortcuts = ShortcutCenter()
    var openReport: () -> Void = {}
    var openLessons: () -> Void = {}
    var setMissionControl: (Bool) -> Void = { _ in }
    @State var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(verbatim: tab.title).font(.system(size: 13, weight: .semibold)).frame(height: 30)
                HStack(spacing: 2) {
                    ForEach(Tab.allCases, id: \.self) { t in tool(t) }
                }
                .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
            .background(Palette.chrome)
            .overlay(alignment: .bottom) { Palette.hair.frame(height: 1) }

            Group {
                switch tab {
                case .general: GeneralTab(store: store, engine: engine, openReport: openReport, openLessons: openLessons)
                case .layouts: LayoutsTab(store: store, engine: engine)
                case .displays: DisplaysTab(store: store, engine: engine)
                case .dock: DockTab(store: store, engine: engine)
                case .gestures: GesturesTab(store: store, engine: engine, setMissionControl: setMissionControl)
                case .appearance: AppearanceTab(store: store, engine: engine)
                case .ai: AITab(store: store, engine: engine)
                case .wheel: WheelEditorTab(store: store, engine: engine)
                default: ShortcutsTab(store: store, engine: engine, center: shortcuts)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .font(.system(size: 13))
        .foregroundStyle(Palette.label)
        .frame(width: 760, height: 560)
        .background(Palette.window)
    }

    private func tool(_ t: Tab) -> some View {
        Button { tab = t } label: {
            VStack(spacing: 3) {
                ZStack {
                    Glyph(d: t.icon, grid: 20, size: 22)
                    ForEach(t.circles, id: \.self) { r in
                        Circle().stroke(lineWidth: 1.5 * 22 / 20).frame(width: 2 * r * 22 / 20, height: 2 * r * 22 / 20)
                    }
                }
                .foregroundStyle(tab == t ? Palette.accent : Palette.label2)
                Text(verbatim: t.title).font(.system(size: 11)).foregroundStyle(tab == t ? Palette.label : Palette.label2)
                    .lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 6)
            .frame(minWidth: 78, minHeight: 48, maxHeight: 48)  // 78 pt as designed; longer translated labels widen it
            .background(tab == t ? Palette.fill2 : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!t.available)
        .opacity(t.available ? 1 : 0.45)
        .help(t.available ? "" : "Arrives in a later version")
        .accessibilityAddTraits(tab == t ? .isSelected : [])
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var store: Store
    let engine: Engine
    var openReport: () -> Void = {}
    var openLessons: () -> Void = {}
    @State private var atLogin = SMAppService.mainApp.status == .enabled

    private let styles: [(StatusStyle, String, String)] = [
        (.numberAndName, String(localized: "Layout number and name"), "3 · \(String(localized: "Dev"))"),
        (.iconOnly, String(localized: "Icon only"), ""),
        (.numberOnly, String(localized: "Layout number only"), "3"),
        (.windowCount, String(localized: "Window count in this layout"), String(localized: "\(5) windows"))
    ]

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            FormGroup {
                FormRow(first: true) {
                    RowText(title: "Launch Bower at login")
                    Toggle("", isOn: Binding(get: { atLogin }, set: setLogin)).toggleStyle(BowerToggle())
                        .accessibilityLabel("Launch Bower at login")
                }
                FormRow {
                    RowText(title: "Hide windows that aren't in the current layout",
                            sub: "Off: windows from other layouts stay where they are, behind.")
                    Toggle("", isOn: Binding(get: { store.state.hideOtherLayouts }, set: engine.setHideOtherLayouts))
                        .toggleStyle(BowerToggle())
                        .accessibilityLabel("Hide windows not in layout")
                }
                FormRow {
                    RowText(title: "Full screen stays in its layout",
                            sub: "The green button fills the screen instead of opening a new desktop, which no layout can hold.")
                    Toggle("", isOn: Binding(get: { store.state.keepFullScreenHere }, set: engine.setKeepFullScreenHere))
                        .toggleStyle(BowerToggle())
                        .accessibilityLabel("Full screen stays in its layout")
                }
            }
            GroupHeading(text: "Menu bar item")
            FormGroup {
                ForEach(Array(styles.enumerated()), id: \.offset) { i, s in
                    FormRow(first: i == 0) {
                        Radio(on: store.state.statusStyle == s.0)
                        RowText(verbatim: s.1)
                        HStack(spacing: 5) {
                            BowerGlyph(size: 13)
                            if !s.2.isEmpty { Text(s.2).font(.system(size: 12, weight: .medium)) }
                        }
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { engine.setStatusStyle(s.0) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(store.state.statusStyle == s.0 ? [.isButton, .isSelected] : .isButton)
                }
            }
            FormGroup {
                FormRow(first: true) {
                    RowText(title: "When an app in a layout isn't running",
                            sub: "On a Bento Box display, the tile of an app you quit can wait for it to come back.")
                    Menu {
                        Button("Keep its space empty") { engine.setKeepEmptySpace(true) }
                        Button("Let other windows use it") { engine.setKeepEmptySpace(false) }
                    } label: { PopLabel(text: store.state.keepEmptySpace ? String(localized: "Keep its space empty") : String(localized: "Let other windows use it")) }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
            }
            GeneralMore(store: store, engine: engine, openReport: openReport, openLessons: openLessons)
            (Text("Bower is free and open source and runs only on this Mac. No account, and no network access unless you set up an AI endpoint or turn on update checks. ")
                + Text("[View source](https://github.com/truthofmatthew/bower)"))
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(Palette.label2).tint(Palette.accent)
                .padding(.horizontal, 4)
        }
        .padding(.bottom, 8)
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Bower: login item change failed: \(error)")
        }
        atLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Layouts

private struct LayoutsTab: View {
    @ObservedObject var store: Store
    let engine: Engine
    @State private var dragging: Int?
    @State private var selectedRoute: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                GroupHeading(text: "Layouts · drag to reorder")
                FormGroup {
                    HStack(spacing: 8) {
                        Spacer().frame(width: 12)
                        Text("#").frame(width: 18, alignment: .leading)
                        Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(NSScreen.screens.prefix(2), id: \.uuid) { s in
                            Text(s.localizedName).lineLimit(1).frame(width: 96, alignment: .leading)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.label2)
                    .padding(.horizontal, 10).frame(height: 26)
                    .overlay(alignment: .bottom) { Palette.hair.frame(height: 1) }
                    ForEach(0..<9, id: \.self) { i in layoutRow(i) }
                }
            }
            .frame(width: 432)

            VStack(alignment: .leading, spacing: 8) {
                GroupHeading(text: "App routing")
                FormGroup {
                    HStack(spacing: 8) {
                        Text("App").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Opens in").frame(width: 112, alignment: .leading)
                    }
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.label2)
                    .padding(.horizontal, 10).frame(height: 26)
                    .overlay(alignment: .bottom) { Palette.hair.frame(height: 1) }
                    ForEach(store.state.routes.keys.sorted(), id: \.self) { id in routeRow(id) }
                    HStack(spacing: 0) {
                        Menu {
                            ForEach(unroutedApps, id: \.bundleIdentifier) { app in
                                Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                                    if let id = app.bundleIdentifier { engine.route(bundleID: id, to: store.state.current) }
                                }
                            }
                        } label: { Text("+").font(.system(size: 15)).frame(width: 30, height: 28) }
                            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                            .overlay(alignment: .trailing) { Palette.hair.frame(width: 1) }
                            .accessibilityLabel("Add app")
                        Button {
                            if let id = selectedRoute { engine.route(bundleID: id, to: nil); selectedRoute = nil }
                        } label: { Text("−").font(.system(size: 15)).frame(width: 30, height: 28) }
                            .buttonStyle(.plain).disabled(selectedRoute == nil)
                            .overlay(alignment: .trailing) { Palette.hair.frame(width: 1) }
                            .accessibilityLabel("Remove app")
                        Spacer()
                    }
                    .frame(height: 28)
                    .overlay(alignment: .top) { Palette.hair.frame(height: 1) }
                }
                Text("New windows of a routed app open in that layout, even while another is showing. Unrouted apps stay where you put them.")
                    .font(.system(size: 11)).foregroundStyle(Palette.label2).padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var unroutedApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && store.state.routes[$0.bundleIdentifier!] == nil
                && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func layoutRow(_ i: Int) -> some View {
        let l = store.state.layouts[i]
        let cur = i == store.state.current
        return HStack(spacing: 8) {
            Glyph(d: "M4 2.5h.01M8 2.5h.01M4 6h.01M8 6h.01M4 9.5h.01M8 9.5h.01", grid: 12, size: 12, width: 2)
                .foregroundStyle(Palette.label3)
            Text("\(i + 1)").font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(cur ? Palette.onAccent : Palette.label)
                .frame(width: 18, height: 18)
                .background(cur ? Palette.accent : Palette.fill2, in: RoundedRectangle(cornerRadius: 5))
            NameField(name: l.name, dim: l.isUntitled) { engine.rename(i, to: $0) }
            Button { engine.clearLayout(i) } label: {
                Glyph(d: "M4.5 4.5l7 7M11.5 4.5l-7 7", size: 12, width: 1.75).frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.label3)
            .opacity(l.isUntitled && l.modes.isEmpty ? 0 : 1)
            .disabled(l.isUntitled && l.modes.isEmpty)
            .help("Clear this layout: its name goes back to Untitled and its modes to Native. Its windows stay put.")
            .accessibilityLabel("Clear layout \(i + 1)")
            ForEach(NSScreen.screens.prefix(2), id: \.uuid) { s in
                ModeMenu(mode: l.modes[s.uuid] ?? .native) { engine.setMode($0, display: s.uuid, layout: i) }
                    .frame(width: 96)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(dragging == i ? Palette.groupSolid : .clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .top) { if i > 0 { Palette.hair.frame(height: 1) } }
        .onDrag {
            dragging = i
            return NSItemProvider(object: "\(i)" as NSString)
        }
        .onDrop(of: [.plainText], delegate: RowDrop(target: i, dragging: $dragging) { engine.moveLayout(from: $0, to: $1) })
    }

    private func routeRow(_ id: String) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
        let n = store.state.routes[id]
        return HStack(spacing: 8) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
                .resizable().frame(width: 18, height: 18)
            Text(name).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            Menu {
                Button("Current layout") { engine.route(bundleID: id, to: nil) }
                ForEach(0..<9, id: \.self) { i in
                    Button("\(i + 1) · \(store.state.layouts[i].name)") { engine.route(bundleID: id, to: i) }
                }
            } label: {
                PopLabel(text: n.map { "\($0 + 1) · \(store.state.layouts[$0].name)" } ?? String(localized: "Current layout"))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).frame(width: 112)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(selectedRoute == id ? Palette.accentFill : .clear)
        .overlay(alignment: .top) { Palette.hair.frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { selectedRoute = id }
    }
}

private struct RowDrop: DropDelegate {
    let target: Int
    @Binding var dragging: Int?
    let move: (Int, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil }
        guard let from = dragging else { return false }
        move(from, target)
        return true
    }
}

/// Inline layout name: plain text until clicked, saved on Return or when focus leaves.
private struct NameField: View {
    let name: String
    let dim: Bool
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.plain)
            .foregroundStyle(dim && !focused ? Palette.label3 : Palette.label)
            .focused($focused)
            .onAppear { text = name }
            .onChange(of: name) { _, n in if !focused { text = n } }
            .onChange(of: focused) { _, f in if !f { save() } }
            .onSubmit(save)
            .frame(maxWidth: .infinity)
    }

    private func save() {
        // An empty name sets the layout back to Untitled: unused, and left out of the menu bar list.
        let t = text.trimmingCharacters(in: .whitespaces)
        let n = t.isEmpty ? Layout.untitled : t
        text = n
        if n != name { commit(n) }
    }
}

/// `.pop`: 26 tall, radius 6, control fill, a ⌄ on the right.
struct PopLabel: View {
    let text: String
    var height: CGFloat = 26
    var body: some View {
        HStack(spacing: 10) {
            Text(text).lineLimit(1)
            Spacer(minLength: 0)
            Text("⌄").font(.system(size: 11)).foregroundStyle(Palette.label2).offset(y: -3)
        }
        .padding(.leading, 10).padding(.trailing, 8)
        .frame(height: height)
        .background(Palette.control, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.hair, lineWidth: 0.5))
    }
}

/// A popover rather than a menu, so each mode can play a demo of what it does.
private struct ModeMenu: View {
    let mode: WindowMode
    let set: (WindowMode) -> Void
    @State private var open = false

    var body: some View {
        Button { open = true } label: { PopLabel(text: mode.title) }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(WindowMode.allCases, id: \.self) { m in
                        Button { set(m); open = false } label: { row(m) }.buttonStyle(.plain)
                    }
                }
                .padding(8)
                .frame(width: 340)
            }
    }

    private func row(_ m: WindowMode) -> some View {
        HStack(spacing: 10) {
            DemoView(scene: m.demo, key: m.rawValue).frame(width: 88, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title).fontWeight(.semibold)
                Text(m.blurb).font(.system(size: 11)).foregroundStyle(Palette.label2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if m == mode { Glyph(d: "M3.5 8.5l3 3 6-7", size: 12, width: 2).foregroundStyle(Palette.accent) }
        }
        .padding(6)
        .background(m == mode ? Palette.fill : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(m == mode ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Displays

private struct DisplaysTab: View {
    @ObservedObject var store: Store
    let engine: Engine
    @State private var selected = NSScreen.main?.uuid

    var body: some View {
        let screens = NSScreen.screens
        let screen = screens.first { $0.uuid == selected } ?? screens.first
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(tiles(screens, in: geo.size), id: \.0.uuid) { s, r in tile(s, r, selected: s.uuid == screen?.uuid) }
                    Text("Arrangement follows System Settings. Click a display to edit it.")
                        .font(.system(size: 11)).foregroundStyle(Palette.label2)
                        .position(x: 12 + 160, y: geo.size.height - 14)
                        .frame(width: 344, alignment: .leading)
                }
            }
            .frame(height: 136)
            .background(Palette.stage, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.hair, lineWidth: 0.5))

            if let screen {
                GroupHeading(verbatim: screen.localizedName)
                FormGroup {
                    FormRow(first: true) {
                        RowText(title: "Window mode")
                        ModeMenu(mode: engine.mode(of: screen)) { engine.setMode($0, for: screen) }.fixedSize()
                    }
                    FormRow {
                        RowText(title: "Pin this display", sub: "A pinned display keeps its windows when you switch layouts elsewhere.")
                        Toggle("", isOn: Binding(get: { store.state.pinned.contains(screen.uuid) }, set: { _ in engine.togglePin(screen) }))
                            .toggleStyle(BowerToggle())
                            .accessibilityLabel("Pin \(screen.localizedName)")
                    }
                }
            }

            if !store.state.shelf.isEmpty {
                GroupHeading(text: "Offline shelf")
                FormGroup {
                    ForEach(Array(store.state.shelf.enumerated()), id: \.element.display.uuid) { i, entry in shelfRow(entry, first: i == 0) }
                }
            }
        }
    }

    /// "Last seen Oct 28 · 3 layouts, 7 windows saved · Bento Box"
    private func shelfRow(_ e: ShelfEntry, first: Bool) -> some View {
        let layouts = Set(e.windows.map(\.layout)).count, count = e.windows.count
        let mode = (e.modes[store.state.current] ?? .native).title
        let date = e.lastSeen.formatted(.dateTime.month(.abbreviated).day())
        let meta = [String(localized: "Last seen \(date)"),
                    (layouts == 1 ? String(localized: "1 layout") : String(localized: "\(layouts) layouts")) + ", "
                        + (count == 1 ? String(localized: "1 window saved") : String(localized: "\(count) windows saved")),
                    mode].joined(separator: " · ")
        return FormRow(first: first) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Palette.label3, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 44, height: 28)
            RowText(verbatim: e.display.name, sub: meta)
            Menu {
                ForEach(NSScreen.screens, id: \.uuid) { s in Button(s.localizedName) { engine.restore(e, onto: s) } }
                Divider()
                Button("Forget \(e.display.name)") { engine.forget(e) }
            } label: { PopLabel(text: String(localized: "Move to…")) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
    }

    /// Scales the real arrangement (AppKit frames) into the stage, centred, at most 90 pt tall per display.
    private func tiles(_ screens: [NSScreen], in size: CGSize) -> [(NSScreen, CGRect)] {
        let all = screens.reduce(CGRect.null) { $0.union($1.frame) }
        guard !all.isNull else { return [] }
        let scale = min(90 / (screens.map(\.frame.height).max() ?? 1), (size.width - 40) / all.width, (size.height - 40) / all.height)
        let w = all.width * scale, h = all.height * scale
        let ox = (size.width - w) / 2, oy = (size.height - 24 - h) / 2
        return screens.map { s in
            let f = s.frame
            return (s, CGRect(x: ox + (f.minX - all.minX) * scale, y: oy + (all.maxY - f.maxY) * scale,
                              width: f.width * scale - 8, height: f.height * scale))
        }
    }

    private func tile(_ s: NSScreen, _ r: CGRect, selected: Bool) -> some View {
        let st = store.state
        let pinned = st.pinned.contains(s.uuid)
        let isMain = s == NSScreen.screens.first
        return Button { self.selected = s.uuid } label: {
            VStack(spacing: 2) {
                Text(r.width < 90 ? String(s.localizedName.prefix(2)) : s.localizedName).lineLimit(1)
                Text((isMain ? "Main · " : "") + "\(st.current + 1) · \(st.layouts[st.current].name)")
                    .fontWeight(.medium).opacity(0.85).lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            .padding(.horizontal, 4)
            .frame(width: r.width, height: r.height)
            .background(Palette.screen, in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .top) {
                if isMain { UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5).fill(.white.opacity(0.55)).frame(height: 6) }
            }
            .overlay(alignment: .topTrailing) {
                if pinned {
                    Glyph(d: "M10.5 1.5 14.5 5.5 12 6.5 9.5 9l.5 3.5-1 1-3-3-3.5 3.5M5.5 10.5l-3-3 1-1L7 7l2.5-2.5 1-2.5", size: 11, width: 1.8)
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 18, height: 18).background(Palette.accent, in: Circle())
                        .padding(.top, 10).padding(.trailing, 6)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.hair, lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 5).inset(by: -2.5).strokeBorder(selected ? Palette.accent : .clear, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .offset(x: r.minX, y: r.minY)
        .accessibilityLabel("\(s.localizedName)\(isMain ? ", main" : "")\(pinned ? ", pinned" : "")\(selected ? ", selected" : "")")
    }
}

// MARK: - Shortcuts

/// SetShortcuts.dc.html: keyboard preset, then two columns of rows, each with a recorder.
private struct ShortcutsTab: View {
    @ObservedObject var store: Store
    let engine: Engine
    @ObservedObject var center: ShortcutCenter

    private let left = ["Overlays", "Layouts", "Windows"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("Keyboard")
                    Segmented(options: ["ANSI", "ISO"], selected: store.state.isoKeyboard ? "ISO" : "ANSI") { engine.setISO($0 == "ISO") }
                    Text("ISO uses ⌃⌥< (the key left of Z) for Center Third.").font(.system(size: 11)).foregroundStyle(Palette.label2)
                }
                if let n = center.notice {
                    Text(n).font(.system(size: 12)).foregroundStyle(Palette.warn).padding(.horizontal, 4)
                }
                HStack(alignment: .top, spacing: 14) {
                    // Definite column widths: inside a ScrollView, flexible ones get measured too wide, and
                    // wrapped (translated) text then overflows its row.
                    VStack(alignment: .leading, spacing: 8) { ForEach(left, id: \.self) { group($0) } }
                        .frame(width: 345)
                    VStack(alignment: .leading, spacing: 8) {
                        group("Snapping")
                        group("Zoom")
                        group("Dock")
                        HStack {
                            Spacer()
                            Button("Restore Defaults") { center.stop(); engine.resetShortcuts() }.buttonStyle(BowerButton())
                        }
                        .padding(.top, 4)
                    }
                    .frame(width: 345)
                }
            }
        }
        .onDisappear { center.stop() }
    }

    @ViewBuilder private func group(_ name: String) -> some View {
        let rows = ShortcutID.allCases.filter { $0.group == name }
        GroupHeading(verbatim: rows.first?.groupTitle ?? name)
        FormGroup {
            ForEach(Array(rows.enumerated()), id: \.element) { i, id in row(id, first: i == 0) }
            if name == "Overlays" {
                FormRow {
                    RowText(title: "Three-finger tap opens the Snap Wheel",
                            sub: !TrackpadTap.shared.available ? "No trackpad found."
                                : TrackpadTap.systemUsesThreeFingerTap ? "macOS also uses this tap for Look Up (System Settings › Trackpad)."
                                : "Tap with three fingers, then click an action.")
                    Toggle("", isOn: Binding(get: { store.state.trackpadTapOn }, set: engine.setTrackpadTapWheel))
                        .toggleStyle(BowerToggle())
                        .disabled(!TrackpadTap.shared.available)
                        .accessibilityLabel("Three-finger tap opens the Snap Wheel")
                }
                FormRow {
                    RowText(title: "Swipe sideways to change layout", sub: "Fingers, and how it shares the swipe with macOS, are in Settings › Gestures.")
                    Toggle("", isOn: Binding(get: { store.state.swipeLayouts }, set: engine.setSwipeLayouts))
                        .toggleStyle(BowerToggle())
                        .accessibilityLabel("Swipe sideways to change layout")
                }
                FormRow {
                    RowText(title: "Middle-click opens the Snap Wheel", sub: "Off: the middle button goes to apps as usual.")
                    Toggle("", isOn: Binding(get: { store.state.middleClickWheel }, set: engine.setMiddleClickWheel))
                        .toggleStyle(BowerToggle())
                        .accessibilityLabel("Middle-click opens the Snap Wheel")
                }
            }
        }
    }

    private func row(_ id: ShortcutID, first: Bool) -> some View {
        let recording = center.recording == id
        let conflict = center.conflicts[id]
        let sub = recording ? String(localized: "Recording · Esc cancels, ⌫ clears") : conflict ?? id.sub
        return FormRow(first: first) {
            VStack(alignment: .leading, spacing: 2) {
                Text(id.title).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                if let sub {
                    Text(sub).font(.system(size: 11)).foregroundStyle(conflict != nil && !recording ? Palette.warn : Palette.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Recorder(id: id, combo: store.state.combo(id), iso: store.state.isoKeyboard, recording: recording, conflict: conflict != nil) {
                recording ? center.stop() : center.record(id, store: store, engine: engine)
            }
        }
    }
}

/// `.rec`: 128 × 28, keycaps inside; recording = accent ring and tint; conflict = warning ring.
private struct Recorder: View {
    let id: ShortcutID
    let combo: Combo?
    let iso: Bool
    let recording: Bool
    let conflict: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 3) {
                if recording {
                    Text("Type shortcut…").font(.system(size: 12)).foregroundStyle(Palette.label2)
                } else if let combo {
                    ForEach(Array(KeyNames.caps(id, combo, iso: iso).enumerated()), id: \.offset) { _, k in
                        Text(k).font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 4).frame(minWidth: 18, minHeight: 18)
                            .background(Palette.control, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.hair, lineWidth: 0.5))
                    }
                } else {
                    Text("Record").font(.system(size: 12)).foregroundStyle(Palette.label3)
                }
            }
            // A key combination reads ⌃ ⌥ ← in every language, including right-to-left ones.
            .environment(\.layoutDirection, .leftToRight)
            .frame(width: 128, height: 28)
            .background(recording ? Palette.accentFill : Palette.field, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(conflict && !recording ? Palette.warn : Palette.hair, lineWidth: conflict && !recording ? 1 : 0.5))
            .overlay(RoundedRectangle(cornerRadius: 7).inset(by: -2).strokeBorder(recording ? Palette.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(id.title) shortcut")
        .accessibilityValue(recording ? "Recording" : combo.map { KeyNames.caps(id, $0, iso: iso).joined(separator: " ") } ?? "None")
    }
}
