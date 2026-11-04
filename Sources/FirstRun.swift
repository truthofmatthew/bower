import SwiftUI

/// What the welcome window watches. AppDelegate feeds it.
final class FirstRunModel: ObservableObject {
    @Published var trusted = AX.trusted
    @Published var pressed: Set<Int> = []
    @Published var lastSwitch: String?
    @Published var wheelOpened = false

    var triedKeys: Bool { pressed.contains(0) && pressed.contains(1) }
    var finished: Bool { trusted && triedKeys && wheelOpened }
}

/// FirstRun.dc.html: three steps, each unlocked by the one before, and two optional ones. Continue needs only Accessibility.
struct FirstRunView: View {
    @ObservedObject var model: FirstRunModel
    /// Continue: closes and starts the Getting Started lessons.
    var close: () -> Void
    /// Skip Setup: closes without the lessons.
    var skip: () -> Void = {}
    /// Turns off the macOS features that would fight Bower (edge tiling, click wallpaper, Stage Manager).
    var turnOffConflicts: () -> Void = {}
    @State private var conflicts = Conflict.active
    @State private var screenAllowed = Capture.allowed

    /// optional: a step that can be done any time, drawn at full strength so its button doesn't look disabled.
    private enum Status { case active, done, todo, optional }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                BowerIcon(size: 56)
                Text("Welcome to Bower").font(.system(size: 20, weight: .bold))
                Text("Name a layout for each project and switch the whole desk with ⌥1–9.")
                    .font(.system(size: 12)).foregroundStyle(Palette.label2)
            }
            .padding(.top, 22)
            .padding(.bottom, 12)

            VStack(spacing: 4) {
                if model.trusted {
                    step(.done, "✓", "Accessibility granted", "You can revoke it any time in System Settings.")
                } else {
                    step(.active, "1", "Grant Accessibility access",
                         "macOS requires it to move and resize other apps’ windows. Turn on Bower in Privacy & Security › Accessibility.") {
                        HStack(spacing: 12) {
                            Button("Open System Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }
                            .buttonStyle(BowerButton(primary: true))
                            HStack(spacing: 6) {
                                Spinner()
                                Text("Waiting for permission…")
                            }
                            .font(.system(size: 12)).foregroundStyle(Palette.label2)
                            .accessibilityElement(children: .combine)
                        }
                        .padding(.top, 6)
                    }
                }
                step(!model.trusted ? .todo : model.triedKeys ? .done : .active, model.triedKeys ? "✓" : "2", "Try ⌥1 and ⌥2",
                     "Switch between two starter layouts. No animation: the desk just changes.") {
                    if model.trusted && !model.triedKeys {
                        HStack(spacing: 6) {
                            // Each pair reads ⌥ 1 even in right-to-left languages; the sentence around it may mirror.
                            HStack(spacing: 6) { Keycap("⌥", hit: model.pressed.contains(0)); Keycap("1", hit: model.pressed.contains(0)) }
                                .environment(\.layoutDirection, .leftToRight)
                            Text("then").font(.system(size: 12)).foregroundStyle(Palette.label2).padding(.horizontal, 6)
                            HStack(spacing: 6) { Keycap("⌥", hit: model.pressed.contains(1)); Keycap("2", hit: model.pressed.contains(1)) }
                                .environment(\.layoutDirection, .leftToRight)
                            if let s = model.lastSwitch {
                                Text("✓ Switched to \(s)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ok).padding(.leading, 10)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                step(!model.triedKeys ? .todo : model.wheelOpened ? .done : .active, model.wheelOpened ? "✓" : "3",
                     "Open the Snap Wheel", "Middle-click anywhere, or press ⌃⌥Space.")
                step(screenAllowed ? .done : .optional, screenAllowed ? "✓" : "4", "Optional: see your windows as they are",
                     "Lets the overview show what's in your windows. Still pictures only, never recorded or kept.") {
                    if !screenAllowed {
                        Button("Allow…") { Capture.requestAccess(); screenAllowed = Capture.allowed }.buttonStyle(BowerButton()).padding(.top, 6)
                    }
                }
                step(conflicts.isEmpty ? .done : .optional, conflicts.isEmpty ? "✓" : "5", "Turn off what gets in the way",
                     conflicts.isEmpty ? "None of macOS's own ways of moving windows is on, so nothing will fight Bower."
                         : "These macOS features move windows behind Bower's back. You can turn them back on in Settings › General.") {
                    if !conflicts.isEmpty {
                        HStack(spacing: 10) {
                            Button("Turn Them Off") { turnOffConflicts(); conflicts = Conflict.active }.buttonStyle(BowerButton())
                            Text(verbatim: conflicts.map(\.title).formatted(.list(type: .and)))
                                .font(.system(size: 12)).foregroundStyle(Palette.label2).lineLimit(2)
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity, alignment: .top)

            HStack {
                Button("Skip Setup", action: skip).buttonStyle(.plain).foregroundStyle(Palette.label2).padding(.horizontal, 14)
                Spacer()
                Button("Continue", action: close).buttonStyle(BowerButton(primary: true)).disabled(!model.trusted)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Palette.hair.frame(height: 1) }
        }
        .font(.system(size: 13))
        .foregroundStyle(Palette.label)
        .frame(width: 640, height: 680)
        .background(Palette.window)
    }

    private func step(_ s: Status, _ ind: String, _ title: LocalizedStringKey, _ desc: LocalizedStringKey) -> some View {
        step(s, ind, title, desc) { EmptyView() }
    }

    private func step<Extra: View>(_ s: Status, _ ind: String, _ title: LocalizedStringKey, _ desc: LocalizedStringKey, @ViewBuilder extra: () -> Extra) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(verbatim: ind)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 26, height: 26)
                .foregroundStyle(s == .active ? Palette.onAccent : s == .done ? Palette.ok : Palette.label)
                .background(Circle().fill(s == .active ? Palette.accent : s == .done ? .clear : Palette.fill2))
                .overlay(Circle().strokeBorder(s == .done ? Palette.ok : .clear, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(desc).font(.system(size: 12)).lineSpacing(3).foregroundStyle(Palette.label2).fixedSize(horizontal: false, vertical: true)
                extra()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background {
            if s == .active {
                RoundedRectangle(cornerRadius: 10).fill(Palette.group)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.hair, lineWidth: 0.5))
                    .overlay(RoundedRectangle(cornerRadius: 10).inset(by: -2).strokeBorder(Palette.accentFill, lineWidth: 2))
            }
        }
        .opacity(s == .todo ? 0.55 : 1)
    }
}

/// `.kc`: 26 pt keycap; `.hit` fills it with the accent.
private struct Keycap: View {
    let key: String
    let hit: Bool
    init(_ key: String, hit: Bool) { self.key = key; self.hit = hit }
    var body: some View {
        Text(key)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(hit ? Palette.onAccent : Palette.label)
            .padding(.horizontal, 6)
            .frame(minWidth: 26, minHeight: 26)
            .background(hit ? Palette.accent : Palette.control, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.hair, lineWidth: 0.5))
    }
}
