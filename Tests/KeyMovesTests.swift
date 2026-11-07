import Carbon.HIToolbox
import XCTest
@testable import Bower

final class KeyMovesTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)

    // MARK: Swapping in the tree

    func testSwapKeepsEveryTileSize() {
        var t = DockNode.split(.h, [.window("a"), .split(.v, [.window("b"), .window("c")], weights: [0.7, 0.3])], weights: [0.25, 0.75])
        let before = t.solve(in: screen, gap: 10).frames
        t.swap("a", "c")
        let after = t.solve(in: screen, gap: 10).frames
        XCTAssertEqual(after["c"], before["a"])
        XCTAssertEqual(after["a"], before["c"])
        XCTAssertEqual(after["b"], before["b"])
        XCTAssertEqual(t.weights, [0.25, 0.75])
    }

    func testSwapWithATabTakesItsPlaceInTheGroup() {
        var t = DockNode.split(.h, [.window("a"), DockNode(kind: .tabs, children: [.window("b"), .window("c")], selected: 1)])
        t.swap("a", "c")
        XCTAssertEqual(t.children[0].key, "c")
        XCTAssertEqual(t.children[1].keys, ["b", "a"])
        XCTAssertEqual(t.children[1].selected, 1)
    }

    func testMoveTabAlongItsGroup() {
        var t = DockNode.split(.h, [.window("a"), DockNode(kind: .tabs, children: [.window("b"), .window("c"), .window("d")], selected: 1)])
        XCTAssertTrue(t.moveTab("c", by: -1))
        XCTAssertEqual(t.children[1].keys, ["c", "b", "d"])
        XCTAssertEqual(t.children[1].selected, 0)
        XCTAssertFalse(t.moveTab("c", by: -1))  // already first
        XCTAssertFalse(t.moveTab("a", by: 1))  // not a tab
    }

    // MARK: Width

    func testWidthSteps() {
        XCTAssertEqual(WidthCycle.next(from: 0.3, wider: true), 0.5)
        XCTAssertEqual(WidthCycle.next(from: 0.5, wider: true)!, 2.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(WidthCycle.next(from: 0.667, wider: true), 0.9)
        XCTAssertEqual(WidthCycle.next(from: 0.9, wider: true), 1)
        XCTAssertNil(WidthCycle.next(from: 1, wider: true))
        XCTAssertEqual(WidthCycle.next(from: 1, wider: false), 0.9)
        XCTAssertEqual(WidthCycle.next(from: 0.8, wider: false)!, 2.0 / 3, accuracy: 0.0001)
        XCTAssertNil(WidthCycle.next(from: 0.5, wider: false))
        XCTAssertNil(WidthCycle.next(from: 0.3, wider: false))
    }

    func testWidthFrameStaysOnScreenAroundItsCentre() {
        let v = CGRect(x: 0, y: 25, width: 1200, height: 750)
        // Centred on where it was.
        XCTAssertEqual(WidthCycle.frame(CGRect(x: 400, y: 100, width: 400, height: 300), width: 600, in: v),
                       CGRect(x: 300, y: 100, width: 600, height: 300))
        // Near the right edge: pushed back in.
        XCTAssertEqual(WidthCycle.frame(CGRect(x: 1000, y: 100, width: 200, height: 300), width: 800, in: v),
                       CGRect(x: 400, y: 100, width: 800, height: 300))
        // Wider than the display: the display's width.
        XCTAssertEqual(WidthCycle.frame(CGRect(x: 0, y: 25, width: 200, height: 900), width: 2000, in: v), v)
    }

    func testCentredKeepsSize() {
        let v = CGRect(x: 0, y: 25, width: 1200, height: 750)
        XCTAssertEqual(WidthCycle.centred(CGRect(x: 10, y: 30, width: 400, height: 300), in: v), CGRect(x: 400, y: 250, width: 400, height: 300))
    }

    func testColumnShareSetsTheFractionAndKeepsOthersInProportion() {
        var t = DockNode.split(.h, [.window("a"), .window("b"), .window("c")], weights: [0.5, 0.3, 0.2])
        XCTAssertEqual(t.columnShare(of: "a")!, 0.5, accuracy: 0.0001)
        XCTAssertEqual(t.setColumnShare(of: "a", to: 0.9, length: 1000)!, 0.9, accuracy: 0.0001)
        XCTAssertEqual(t.weights[1], 0.06, accuracy: 0.0001)
        XCTAssertEqual(t.weights[2], 0.04, accuracy: 0.0001)
        // Full width leaves each other column its least share.
        XCTAssertEqual(t.setColumnShare(of: "a", to: 1, length: 1000)!, 0.9, accuracy: 0.0001)
    }

    func testColumnShareRespectsTheOthersSmallestSize() {
        var t = DockNode.split(.h, [.window("a"), .window("b")])
        let got = t.setColumnShare(of: "a", to: 1, length: 1000, mins: ["b": CGSize(width: 300, height: 100)])
        XCTAssertEqual(got!, 0.7, accuracy: 0.0001)
        XCTAssertEqual(t.weights[1], 0.3, accuracy: 0.0001)
    }

    func testColumnShareFindsTheRowAboveAColumn() {
        // b sits in a column (v split) inside the top row: the row is what it widens in.
        var t = DockNode.split(.h, [.window("a"), .split(.v, [.window("b"), .window("c")])])
        XCTAssertEqual(t.columnShare(of: "b")!, 0.5, accuracy: 0.0001)
        t.setColumnShare(of: "b", to: 2.0 / 3, length: 1000)
        XCTAssertEqual(t.weights[1], 2.0 / 3, accuracy: 0.0001)
        // A window alone has nothing beside it.
        var one = DockNode.split(.v, [.window("x"), .window("y")])
        XCTAssertNil(one.columnShare(of: "x"))
        XCTAssertNil(one.setColumnShare(of: "x", to: 0.5, length: 1000))
    }

    // MARK: Direction

    func testNearestThatWay() {
        let from = CGRect(x: 400, y: 200, width: 200, height: 200)
        let cands: [(String, CGRect)] = [
            ("left", CGRect(x: 0, y: 200, width: 390, height: 200)),
            ("farLeft", CGRect(x: -800, y: 200, width: 400, height: 200)),
            ("above", CGRect(x: 400, y: 0, width: 200, height: 190)),
            ("overlapping", CGRect(x: 500, y: 250, width: 200, height: 100)),
        ]
        XCTAssertEqual(Compass.nearest(from: from, cands, .left), "left")
        XCTAssertEqual(Compass.nearest(from: from, cands, .up), "above")
        XCTAssertNil(Compass.nearest(from: from, cands, .right))
        XCTAssertNil(Compass.nearest(from: from, cands, .down))
    }

    func testDisplayThatWay() {
        // A laptop with a display to its right and one above.
        let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let displays: [(String, CGRect)] = [("right", CGRect(x: 1440, y: -200, width: 1920, height: 1080)),
                                            ("above", CGRect(x: 0, y: -1080, width: 1440, height: 1080))]
        XCTAssertEqual(Compass.nearest(from: laptop, displays, .right), "right")
        XCTAssertEqual(Compass.nearest(from: laptop, displays, .up), "above")
        XCTAssertNil(Compass.nearest(from: laptop, displays, .left))
    }

    // MARK: Bento order

    func testBentoOrderKeepsAMovedOrder() {
        XCTAssertEqual(Bento.order(z: ["a", "b", "c"], kept: nil), ["a", "b", "c"])
        // A move set b, a, c; focusing c since doesn't change it.
        XCTAssertEqual(Bento.order(z: ["c", "a", "b"], kept: ["b", "a", "c"]), ["b", "a", "c"])
        // A new window goes first; a closed one drops out.
        XCTAssertEqual(Bento.order(z: ["d", "c", "a"], kept: ["b", "a", "c"]), ["d", "a", "c"])
    }

    // MARK: Keys

    func testDirectionKeysDontClash() {
        let st = DeskState()
        var seen: [Combo: ShortcutID] = [:]
        for id in ShortcutID.allCases {
            for c in st.bindings(id) {
                XCTAssertNil(seen[c], "\(id) and \(seen[c].map { "\($0)" } ?? "") share a key")
                seen[c] = id
            }
        }
        XCTAssertEqual(seen[Combo(key: kVK_ANSI_H, mods: controlKey | optionKey | cmdKey)], .focus)
        XCTAssertEqual(seen[Combo(key: kVK_ANSI_J, mods: controlKey | optionKey | shiftKey)], .moveWindow)
        XCTAssertEqual(seen[Combo(key: kVK_ANSI_W, mods: controlKey | optionKey)], .wider)
    }
}
