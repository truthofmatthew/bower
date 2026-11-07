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
        // Settings added later decode from a file that predates them, and a bad value keeps its default.
        XCTAssertFalse(p.focusRing)
        XCTAssertEqual(p.focusRingStyle, .outline)
        XCTAssertEqual(p.focusRingColour, .accent)
        XCTAssertEqual(p.focusRingWidth, 3)
        XCTAssertEqual(p.appearance, .automatic)
        XCTAssertEqual(p.reserved, ReservedEdges())
        let newer = #"{"focusRing": true, "focusRingColour": "teal", "appearance": "dark", "reserveLeft": 120}"#
        let q = try JSONDecoder().decode(Prefs.self, from: Data(newer.utf8))
        XCTAssertTrue(q.focusRing)
        XCTAssertEqual(q.focusRingColour, .accent)
        XCTAssertEqual(q.appearance, .dark)
        XCTAssertEqual(q.reserved, ReservedEdges(left: 120))
    }

    /// Space kept free comes off the right edges (AX: top is minY), and never leaves too little to arrange into.
    func testUsableArea() {
        let v = CGRect(x: 0, y: 25, width: 1440, height: 875)
        XCTAssertEqual(UsableArea.inset(v, by: ReservedEdges()), v)
        XCTAssertEqual(UsableArea.inset(v, by: ReservedEdges(top: 40, bottom: 10, left: 100, right: 0)),
                       CGRect(x: 100, y: 65, width: 1340, height: 825))
        let squeezed = UsableArea.inset(v, by: ReservedEdges(top: 0, bottom: 0, left: 5000, right: 5000))
        XCTAssertEqual(squeezed.width, UsableArea.minimum.width, accuracy: 1)
        XCTAssertEqual(squeezed.midX, v.midX, accuracy: 1)
        XCTAssertEqual(UsableArea.inset(v, by: ReservedEdges(top: -50)), v)
    }

    /// Extension popups float; anything with title-bar buttons, or bigger than a popup, is still arranged.
    func testPopupsFloat() {
        XCTAssertTrue(AX.looksLikePopup(size: CGSize(width: 380, height: 600), hasButtons: false))
        XCTAssertFalse(AX.looksLikePopup(size: CGSize(width: 380, height: 600), hasButtons: true))
        XCTAssertFalse(AX.looksLikePopup(size: CGSize(width: 240, height: 160), hasButtons: true))  // parked small
        XCTAssertFalse(AX.looksLikePopup(size: CGSize(width: 1200, height: 800), hasButtons: false))  // a frameless app
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
