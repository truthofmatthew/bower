import SwiftUI

/// A tiny desk that loops one action: the windows sit where `before` puts them, glide to `after`, hold, and go back.
/// Rects are in unit coordinates of the whole demo, top-left origin. Window 0 is the one acted on.
struct DemoScene {
    struct W {
        var r: CGRect
        var on = true
    }
    var before: [W]
    var after: [W]
    var twoDisplays = false
    /// After: the windows share one pane under a tab strip (Tabs mode).
    var tabs = false
}

private func w(_ x: CGFloat, _ y: CGFloat, _ wd: CGFloat, _ h: CGFloat, on: Bool = true) -> DemoScene.W {
    DemoScene.W(r: CGRect(x: x, y: y, width: wd, height: h), on: on)
}

/// Three loose windows, the usual starting point.
private let loose = [w(0.12, 0.1, 0.42, 0.5), w(0.46, 0.3, 0.42, 0.5), w(0.22, 0.45, 0.36, 0.45)]
/// Bento Box: the window used last takes the left column, the rest share a grid.
private let bento = [w(0, 0, 0.5, 1), w(0.5, 0, 0.5, 0.5), w(0.5, 0.5, 0.5, 0.5)]

extension WheelAction {
    var demo: DemoScene {
        switch self {
        case .maximize: DemoScene(before: [w(0.22, 0.2, 0.45, 0.5)], after: [w(0, 0, 1, 1)])
        case .thirds: DemoScene(before: [w(0.28, 0.2, 0.45, 0.55)], after: [w(0, 0, 1 / 3, 1)])
        case .mode, .retile: DemoScene(before: loose, after: bento)
        case .layouts:
            DemoScene(before: [w(0.05, 0.1, 0.5, 0.75), w(0.55, 0.2, 0.4, 0.6), w(0, 0, 0.6, 1, on: false), w(0.6, 0, 0.4, 1, on: false)],
                      after: [w(0.05, 0.1, 0.5, 0.75, on: false), w(0.55, 0.2, 0.4, 0.6, on: false), w(0, 0, 0.6, 1), w(0.6, 0, 0.4, 1)])
        case .send:
            DemoScene(before: [w(0.3, 0.2, 0.5, 0.6), w(0.05, 0.3, 0.3, 0.5)], after: [w(0.75, 0.2, 0.5, 0.6, on: false), w(0.05, 0.3, 0.3, 0.5)])
        case .recipe:
            DemoScene(before: loose, after: [w(0, 0, 2 / 3, 1), w(2 / 3, 0, 1 / 3, 0.5), w(2 / 3, 0.5, 1 / 3, 0.5)])
        case .settings: DemoScene(before: [w(0.3, 0.2, 0.4, 0.6, on: false)], after: [w(0.25, 0.15, 0.5, 0.7)])
        case .center: DemoScene(before: [w(0.04, 0.06, 0.45, 0.45)], after: [w(0.275, 0.275, 0.45, 0.45)])
        case .almostMaximize: DemoScene(before: [w(0.28, 0.25, 0.4, 0.45)], after: [w(0.05, 0.05, 0.9, 0.9)])
        case .nextDisplay: DemoScene(before: [w(0.06, 0.2, 0.32, 0.55)], after: [w(0.58, 0.2, 0.32, 0.55)], twoDisplays: true)
        case .restore: DemoScene(before: [w(0, 0, 1, 1)], after: [w(0.22, 0.2, 0.45, 0.5)])
        case .minimize: DemoScene(before: [w(0.25, 0.2, 0.5, 0.55)], after: [w(0.45, 0.92, 0.1, 0.06, on: false)])
        case .hideOthers:
            DemoScene(before: [w(0.3, 0.15, 0.45, 0.6), w(0.04, 0.05, 0.35, 0.5), w(0.55, 0.42, 0.4, 0.5)],
                      after: [w(0.3, 0.15, 0.45, 0.6), w(0.04, 0.05, 0.35, 0.5, on: false), w(0.55, 0.42, 0.4, 0.5, on: false)])
        case .split: DemoScene(before: [w(0.1, 0.15, 0.45, 0.5), w(0.42, 0.35, 0.45, 0.5)], after: [w(0, 0, 0.5, 1), w(0.5, 0, 0.5, 1)])
        case .fourCorners:
            DemoScene(before: loose + [w(0.5, 0.05, 0.38, 0.4)],
                      after: [w(0, 0, 0.5, 0.5), w(0.5, 0, 0.5, 0.5), w(0, 0.5, 0.5, 0.5), w(0.5, 0.5, 0.5, 0.5)])
        case .focusStack: DemoScene(before: loose, after: [w(0, 0, 2 / 3, 1), w(2 / 3, 0, 1 / 3, 0.5), w(2 / 3, 0.5, 1 / 3, 0.5)])
        }
    }

