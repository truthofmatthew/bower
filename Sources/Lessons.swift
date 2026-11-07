import AppKit
import SwiftUI

/// Getting Started and What's New: one move at a time, on a small card in the corner. Each step waits until you
/// actually do it (Bower notices), then moves on. Help › Getting Started brings it back any time.
final class Lessons: ObservableObject {
    enum Course { case gettingStarted, keepLearning, whatsNew }

    struct Step: Identifiable {
        let id: String
        let title: String
        let text: String
    }

    private unowned let engine: Engine
    private var panel: NSPanel?
    @Published private(set) var course = Course.gettingStarted
    @Published private(set) var index = 0
    @Published private(set) var doneStep = false

    init(engine: Engine) { self.engine = engine }

    static let basics: [Step] = [
        Step(id: "switch", title: String(localized: "Switch layouts"), text: String(localized: "Hold ⌥ and press a number from 1 to 9. Each layout keeps its own windows.")),
        Step(id: "wheel", title: String(localized: "Open the Snap Wheel"), text: String(localized: "Press ⌃⌥Space, tap with three fingers, or click the middle button.")),
        Step(id: "send", title: String(localized: "Send a window"), text: String(localized: "Press ⇧⌥ and a number: the focused window moves to that layout.")),
        Step(id: "dock", title: String(localized: "Dock a window"), text: String(localized: "Set this display to Dock mode (Bower's menu › This Display), then drag a window by its title bar to the edge of another. Its neighbours make room.")),
        Step(id: "float", title: String(localized: "Float a window"), text: String(localized: "Click a docked window's green button. It floats on the Desktop; click it again to dock it.")),
        Step(id: "frame", title: String(localized: "Focus on one window"), text: String(localized: "Double-click a window's title bar. Double-click it again to go back.")),
        Step(id: "everything", title: String(localized: "Open the overview"), text: String(localized: "Press ⌃⌥O, or hold ⌥ and pinch in on the trackpad."))
    ]

    static let more: [Step] = [
        Step(id: "group", title: String(localized: "Make a tab group"), text: String(localized: "Drag a window onto the middle of another and pause a moment. Let go, and they share a strip of tabs.")),
        Step(id: "marquee", title: String(localized: "Expand to a rectangle"), text: String(localized: "Hold ⌘⇧ and drag a rectangle around a few windows. They expand to fill the screen.")),
        Step(id: "saveView", title: String(localized: "Save a view"), text: String(localized: "Press ⌃⌥⇧ and a number to save what you're looking at; ⌃⌥ and the number brings it back.")),
        Step(id: "back", title: String(localized: "Go back and forward"), text: String(localized: "Press ⌃⌥[ to go back to where you were, ⌃⌥] to go forward.")),
        Step(id: "swipe", title: String(localized: "Swipe between layouts"), text: String(localized: "Turn it on in Settings › Gestures, then swipe sideways with three fingers."))
    ]

    /// New in this version, newest first.
    static let whatsNew: [Step] = [
        Step(id: "new-keys", title: String(localized: "Move and size from the keyboard"), text: String(localized: "⌃⌥⇧ and an arrow swaps a window with its neighbour. ⌃⌥W and ⌃⌥⇧W step its width through ½, ⅔, 90% and full.")),
        Step(id: "new-ring", title: String(localized: "A ring on the window you're in"), text: String(localized: "Turn it on in Settings › Appearance, as a line or a soft glow.")),
        Step(id: "new-space", title: String(localized: "Room for your own bars"), text: String(localized: "Keep space free along any screen edge in Settings › Dock. Mac setup, in Settings › General, shows anything stopping a feature."))
    ]

    var steps: [Step] {
        switch course {
        case .gettingStarted: Self.basics
        case .keepLearning: Self.more
        case .whatsNew: Self.whatsNew
        }
    }

    var step: Step? { steps[safe: index] }

    func start(_ c: Course) {
        course = c
        index = c == .whatsNew ? 0 : steps.firstIndex { !engine.state.prefs.lessonsDone.contains($0.id) } ?? 0
        doneStep = false
        show()
    }

    /// Shows What's New once per version, after the first run.
    func offerWhatsNew() {
        let v = Updates.current
        guard engine.state.prefs.lastWhatsNew != v else { return }
        engine.setPrefs { $0.lastWhatsNew = v }
        start(.whatsNew)
    }

    /// Bower noticed a move; the step waiting for it is done.
    func did(_ id: String) {
        if !engine.state.prefs.lessonsDone.contains(id) { engine.setPrefs { $0.lessonsDone.insert(id) } }
        guard panel != nil, step?.id == id else { return }
        doneStep = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.next() }
    }

    func next() {
        doneStep = false
        if index + 1 < steps.count { index += 1 } else { index = steps.count }  // past the end: the "that's it" card
    }

    func keepLearning() { start(.keepLearning) }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 170), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: LessonCard(lessons: self))
            panel = p
        }
        if let s = NSScreen.main {
            let v = s.visibleFrame
            panel?.setFrameOrigin(NSPoint(x: v.maxX - 360, y: v.minY + 20))
        }
        panel?.orderFrontRegardless()
    }
}

private struct LessonCard: View {
    @ObservedObject var lessons: Lessons

    private var heading: String {
        let n = min(lessons.index + 1, lessons.steps.count), m = lessons.steps.count
        switch lessons.course {
        case .gettingStarted: return String(localized: "Getting started · \(n) of \(m)")
        case .keepLearning: return String(localized: "Keep learning · \(n) of \(m)")
        case .whatsNew: return String(localized: "New in Bower · \(n) of \(m)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let s = lessons.step {
                Text(heading).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.label2)
                HStack(spacing: 6) {
                    if lessons.doneStep { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent) }
                    Text(s.title).font(.system(size: 14, weight: .semibold))
                }
                Text(s.text).font(.system(size: 12)).foregroundStyle(Palette.label).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    Button(lessons.course == .whatsNew ? String(localized: "Done") : String(localized: "Skip all")) { lessons.close() }
                        .buttonStyle(BowerButton())
                    Spacer()
                    Button(lessons.course == .whatsNew ? String(localized: "Next") : String(localized: "Skip")) { lessons.next() }
                        .buttonStyle(BowerButton(primary: lessons.course == .whatsNew))
                }
            } else {
                Text(lessons.course == .gettingStarted ? String(localized: "That's the basics") : String(localized: "All done"))
                    .font(.system(size: 14, weight: .semibold))
                Text(lessons.course == .gettingStarted
                     ? String(localized: "Keep going with tab groups, expanding to a rectangle and more, the same way. Or stop here: Bower's menu › Help brings this back.")
                     : String(localized: "Shortcuts, Settings and commands by link are in the guide."))
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    if lessons.course == .gettingStarted {
                        Button(String(localized: "Done")) { lessons.close() }.buttonStyle(BowerButton())
                        Button(String(localized: "Keep Learning")) { lessons.keepLearning() }.buttonStyle(BowerButton(primary: true))
                    } else {
                        Button(String(localized: "Done")) { lessons.close() }.buttonStyle(BowerButton(primary: true))
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340, height: 170, alignment: .topLeading)
        .background(Palette.window, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.hair))
        .animation(Theme.reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.2), value: lessons.index)
    }
}
