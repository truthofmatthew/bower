import SwiftUI

/// How a setting is offered: in every build, only with "Show advanced settings", or never in a release.
enum SettingLevel { case standard, advanced, hidden }

private struct LevelModifier: ViewModifier {
    let level: SettingLevel
    let showAdvanced: Bool
    func body(content: Content) -> some View {
        #if DEBUG
        let shown = level != .hidden || showAdvanced
        #else
        let shown = level == .standard || (level == .advanced && showAdvanced)
        #endif
        if shown { content }
    }
}

extension View {
    func level(_ l: SettingLevel, _ store: Store) -> some View { modifier(LevelModifier(level: l, showAdvanced: store.state.prefs.showAdvanced)) }
}

/// Small builders shared by the newer tabs, so each row is one line.
struct PrefRows {
    @ObservedObject var store: Store
    let engine: Engine

    func bind<T>(_ kp: WritableKeyPath<Prefs, T>) -> Binding<T> {
        Binding(get: { store.state.prefs[keyPath: kp] }, set: { v in engine.setPrefs { $0[keyPath: kp] = v } })
    }

    func toggle(_ title: LocalizedStringKey, _ sub: LocalizedStringKey? = nil, _ kp: WritableKeyPath<Prefs, Bool>, first: Bool = false) -> some View {
        FormRow(first: first) {
            RowText(title: title, sub: sub)
            Toggle("", isOn: bind(kp)).toggleStyle(BowerToggle()).accessibilityLabel(Text(title))
        }
    }

    func slider(_ title: LocalizedStringKey, _ sub: LocalizedStringKey? = nil, _ kp: WritableKeyPath<Prefs, Double>, _ range: ClosedRange<Double>,
                step: Double, format: @escaping (Double) -> String, first: Bool = false) -> some View {
        FormRow(first: first) {
            RowText(title: title, sub: sub)
            Slider(value: bind(kp), in: range, step: step).frame(width: 150).accessibilityLabel(Text(title))
            Text(format(store.state.prefs[keyPath: kp])).font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.label2)
                .frame(width: 52, alignment: .trailing)
        }
    }

    func menu<T: Hashable>(_ title: LocalizedStringKey, _ sub: LocalizedStringKey? = nil, _ kp: WritableKeyPath<Prefs, T>,
                           _ options: [(T, String)], first: Bool = false) -> some View {
        FormRow(first: first) {
            RowText(title: title, sub: sub)
            Menu {
                ForEach(options, id: \.0) { o in Button(o.1) { engine.setPrefs { $0[keyPath: kp] = o.0 } } }
            } label: { PopLabel(text: options.first { $0.0 == store.state.prefs[keyPath: kp] }?.1 ?? "") }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
    }
}

private func ms(_ v: Double) -> String { String(localized: "\(Int((v * 1000).rounded())) ms") }
private func pt(_ v: Double) -> String { String(localized: "\(Int(v.rounded())) pt") }
private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
private func times(_ v: Double) -> String { String(format: "%.1f×", v) }

// MARK: - Dock

struct DockTab: View {
    @ObservedObject var store: Store
    let engine: Engine

