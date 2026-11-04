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
        engine.setPrefs { $0.showAdvanced = true }
        for scheme in [ColorScheme.light, .dark] {
            for t in SettingsView.Tab.allCases {
                // A real hosting view in a window, since ImageRenderer leaves scroll views empty.
                let host = NSHostingView(rootView: SettingsView(store: store, engine: engine, tab: t).environment(\.colorScheme, scheme))
                let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 560), styleMask: [.borderless], backing: .buffered, defer: false)
                win.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                win.contentView = host
                win.orderBack(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                win.orderOut(nil)
                guard let png = rep.representation(using: .png, properties: [:]) else { continue }
                try png.write(to: URL(fileURLWithPath: out).appendingPathComponent("\(t.rawValue)-\(scheme).png"))
            }
        }
    }
}
