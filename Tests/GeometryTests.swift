import Carbon.HIToolbox
import XCTest
@testable import Bower

final class GeometryTests: XCTestCase {
    let v = CGRect(x: 0, y: 25, width: 1200, height: 750)

    func testHalvesAndQuartersTileTheScreen() {
        XCTAssertEqual(SnapAction.leftHalf.frame(in: v), CGRect(x: 0, y: 25, width: 600, height: 750))
        XCTAssertEqual(SnapAction.rightHalf.frame(in: v), CGRect(x: 600, y: 25, width: 600, height: 750))
        XCTAssertEqual(SnapAction.bottomRight.frame(in: v), CGRect(x: 600, y: 400, width: 600, height: 375))
        XCTAssertEqual(SnapAction.maximize.frame(in: v), v)
    }

    func testThirdsCoverOddWidthsWithoutGaps() {
        let odd = CGRect(x: 0, y: 0, width: 1001, height: 500)
        let first = SnapAction.firstThird.frame(in: odd), last = SnapAction.lastThird.frame(in: odd)
        XCTAssertEqual(first.width, 333)
        XCTAssertEqual(last.maxX, 1001)
        XCTAssertEqual(SnapAction.lastTwoThirds.frame(in: odd).minX, 333)
    }

    func testBentoMatchesDesignLayouts() {
        let r = CGRect(x: 0, y: 0, width: 606, height: 306)  // 600 × 300 inside the 6 pt margin… minus gaps
        XCTAssertEqual(Bento.tiles(count: 1, in: r), [CGRect(x: 6, y: 6, width: 594, height: 294)])
        // 5 windows: main column + 2 × 2 grid, three equal columns.
        let five = Bento.tiles(count: 5, in: r)
        XCTAssertEqual(five.count, 5)
        XCTAssertEqual(five[0].height, 294)
        XCTAssertEqual(five[1].width, five[0].width, accuracy: 0.001)
        XCTAssertEqual(five[4].maxX, 600, accuracy: 0.001)
        XCTAssertEqual(five[4].maxY, 300, accuracy: 0.001)
        // An odd remainder stretches the last tile to the right edge.
        XCTAssertEqual(Bento.tiles(count: 4, in: r)[3].maxX, 600, accuracy: 0.001)
    }

    func testWheelHitTesting() {
        let c = WheelGeometry.center
        XCTAssertEqual(WheelGeometry.hit(c, arc: nil), .cancel)
        XCTAssertEqual(WheelGeometry.hit(CGPoint(x: c.x, y: c.y - 60), arc: nil), .inner(0))  // top
        XCTAssertEqual(WheelGeometry.hit(CGPoint(x: c.x + 60, y: c.y), arc: nil), .inner(2))  // right
        XCTAssertEqual(WheelGeometry.hit(CGPoint(x: c.x - 60, y: c.y), arc: nil), .inner(6))  // left
        XCTAssertEqual(WheelGeometry.hit(CGPoint(x: c.x, y: c.y + 120), arc: nil), .outer(4))  // bottom
        XCTAssertEqual(WheelGeometry.hit(CGPoint(x: c.x + 200, y: c.y), arc: nil), WheelGeometry.Hit.none)

        // Layouts (slot 3, centred at 45°): item 4 sits on the parent's angle.
        let arc = WheelGeometry.Arc.layouts(3)
        XCTAssertEqual(WheelGeometry.hit(WheelGeometry.point(175, WheelGeometry.angle(3)), arc: arc), .arc(4))
        XCTAssertEqual(WheelGeometry.hit(WheelGeometry.point(175, arc.angle(0)), arc: arc), .arc(0))
    }

    func testIconParserReadsRelativeCommands() {
        let box = Icon.path(Icon.layouts).boundingBox
        XCTAssertEqual(box, CGRect(x: 2, y: 2, width: 12, height: 12))
        XCTAssertEqual(Icon.path(Icon.send).boundingBox.maxX, 13.5)
    }
}

final class TabsAndShortcutTests: XCTestCase {
    /// Two groups split the visible frame with a 1 pt divider; each pane sits under a 30 pt strip.
    func testTabRectsSplitWithDivider() throws {
        let s = try XCTUnwrap(NSScreen.main)
        let tabs = TabsController(engine: Engine(store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))))
        let v = s.axVisibleFrame
        let one = tabs.rects(s, groups: 1)
        XCTAssertEqual(one[0].strip.height, 30)
        XCTAssertEqual(one[0].pane.minY, v.minY + 30)
        let two = tabs.rects(s, groups: 2)
        XCTAssertEqual(two[1].pane.minX - two[0].pane.maxX, 1)
        XCTAssertEqual(two[1].pane.maxX, v.maxX)
    }

    func testGroupedRowsExpandToEveryKey() {
        var st = DeskState()
        XCTAssertEqual(st.bindings(.quarters).count, 4)
        XCTAssertEqual(st.bindings(.switchLayout).count, 9)
        XCTAssertEqual(st.bindings(.maximize), [ShortcutID.maximize.defaultCombo])
        st.clearedShortcuts.insert(ShortcutID.maximize.rawValue)
        XCTAssertTrue(st.bindings(.maximize).isEmpty)
        st.isoKeyboard = true
        XCTAssertEqual(st.bindings(.thirds)[1].key, Int(kVK_ANSI_Grave))
    }

    /// The defaults must not collide with each other.
    func testDefaultShortcutsAreUnique() {
        let st = DeskState()
        let all = ShortcutID.allCases.flatMap { st.bindings($0) }
        XCTAssertEqual(all.count, Set(all).count)
    }

    func testHiddenWheelSlotsRoundTrip() throws {
        var st = DeskState()
        st.wheelSlots[6] = nil
        st.wheelSlots[5] = .center
        let back = try JSONDecoder().decode(DeskState.self, from: JSONEncoder().encode(st))
        XCTAssertNil(back.wheelSlots[6])
        XCTAssertEqual(back.wheelSlots[5], .center)
    }

    /// A window that can't fit its Bento tile gets the room it needs from the others; the shape stays.
    func testBentoMakesRoomForMinimums() {
        let r = CGRect(x: 0, y: 0, width: 1200, height: 800)
        XCTAssertEqual(Bento.tiles(count: 3, in: r, mins: [nil, nil, nil]), Bento.tiles(count: 3, in: r))
        let t = Bento.tiles(count: 3, in: r, mins: [CGSize(width: 700, height: 0), nil, CGSize(width: 400, height: 0)])
        XCTAssertGreaterThanOrEqual(t[0].width, 700)
        XCTAssertGreaterThanOrEqual(t[2].width, 400)
        XCTAssertLessThanOrEqual(t[0].maxX, t[1].minX)
        XCTAssertEqual(t[1].minX, t[2].minX, accuracy: 1)  // still a right column, one above the other
        XCTAssertLessThanOrEqual(t[1].maxY, t[2].minY)
        let five = Bento.tiles(count: 5, in: r, mins: [nil, CGSize(width: 500, height: 0), nil, nil, nil])
        XCTAssertGreaterThanOrEqual(five[1].width, 500)
        for (i, a) in five.enumerated() { for b in five[(i + 1)...] { XCTAssertEqual(a.intersection(b).area, 0, accuracy: 0.5) } }
    }
}