    var body: some View {
        let r = PrefRows(store: store, engine: engine)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("In Dock mode windows sit side by side and never overlap. Turn it on for a display in Bower's menu › This Display, then drag a title bar to another window's edge to dock it there.")
                    .font(.system(size: 12)).foregroundStyle(Palette.label2).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                GroupHeading(text: "Windows")
                FormGroup {
                    r.slider("Space between windows", nil, \.gap, 0...32, step: 1, format: pt, first: true)
                    r.toggle("Drag the gaps between windows to resize them", nil, \.gapHandles)
                    r.toggle("Always show drag handles", "Otherwise a gap's handle shows when the pointer is over it.", \.gapHandlesAlwaysShown).level(.advanced, store)
                    r.menu("Closing", nil, \.shareRemovedSpace, [(true, String(localized: "Share its space with the whole row")),
                                                                  (false, String(localized: "Give its space to the neighbour after it"))])
                    r.toggle("Windows can be squeezed below their app's minimum", nil, \.squeezeBelowMinimum).level(.advanced, store)
                    r.toggle("Show a window too small for its tile as its icon", "Double-click the icon to see the window on its own. It's a real window again as soon as it fits.", \.collapseSmall).level(.advanced, store)
                    r.toggle("Park hidden windows small", "Windows out of view, and a group's other tabs. Leaves room for the rest in Mission Control; each is resized as it's shown again.", \.parkSmall).level(.advanced, store)
                }
                GroupHeading(text: "Dragging a title bar")
                FormGroup {
                    r.toggle("Show where it will land", nil, \.previewDrags, first: true)
                    r.slider("Hold over a target", "How long before the layout makes room. Letting go drops it there at once.", \.holdDelay, 0...1.5, step: 0.05, format: ms)
                    r.toggle("Windows make room live during drags", "Otherwise they're covered until you let go, and resized once.", \.reflowWhileDragging).level(.advanced, store)
                    r.toggle("Pushed windows stay pushed while dragging", "Otherwise dragging back undoes each push.", \.keepPushed).level(.advanced, store)
                    r.toggle("Double-click a title bar frames the window on its own", "Double-click again to go back. ⌥-double-click still zooms.", \.doubleClickFrames)
                }
                GroupHeading(text: "Green button and the Desktop")
                FormGroup {
                    r.toggle("Green button floats and docks", "Instead of full screen. fn-click still goes full screen, and ⌥-click zooms.", \.greenButtonFloats, first: true)
                    r.toggle("A sole floating window takes the Desktop's space", "Only for a window that's the only one floating: it fills the Desktop's tile.", \.soleFloatTakesDesktop).level(.advanced, store)
                    r.toggle("Floating a window brings the Desktop back", "When the Desktop is hidden in this layout.", \.hiddenDesktopReturns).level(.advanced, store)
                }
            }
            .padding(.bottom, 8)
        }
    }
}

private struct IgnoredApps: View {
    @ObservedObject var store: Store
    let engine: Engine

