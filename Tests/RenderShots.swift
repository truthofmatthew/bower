import SwiftUI
import XCTest
@testable import Bower

/// Renders each Settings tab and the lesson card to PNGs for a look without running the app.
/// Off unless BOWER_SHOTS names a folder: `BOWER_SHOTS=/path xcodebuild test …`.
final class RenderShots: XCTestCase {
    @MainActor
    func testRenderSettingsTabs() throws {
        guard let out = ProcessInfo.processInfo.environment["BOWER_SHOTS"] else { throw XCTSkip("BOWER_SHOTS not set") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = Store(directory: dir)
        let engine = Engine(store: store)
        engine.setPrefs { $0.showAdvanced = true; $0.focusRing = true }
        try render(store: store, engine: engine, tabs: SettingsView.Tab.allCases, to: out, suffix: "")
        // The AI tab as it looks with a hosted provider chosen.
        engine.setAI(AISettings(preset: .claude, endpoint: AIPreset.claude.endpoint, model: "claude-sonnet-4-5"))
        try render(store: store, engine: engine, tabs: [.ai], to: out, suffix: "-claude")
        // The welcome window, as a new user first sees it.
        // Before Accessibility is allowed: the tallest the window gets.
        let model = FirstRunModel()
        model.trusted = false
        let host = NSHostingView(rootView: FirstRunView(model: model, close: {}).environment(\.colorScheme, .dark))
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 680), styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        win.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out).appendingPathComponent("first-run-dark.png"))
        }
        win.orderOut(nil)

        // A recipe with its preview, as the AI returns it.
        engine.setAI(AISettings(preset: .ollama, endpoint: AIPreset.ollama.endpoint, model: "llama3.2"))
        let recipe = RecipeModel(name: nil, engine: engine)
        recipe.name = "Morning desk"
        recipe.text = "## Projects & Layouts\n- Dev — @Safari on @main monitor\n- Comms — @Messages on @main monitor\n\n## Window modes\n- @main monitor uses Bento Box\n"
        recipe.phase = .ready(RecipePlan(
            layouts: [.init(number: 3, name: "Dev", windows: [.init(app: "Safari", display: "main monitor")]),
                      .init(number: 4, name: "Comms", windows: [.init(app: "Messages", display: "main monitor")])],
            modes: [.init(display: "main monitor", mode: "bento")]))
        try snapshot(RecipeEditorView(model: recipe) {}, size: CGSize(width: 1020, height: 604), to: out, name: "recipe-dark.png")
    }

    @MainActor
    private func snapshot(_ view: some View, size: CGSize, to out: String, name: String) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        let win = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        win.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
        win.orderOut(nil)
    }

    @MainActor
    private func render(store: Store, engine: Engine, tabs: [SettingsView.Tab], to out: String, suffix: String) throws {
        for scheme in [ColorScheme.light, .dark] {
            for t in tabs {
                // A real hosting view in a window, since ImageRenderer leaves scroll views empty.
                let host = NSHostingView(rootView: SettingsView(store: store, engine: engine, tab: t).environment(\.colorScheme, scheme))
                let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 560), styleMask: [.borderless], backing: .buffered, defer: false)
                win.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                win.contentView = host
                win.orderBack(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                // One picture per screenful, scrolling down, so nothing below the fold goes unseen.
                let scroll = Self.scrollView(in: host)
                let pageHeight = max(1, (scroll?.contentView.bounds.height ?? 1) - 40)
                let total = scroll?.documentView?.frame.height ?? 0
                var page = 0, y = 0.0
                repeat {
                    if let scroll {
                        scroll.contentView.scroll(to: CGPoint(x: 0, y: min(y, max(0, total - scroll.contentView.bounds.height))))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                    }
                    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { break }
                    host.cacheDisplay(in: host.bounds, to: rep)
                    guard let png = rep.representation(using: .png, properties: [:]) else { break }
                    try png.write(to: URL(fileURLWithPath: out).appendingPathComponent("\(t.rawValue)\(suffix)-\(scheme)\(page == 0 ? "" : "-\(page + 1)").png"))
                    page += 1
                    y += pageHeight
                } while scroll != nil && y < total - 20 && page < 8
                win.orderOut(nil)
            }
        }
    }

    private static func scrollView(in v: NSView) -> NSScrollView? {
        if let s = v as? NSScrollView, (s.documentView?.frame.height ?? 0) > s.contentView.bounds.height + 1 { return s }
        for sub in v.subviews { if let s = scrollView(in: sub) { return s } }
        return nil
    }
}
