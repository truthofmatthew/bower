import XCTest
@testable import Bower

final class StateTests: XCTestCase {
    /// A state.json from before Workspaces existed must keep its layouts, not reset to defaults.
    func testOldStateFileStillLoads() throws {
        let old = #"{"layouts":[{"name":"Work","modes":{}},{"name":"Play","modes":{}}],"current":1,"assignment":{"42":1},"#
            + #""saved":{},"routes":{},"pinned":[],"statusStyle":"numberOnly","hideOtherLayouts":false}"#
        let st = try JSONDecoder().decode(DeskState.self, from: Data(old.utf8))
        XCTAssertEqual(st.layouts.map(\.name), ["Work", "Play"])
        XCTAssertEqual(st.current, 1)
        XCTAssertEqual(st.assignment["42"], 1)
        XCTAssertEqual(st.statusStyle, .numberOnly)
        XCTAssertFalse(st.hideOtherLayouts)
        XCTAssertTrue(st.workspaces.isEmpty)
        XCTAssertTrue(st.shelf.isEmpty)
    }

    func testStateRoundTrips() throws {
        var st = DeskState()
        st.workspaces = [Workspace(name: "Docked", saved: Date(timeIntervalSince1970: 0), layouts: st.layouts, current: 2,
                                   displays: [DisplayRecord(uuid: "A", name: "Studio", size: CGSize(width: 2560, height: 1440))],
                                   windows: [WindowRecord(bundleID: "com.x", title: "T", layout: 2, frame: .zero, key: "7")],
                                   pinned: ["A"], routes: ["com.x": 2])]
        st.currentWorkspace = "Docked"
        let back = try JSONDecoder().decode(DeskState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(back.workspaces.first?.windows.first?.layout, 2)
        XCTAssertEqual(back.currentWorkspace, "Docked")
    }
}