    var blurb: String {
        switch self {
        case .maximize: String(localized: "The window fills the screen.")
        case .thirds: String(localized: "Opens an arc of thirds: left, centre, right, or two thirds.")
        case .mode: String(localized: "Opens an arc to pick how this display arranges windows, such as Bento Box.")
        case .layouts: String(localized: "Opens an arc of your layouts. Pick one to swap every window on screen.")
        case .send: String(localized: "Opens an arc of layouts. The window moves there and leaves this one.")
        case .retile: String(localized: "Tiles every window on this display into a grid.")
        case .recipe: String(localized: "Runs an AI Recipe that arranges your apps the way you wrote it.")
        case .settings: String(localized: "Opens Bower Settings.")
        case .center: String(localized: "Moves the window to the middle of the screen, same size.")
        case .almostMaximize: String(localized: "The window fills the screen with a small margin around it.")
        case .nextDisplay: String(localized: "Moves the window to your next display, keeping its place.")
        case .restore: String(localized: "Puts the window back where it was before Bower last moved it.")
        case .minimize: String(localized: "Sends the window to the Dock.")
        case .hideOthers: String(localized: "Hides every other app, so only this one stays.")
        case .split: String(localized: "Your two front windows share the screen, half each.")
        case .fourCorners: String(localized: "Your four front windows take a corner each.")
        case .focusStack: String(localized: "The front window takes two thirds; the rest stack in the last third.")
        }
    }
}

extension WindowMode {
    var demo: DemoScene {
        switch self {
        case .native: DemoScene(before: [w(0.1, 0.12, 0.42, 0.5), w(0.5, 0.4, 0.42, 0.5)], after: [w(0.46, 0.34, 0.42, 0.5), w(0.5, 0.4, 0.42, 0.5)])
        case .bento:
            // A window opens and everything retiles; the new one takes the left column.
            DemoScene(before: [w(0.25, 0.25, 0.5, 0.5, on: false), w(0, 0, 0.5, 1), w(0.5, 0, 0.5, 1)],
                      after: [w(0, 0, 0.5, 1), w(0.5, 0, 0.5, 0.5), w(0.5, 0.5, 0.5, 0.5)])
        case .tabs: DemoScene(before: loose, after: Array(repeating: w(0, 0.14, 1, 0.86), count: 3), tabs: true)
        }
    }

    var blurb: String {
        switch self {
        case .native: String(localized: "Windows stay where you put them.")
        case .bento: String(localized: "Windows tile on their own. The one you used last gets the big column.")
        case .tabs: String(localized: "Windows share one pane, with a tab for each.")
        }
    }
}

struct DemoView: View {
    let scene: DemoScene
    /// What the loop restarts on: a new action, not a re-render.
    let key: String
    @State private var done = false

    var body: some View {
        GeometryReader { g in
            let size = g.size
            let wins = done ? scene.after : scene.before
            ZStack(alignment: .topLeading) {
                ForEach(Array(screens.enumerated()), id: \.offset) { _, s in
                    RoundedRectangle(cornerRadius: 4).fill(Palette.screen.opacity(0.55))
                        .frame(width: s.width * size.width, height: s.height * size.height)
                        .offset(x: s.minX * size.width, y: s.minY * size.height)
                }
                if scene.tabs {
                    HStack(spacing: 3) {
                        ForEach(0..<scene.after.count, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2).fill(i == 0 ? Palette.accent : Palette.label3).frame(height: 7)
                        }
                    }
                    .frame(width: size.width - 8).offset(x: 4, y: 3)
                    .opacity(done ? 1 : 0)
                }
                // Back to front, so window 0 (the one acted on) is drawn last, on top.
                ForEach(wins.indices.reversed(), id: \.self) { i in window(wins[i], active: i == 0, in: size) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
        .task(id: key) {
            done = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                withAnimation(Theme.reduceMotion ? nil : .timingCurve(0.77, 0, 0.175, 1, duration: 0.55)) { done = true }
                try? await Task.sleep(for: .milliseconds(1600))
                withAnimation(Theme.reduceMotion ? nil : .timingCurve(0.77, 0, 0.175, 1, duration: 0.45)) { done = false }
            }
        }
    }

    private var screens: [CGRect] {
        scene.twoDisplays ? [CGRect(x: 0, y: 0, width: 0.48, height: 1), CGRect(x: 0.52, y: 0, width: 0.48, height: 1)]
            : [CGRect(x: 0, y: 0, width: 1, height: 1)]
    }

    private func window(_ d: DemoScene.W, active: Bool, in size: CGSize) -> some View {
        // A 3 pt gutter so tiled windows read as separate.
        let r = CGRect(x: d.r.minX * size.width, y: d.r.minY * size.height, width: d.r.width * size.width, height: d.r.height * size.height)
            .insetBy(dx: 1.5, dy: 1.5)
        return RoundedRectangle(cornerRadius: 3)
            .fill(active ? Palette.accentFill : Palette.groupSolid)
            .overlay(alignment: .top) { (active ? Palette.accent : Palette.fill2).frame(height: 3) }
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(active ? Palette.accent : Palette.hair, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .frame(width: max(r.width, 0), height: max(r.height, 0))
            .scaleEffect(d.on ? 1 : 0.92)
            .opacity(d.on ? 1 : 0)
            .offset(x: r.minX, y: r.minY)
    }
}