    var body: some View {
        GroupHeading(text: "Apps left alone")
        FormGroup {
            FormRow(first: true) {
                RowText(title: "Windows of these apps are left alone", sub: "They float freely and are never arranged, in any mode.")
                Menu {
                    let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
                    ForEach(running, id: \.processIdentifier) { a in
                        Button(a.localizedName ?? AppInfo.name(a.bundleIdentifier!)) { engine.setIgnored(a.bundleIdentifier!, true) }
                    }
                } label: { PopLabel(text: String(localized: "Add App")) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            ForEach(store.state.prefs.ignoredApps.sorted(), id: \.self) { id in
                FormRow {
                    AppRow(bundleID: id)
                    Button("Arrange Again") { engine.setIgnored(id, false) }.buttonStyle(BowerButton())
                }
            }
        }
    }
}

private struct MissingWindows: View {
    @ObservedObject var store: Store
    let engine: Engine
    @State private var confirm = false

    var body: some View {
        let r = PrefRows(store: store, engine: engine)
        let missing = engine.missingWindows
        GroupHeading(text: "Putting windows back")
        FormGroup {
            r.menu("Windows an app reopens go back to their places", nil, \.returnWindows,
                   [(ReturnWindows.afterQuit, String(localized: "After a quit or restart")),
                    (.alsoReopened, String(localized: "Also when reopened")),
                    (.never, String(localized: "Never"))], first: true)
            FormRow {
                RowText(title: "Missing windows",
                        sub: "Places Bower is keeping for windows that closed, or whose app quit. They go back there when they open again.")
                Text(missing.count == 1 ? String(localized: "1 missing") : String(localized: "\(missing.count) missing"))
                    .font(.system(size: 12)).foregroundStyle(Palette.label2)
                Button("Forget Missing Windows…") { confirm = true }.buttonStyle(BowerButton()).disabled(missing.isEmpty)
            }
            ForEach(Array(missing.suffix(8).enumerated()), id: \.offset) { _, w in
                FormRow {
                    let app = AppInfo.name(w.bundleID)
                    AppRow(bundleID: w.bundleID, title: w.title.isEmpty ? app : w.title,
                           sub: "\(app) · \(w.layout + 1) · \(store.state.layouts[w.layout].name)")
                    Button("Forget") { engine.forgetMissing(w) }.buttonStyle(BowerButton())
                }
            }
        }
        .alert(missing.count == 1 ? String(localized: "Forget 1 missing window?") : String(localized: "Forget \(missing.count) missing windows?"),
               isPresented: $confirm) {
            Button("Forget", role: .destructive) { engine.forgetMissing() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("If they open again, they're placed as new windows.") }
    }
}

// MARK: - Gestures

struct GesturesTab: View {
    @ObservedObject var store: Store
    let engine: Engine
    let setMissionControl: (Bool) -> Void

    var body: some View {
        let r = PrefRows(store: store, engine: engine)
        let p = store.state.prefs
        let ex = DockSwipe.explanation(fingers: p.swipeFingers, missionControl: p.replaceMissionControl)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupHeading(text: "Snap Wheel")
                FormGroup {
                    FormRow(first: true) {
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
                        RowText(title: "Middle-click opens the Snap Wheel", sub: "Off: the middle button goes to apps as usual.")
                        Toggle("", isOn: Binding(get: { store.state.middleClickWheel }, set: engine.setMiddleClickWheel))
                            .toggleStyle(BowerToggle())
                            .accessibilityLabel("Middle-click opens the Snap Wheel")
                    }
                }
                GroupHeading(text: "Moving between layouts")
                FormGroup {
                    FormRow(first: true) {
                        RowText(title: "Swipe sideways to change layout", sub: "Swipe left for the next layout, right for the previous one.")
                        Toggle("", isOn: Binding(get: { store.state.swipeLayouts }, set: engine.setSwipeLayouts)).toggleStyle(BowerToggle())
                            .accessibilityLabel("Swipe sideways to change layout")
                    }
                    FormRow {
                        RowText(title: "Move around with")
                        Segmented(options: [String(localized: "Three fingers"), String(localized: "Four fingers")],
                                  selected: p.swipeFingers == 3 ? String(localized: "Three fingers") : String(localized: "Four fingers")) { o in
                            engine.setPrefs { $0.swipeFingers = o == String(localized: "Three fingers") ? 3 : 4 }
                        }
                    }
                    FormRow {
                        Text(verbatim: ex.text).font(.system(size: 12)).foregroundStyle(ex.needsSettings ? Palette.warn : Palette.label2)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        if ex.needsSettings {
                            Button("Open macOS Trackpad Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
                            }
                            .buttonStyle(BowerButton())
                        }
                    }
                    r.toggle("Swipe the other way round", nil, \.swipeInvert).level(.advanced, store)
                }
                GroupHeading(text: "Mission Control")
                FormGroup {
                    FormRow(first: true) {
                        RowText(title: "Show Bower's overview instead",
                                sub: "Mission Control's swipe and shortcut open Bower's overview instead. Hold fn for Mission Control itself.")
                        Toggle("", isOn: Binding(get: { p.replaceMissionControl }, set: setMissionControl)).toggleStyle(BowerToggle())
                            .accessibilityLabel("Show Bower's overview instead of Mission Control")
                    }
                }
                GroupHeading(text: "Zoom")
                FormGroup {
                    r.toggle("Pinch to zoom", "Pinch in to step out a level or see everything; pinch out to step in.", \.pinchZoom, first: true)
                    r.menu("Pinching", nil, \.pinchNeedsOption, [(true, String(localized: "With ⌥ anywhere, or on bare desktop")),
                                                                  (false, String(localized: "Anywhere, without ⌥"))])
                    r.slider("Pan speed", "Hold ⌥ and pan with two fingers to move to the neighbouring window.", \.panSpeed, 0.5...4, step: 0.1, format: times)
                        .level(.advanced, store)
                    r.toggle("⌘⇧-drag a rectangle to zoom to what it frames", "⌘⌥⇧ works too; Esc cancels.", \.marqueeZoom)
                }
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Appearance

struct AppearanceTab: View {
    @ObservedObject var store: Store
    let engine: Engine

    var body: some View {
        let r = PrefRows(store: store, engine: engine)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupHeading(text: "Moving windows")
                FormGroup {
                    r.slider("Animation speed", "How fast windows move and fade. With Reduce Motion on in System Settings › Accessibility › Display, windows go straight to where they're going.",
                             \.animationSpeed, 0...3, step: 0.25, format: { $0 == 0 ? String(localized: "Off") : times($0) }, first: true)
                    r.toggle("A click during an animation ends it", nil, \.interruptAnimations).level(.advanced, store)
                    r.slider("Wait for apps to redraw", "After a window is resized, how long its app has to draw at its new size before Bower shows it. Raise it if windows flash an old layout.",
                             \.redrawWait, 0...1.5, step: 0.05, format: ms).level(.advanced, store)
                    r.toggle("Stretch windows as they move", "Their content stretches with them until they redraw at their new size. Otherwise it keeps its size, revealed or cropped.", \.stretchPictures).level(.advanced, store)
                }
                GroupHeading(text: "Previews")
                FormGroup {
                    FormRow(first: true) {
                        RowText(title: "See your windows as they are",
                                sub: "With Screen Recording allowed, the overview and moving windows show their real contents: still pictures, never recorded or kept. Without it, windows show as their app's colour and icon.")
                        if Capture.allowed {
                            Text("Allowed").font(.system(size: 12)).foregroundStyle(Palette.ok)
                        } else {
                            Button("Allow…") { Capture.requestAccess() }.buttonStyle(BowerButton())
                        }
                    }
                    r.menu("Previews look like", nil, \.previewLook, [(PreviewLook.pictureUnderColour, String(localized: "Picture under colour and icon")),
                                                                       (.colourAndIcon, String(localized: "Colour and app icon"))])
                    r.toggle("Use each app's colour", nil, \.appColours).level(.advanced, store)
                    r.slider("App colour", "Previews take this much colour from the app's icon instead of grey.", \.appColourAmount, 0...1, step: 0.05, format: pct).level(.advanced, store)
                    r.menu("Show where a dragged window lands", nil, \.previewStyle, [(PreviewStyle.tinted, String(localized: "Tinted")), (.picture, String(localized: "As a picture"))])
                        .level(.hidden, store)
                }
                GroupHeading(text: "Background")
                FormGroup {
                    r.toggle("Darken the background behind arranged windows", "On Dock mode displays.", \.dimBehind, first: true)
                    r.slider("Darkness", nil, \.dimOpacity, 0...0.8, step: 0.05, format: pct).level(.advanced, store)
                }
                GroupHeading(text: "Tabs")
                FormGroup {
                    r.menu("Style", nil, \.tabStyle, [(TabStyle.material, String(localized: "Material")), (.glass, String(localized: "Glass (the wallpaper, blurred)")),
                                                      (.solid, String(localized: "Solid"))], first: true)
                    r.toggle("Glass turns opaque when its window isn't active", nil, \.tabGlassOpaqueWhenInactive).level(.advanced, store)
                    r.toggle("Selected tab as a rounded chip", nil, \.tabSelectedChip)
                    r.slider("Chip margin", nil, \.tabChipMargin, 0...10, step: 1, format: pt).level(.hidden, store)
                    r.slider("Inset", nil, \.tabInset, 0...8, step: 1, format: pt).level(.advanced, store)
                    r.slider("Padding", nil, \.tabPadding, 2...16, step: 1, format: pt).level(.advanced, store)
                    r.slider("Tint", "Accent colour over the strip.", \.tabTint, 0...1, step: 0.05, format: pct).level(.advanced, store)
                    r.toggle("Close buttons", nil, \.tabCloseButtons)
                    r.toggle("On the right", nil, \.tabCloseOnRight).level(.advanced, store)
                    r.toggle("Red, yellow and green on each tab strip", nil, \.tabStripLights).level(.advanced, store)
                    r.toggle("Window buttons act on the whole group", "A group's red, yellow and green buttons; ⇧-click for just the tab, fn-click for macOS's own. Green on the tab shown takes it out of the group.", \.windowButtonsActOnGroup)
                    r.toggle("Tuck the strip away while its window moves", nil, \.tuckStrips).level(.advanced, store)
                }
                GroupHeading(text: "Menu bar")
                MenuControlsEditor(store: store, engine: engine)
            }
            .padding(.bottom, 8)
        }
    }
}

/// Menu bar controls, in order: drag to reorder, switch each on or off.
private struct MenuControlsEditor: View {
    @ObservedObject var store: Store
    let engine: Engine

    var body: some View {
        let r = PrefRows(store: store, engine: engine)
        let on = store.state.prefs.menuControls
        FormGroup {
            // Shown in the menu bar's order, so the arrows visibly move a row; the ones that are off follow.
            let rows = on + MenuControl.allCases.filter { !on.contains($0) }
            ForEach(Array(rows.enumerated()), id: \.element) { i, c in
                FormRow(first: i == 0) {
                    RowText(verbatim: c.title, sub: c == .layout ? String(localized: "Bower's own item. Right-clicking any of them opens Bower's menu.") : nil)
                    if let at = on.firstIndex(of: c), c != .layout {
                        Button { move(c, at - 1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.plain).disabled(at <= 1)
                            .accessibilityLabel("Move \(c.title) earlier")
                        Button { move(c, at + 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain).disabled(at >= on.count - 1)
                            .accessibilityLabel("Move \(c.title) later")
                    }
                    Toggle("", isOn: Binding(get: { on.contains(c) }, set: { v in
                        engine.setPrefs { p in if v { p.menuControls.append(c) } else { p.menuControls.removeAll { $0 == c } } }
                    }))
                    .toggleStyle(BowerToggle()).disabled(c == .layout).accessibilityLabel(c.title)
                }
            }
            r.slider("Frame", "How white the frame round Bower's menu bar buttons is.", \.menuBarFill, 0...0.5, step: 0.02, format: pct).level(.advanced, store)
        }
    }

    private func move(_ c: MenuControl, _ to: Int) {
        engine.setPrefs { p in
            guard let i = p.menuControls.firstIndex(of: c), p.menuControls.indices.contains(to), to >= 1 else { return }
            p.menuControls.swapAt(i, to)
        }
    }
}

// MARK: - General additions

struct GeneralMore: View {
    @ObservedObject var store: Store
    let engine: Engine
    var openReport: () -> Void = {}
    var openLessons: () -> Void = {}
    @State private var conflicts = Conflict.active
    @State private var confirmReset = false

    var body: some View {
        let r = PrefRows(store: store, engine: engine)
        IgnoredApps(store: store, engine: engine)
        MissingWindows(store: store, engine: engine)
        GroupHeading(text: "Desktops")
        FormGroup {
            r.menu("Arrange desktops as Bower first sees them", "Turn it on or off for the desktop you're on in Bower's menu › This Display.",
                   \.arrangeDesktops, [(ArrangeDesktops.all, String(localized: "All desktops")), (.firstOnly, String(localized: "First desktop only"))], first: true)
        }
        GroupHeading(text: "macOS features")
        FormGroup {
            if conflicts.isEmpty {
                FormRow(first: true) {
                    RowText(title: "No conflicts with macOS", sub: "None of macOS's own ways of moving windows is on, so nothing will fight Bower.")
                    if !store.state.prefs.turnedOff.isEmpty {
                        Button("Turn Back On") { Conflict.turnBackOn(engine); refresh() }.buttonStyle(BowerButton())
                    }
                }
            } else {
                FormRow(first: true) {
                    RowText(title: "These would fight Bower", sub: "While Bower arranges your windows, they move or hide windows behind its back. You can turn them back on any time.")
                    Button("Turn Them Off") { conflicts.forEach { $0.turnOff(engine) }; refresh() }.buttonStyle(BowerButton(primary: true))
                }
                ForEach(conflicts) { c in
                    FormRow { RowText(verbatim: c.title, sub: c.what) }
                }
            }
        }
        .onAppear(perform: refresh)
        GroupHeading(text: "Updates")
        FormGroup {
            r.toggle("Check for updates automatically", "Once a day, from GitHub. Off: Bower makes no network requests unless you set up an AI endpoint.", \.checkUpdates, first: true)
            r.toggle("Get beta versions", "Betas bring new features sooner, and may have more bugs. Turned off, you stay on the beta you have until the next release.", \.betaUpdates)
            r.toggle("Update reminders", "A dot on Bower's menu bar item when an update is waiting.", \.updateReminders)
        }
        GroupHeading(text: "Help")
        FormGroup {
            FormRow(first: true) {
                RowText(title: "Getting Started", sub: "The first moves, one at a time, from the beginning.")
                Button("Start", action: openLessons).buttonStyle(BowerButton())
            }
            FormRow {
                RowText(title: "Report a Problem…", sub: "Writes an email to us with your Mac's details and Bower's logs attached. You see all of it before it's sent.")
                Button("Report…", action: openReport).buttonStyle(BowerButton())
            }
            r.toggle("Show advanced settings", nil, \.showAdvanced)
            #if DEBUG
            FormRow {
                RowText(title: "Release defaults", sub: "Development build: your current settings become every build's defaults (Resources/Defaults.json).")
                Button("Save Current Settings as Defaults") { Prefs.saveAsReleaseDefaults(store.state.prefs) }.buttonStyle(BowerButton())
            }
            #endif
            FormRow {
                RowText(title: "Reset Dock, gestures and appearance", sub: "Back to how they came. Layouts, shortcuts and workspaces stay.")
                Button("Reset…") { confirmReset = true }
                .buttonStyle(BowerButton())
                .alert("Reset Dock, gestures and appearance?", isPresented: $confirmReset) {
                    Button("Reset", role: .destructive, action: reset)
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Your layouts, shortcuts and workspaces stay.") }
            }
        }
    }

    private func reset() {
        let keep = store.state.prefs
        engine.setPrefs { p in
            p = Prefs.releaseDefaults
            p.views = keep.views; p.closed = keep.closed; p.lessonsDone = keep.lessonsDone; p.lastWhatsNew = keep.lastWhatsNew
            p.turnedOff = keep.turnedOff; p.hotkeysTakenOver = keep.hotkeysTakenOver; p.desktopHidden = keep.desktopHidden
            p.desktopShown = keep.desktopShown; p.offSpaces = keep.offSpaces; p.onSpaces = keep.onSpaces; p.ignoredApps = keep.ignoredApps
        }
    }

    private func refresh() { conflicts = Conflict.active }
}

extension Prefs {
    /// Defaults a release ships with: Resources/Defaults.json when present, else the values in code.
    static var releaseDefaults: Prefs {
        guard let url = Bundle.main.url(forResource: "Defaults", withExtension: "json"), let d = try? Data(contentsOf: url),
              let p = try? JSONDecoder().decode(Prefs.self, from: d) else { return Prefs() }
        return p
    }

    #if DEBUG
    /// Development builds only: writes these settings into the source tree as the release's defaults.
    static func saveAsReleaseDefaults(_ p: Prefs, file: String = #filePath) {
        var clean = p
        clean.views = [:]; clean.closed = []; clean.lessonsDone = []; clean.lastWhatsNew = ""; clean.turnedOff = [:]
        clean.hotkeysTakenOver = []; clean.desktopHidden = []; clean.desktopShown = []; clean.offSpaces = []; clean.onSpaces = []
        clean.ignoredApps = []
        let url = URL(fileURLWithPath: file).deletingLastPathComponent().appendingPathComponent("Resources/Defaults.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(clean).write(to: url)
        Log.info("Saved release defaults to \(url.path)")
    }
    #endif
}
