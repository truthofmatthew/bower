import XCTest
@testable import Bower

final class ParityTests: XCTestCase {
    func testCommandLinks() {
        XCTAssertEqual(Command(url: URL(string: "bower://layout/3")!), .layout(2))
        XCTAssertEqual(Command(url: URL(string: "bower://snap/leftHalf")!), .snap(.leftHalf))
        XCTAssertEqual(Command(url: URL(string: "bower://mode/dock")!), .mode(.dock))
        XCTAssertEqual(Command(url: URL(string: "bower://workspace/My%20week")!), .workspace("My week"))
        XCTAssertEqual(Command(url: URL(string: "bower://save-view/9")!), .saveView(9))
        XCTAssertNil(Command(url: URL(string: "bower://layout/0")!))
        XCTAssertNil(Command(url: URL(string: "bower://nonsense")!))
        XCTAssertNil(Command(url: URL(string: "https://layout/3")!))
    }

    /// Icon.path reads only M L H V Z; anything else would draw only part of the icon.
    func testSettingsIconsUseLinesOnly() {
        // An arc, a stray number after Z, a cut-off pair: drawn as far as possible, never a crash.
        for d in ["M2 2A5 5 0 1 1 8 8", "M1 1L4 4Z 3", "M1 1L4", ""] { _ = Icon.path(d) }
        for t in SettingsView.Tab.allCases {
            XCTAssertNil(t.icon.range(of: "[^MmLlHhVvZz0-9 .,-]", options: .regularExpression), t.rawValue)
        }
    }

    func testVersionCompare() {
        XCTAssertTrue(Updates.newer("v1.10", than: "1.9"))
        XCTAssertTrue(Updates.newer("1.0.1", than: "1.0"))
        XCTAssertFalse(Updates.newer("1.0", than: "1.0.0"))
        XCTAssertFalse(Updates.newer("0.9", than: "1.0"))
    }

    /// A state.json from before the Dock features keeps everything and gets the new defaults.
    func testStateWithoutPrefsLoads() throws {
        let old = #"{"layouts":[{"name":"Work","modes":{"A":"bento"}}],"current":0}"#
        let st = try JSONDecoder().decode(DeskState.self, from: Data(old.utf8))
        XCTAssertEqual(st.layouts.first?.modes["A"], .bento)
        XCTAssertEqual(st.prefs.swipeFingers, 3)
        XCTAssertTrue(st.docks.isEmpty)
    }

    /// Unknown or partial prefs keep what they can.
    func testPartialPrefs() throws {
        let json = #"{"gap": 12, "tabStyle": "glass", "returnWindows": "nonsense"}"#
        let p = try JSONDecoder().decode(Prefs.self, from: Data(json.utf8))
        XCTAssertEqual(p.gap, 12)
        XCTAssertEqual(p.tabStyle, .glass)
        XCTAssertEqual(p.returnWindows, .afterQuit)
    }

    func testRedactedHidesTitles() {
        var st = DeskState()
        st.orphans = [WindowRecord(bundleID: "a", title: "Secret plan.pages", layout: 0, frame: .zero)]
        XCTAssertFalse(Diagnostics.redacted(st).orphans[0].title.contains("Secret"))
    }

    func testBrowserProfileRoutes() {
        XCTAssertEqual(profileName(of: "Octabiz - Microsoft Edge - Product", app: "Microsoft Edge"), "Product")
        XCTAssertNil(profileName(of: "New Tab - Microsoft Edge", app: "Microsoft Edge"))
        XCTAssertEqual(routeKey("com.microsoft.edgemac", profile: "Product"), "com.microsoft.edgemac#Product")
        XCTAssertEqual(routeKey("net.whatsapp.WhatsApp"), "net.whatsapp.WhatsApp")
    }
}
