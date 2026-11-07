import AppKit
import Combine
import SwiftUI

/// What on this Mac stops one of Bower's features, each with the switch that fixes it. Reads what the welcome
/// window, `Conflict` and the trackpad already detect; Settings › General shows it at the top.
enum SetupItem: Identifiable, Equatable {
    case accessibility, screenRecording, sharedSpaces, conflicts([Conflict]), swipes(String, threeFingerDrag: Bool), lookUpTap

    var id: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "screenRecording"
        case .sharedSpaces: "sharedSpaces"
        case .conflicts: "conflicts"
        case .swipes: "swipes"
        case .lookUpTap: "lookUpTap"
        }
    }

    /// Only what needs attention now, most important first.
    static func current(_ st: DeskState) -> [SetupItem] {
        var items: [SetupItem] = []
        if !AX.trusted { items.append(.accessibility) }
        if !Capture.allowed { items.append(.screenRecording) }
        // Bower keeps each display's desktops apart (modes, Use Bower on This Desktop); one set across displays mixes them.
        if NSScreen.screens.count > 1, !NSScreen.screensHaveSeparateSpaces { items.append(.sharedSpaces) }
        let c = Conflict.active
        if !c.isEmpty { items.append(.conflicts(c)) }
        if st.swipeLayouts {
            let ex = DockSwipe.explanation(fingers: st.prefs.swipeFingers, missionControl: st.prefs.replaceMissionControl)
            if ex.needsSettings {
                items.append(.swipes(ex.text, threeFingerDrag: st.prefs.swipeFingers == 3 && DockSwipe.system(fingers: 3).threeFingerDrag))
            }
        }
        if st.trackpadTapOn, TrackpadTap.shared.available, TrackpadTap.systemUsesThreeFingerTap { items.append(.lookUpTap) }
        return items
    }

    static func open(_ pane: String) {
        if let u = URL(string: "x-apple.systempreferences:" + pane) { NSWorkspace.shared.open(u) }
    }
}

struct MacSetupGroup: View {
    @ObservedObject var store: Store
    let engine: Engine
    @State private var items: [SetupItem] = []
    /// Permissions change in System Settings while this is open; look again every couple of seconds.
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        GroupHeading(text: "Mac setup")
        FormGroup {
            if items.isEmpty {
                FormRow(first: true) {
                    Glyph(d: "M3.5 8.5l3 3 6-7", size: 14, width: 2).foregroundStyle(Palette.ok).accessibilityHidden(true)
                    RowText(title: "Everything's set", sub: "Nothing on this Mac is stopping any of Bower's features.")
                }
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in row(item, first: i == 0) }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in refresh() }
        .onChange(of: store.state.prefs.turnedOff) { _, _ in refresh() }
    }

    private func refresh() {
        let now = SetupItem.current(store.state)
        if now != items { items = now }
    }

    @ViewBuilder private func row(_ item: SetupItem, first: Bool) -> some View {
        switch item {
        case .accessibility:
            FormRow(first: first) {
                mark(required: true)
                RowText(title: "Accessibility is off", sub: "Required. macOS needs it before Bower can move and resize other apps' windows.")
                Button("Open System Settings") { SetupItem.open("com.apple.preference.security?Privacy_Accessibility") }
                    .buttonStyle(BowerButton(primary: true))
            }
        case .screenRecording:
            FormRow(first: first) {
                mark(required: false)
                RowText(title: "Screen Recording is off",
                        sub: "Optional. With it, the overview and moving windows show what's in them. Without it, they show the app's colour and icon.")
                Button("Allow…") {
                    Capture.requestAccess()
                    SetupItem.open("com.apple.preference.security?Privacy_ScreenCapture")
                }
                .buttonStyle(BowerButton())
            }
        case .sharedSpaces:
            FormRow(first: first) {
                mark(required: false)
                RowText(title: "Displays share their desktops",
                        sub: "Bower keeps each display's desktops apart. Turn on \"Displays have separate Spaces\" in Desktop & Dock, then log out and back in.")
                Button("Open Desktop & Dock") { SetupItem.open("com.apple.Desktop-Settings.extension") }.buttonStyle(BowerButton())
            }
        case .conflicts(let list):
            FormRow(first: first) {
                mark(required: false)
                RowText(verbatim: String(localized: "macOS moves windows behind Bower's back"),
                        sub: list.map(\.title).formatted(.list(type: .and)) + ". "
                            + String(localized: "You can turn them back on below."))
                Button("Turn Them Off") {
                    list.forEach { $0.turnOff(engine) }
                    refresh()
                }
                .buttonStyle(BowerButton())
            }
        case .swipes(let text, let drag):
            FormRow(first: first) {
                mark(required: false)
                RowText(verbatim: String(localized: "Swiping between layouts"), sub: text)
                Button(drag ? "Open Accessibility Settings" : "Open Trackpad Settings") {
                    SetupItem.open(drag ? "com.apple.Accessibility-Settings.extension" : "com.apple.Trackpad-Settings.extension")
                }
                .buttonStyle(BowerButton())
            }
        case .lookUpTap:
            FormRow(first: first) {
                mark(required: false)
                RowText(title: "Three-finger tap also opens Look Up",
                        sub: "macOS and the Snap Wheel both answer the tap. Set Look Up to a force click in Trackpad settings.")
                Button("Open Trackpad Settings") { SetupItem.open("com.apple.Trackpad-Settings.extension") }.buttonStyle(BowerButton())
            }
        }
    }

    /// A filled dot for what Bower needs, an outline for what's optional.
    private func mark(required: Bool) -> some View {
        Circle()
            .strokeBorder(required ? Palette.danger : Palette.warn, lineWidth: 1.5)
            .background(Circle().fill(required ? Palette.danger : .clear))
            .frame(width: 10, height: 10)
            .accessibilityLabel(required ? Text("Required") : Text("Optional"))
    }
}
