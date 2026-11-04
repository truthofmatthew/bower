import XCTest
@testable import Bower

final class DockTreeTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private func noOverlap(_ s: DockNode.Solved, file: StaticString = #filePath, line: UInt = #line) {
        let rects = Array(Set(s.frames.values.map { "\($0)" })).compactMap { r in s.frames.values.first { "\($0)" == r } }
        for (i, a) in rects.enumerated() {
            for b in rects[(i + 1)...] { XCTAssertTrue(a.intersection(b).area == 0, "\(a) overlaps \(b)", file: file, line: line) }
        }
    }

    func testAddThenRemoveIsUndone() {
        var t = DockNode.split(.h, [.window("a"), .window("b")])
        let before = t
        t.add("c", beside: nil, frames: [:])
        XCTAssertEqual(t.keys, ["a", "b", "c"])
        t.remove("c", share: true)
        XCTAssertEqual(t.keys, before.keys)
        XCTAssertEqual(t.weights.map { ($0 * 1000).rounded() }, [500, 500])
    }

    func testRemoveWithoutShareGivesNeighbourAll() {
        var t = DockNode.split(.h, [.window("a"), .window("b"), .window("c")], weights: [0.5, 0.25, 0.25])
        t.remove("a", share: false)
        XCTAssertEqual(t.weights, [0.75, 0.25])
    }

    func testInsertAtEdgeNestsAcrossAxis() {
        var t = DockNode.split(.h, [.window("a"), .window("b")])
        t.insert(.window("c"), at: .bottom, of: t.path(of: "b")!)
        XCTAssertEqual(t.children[1].axis, .v)
        XCTAssertEqual(t.children[1].keys, ["b", "c"])
        let s = t.solve(in: screen, gap: 10)
        noOverlap(s)
        XCTAssertEqual(s.frames["a"]?.width, 495)
        XCTAssertEqual(s.frames["b"]!.maxY + 10, s.frames["c"]!.minY)
        XCTAssertEqual(s.seams.count, 2)
    }

    func testInsertSameAxisBecomesSibling() {
        var t = DockNode.split(.h, [.window("a"), .window("b")])
        t.insert(.window("c"), at: .left, of: t.path(of: "b")!)
        XCTAssertEqual(t.keys, ["a", "c", "b"])
        XCTAssertEqual(t.weights, [0.5, 0.25, 0.25])
    }

    func testSolveFillsRectExactly() {
        let t = DockNode.split(.h, [.window("a"), .split(.v, [.window("b"), .desktop]), .window("c")], weights: [0.3, 0.3, 0.4])
        let s = t.solve(in: screen, gap: 6)
        noOverlap(s)
        XCTAssertEqual(s.frames["a"]!.minX, 0)
        XCTAssertEqual(s.frames["c"]!.maxX, 1000)
        XCTAssertNotNil(s.desktop)
    }

    func testResizeMovesSeam() {
        var t = DockNode.split(.h, [.window("a"), .window("b")])
        t.resize([], seam: 0, by: 100, length: 1000)
        XCTAssertEqual(t.weights[0], 0.6, accuracy: 0.0001)
    }

    func testGroupAndUngroup() {
        var t = DockNode.split(.h, [.window("a"), .window("b")])
        t.group("b", onto: "a", share: true)
        XCTAssertEqual(t.kind, .tabs)
        XCTAssertEqual(t.keys, ["a", "b"])
        let s = t.solve(in: screen, gap: 6)
        XCTAssertEqual(s.frames["a"], s.frames["b"])
        t.ungroup("b")
        XCTAssertEqual(Set(t.keys), ["a", "b"])
        XCTAssertNotEqual(t.solve(in: screen, gap: 6).frames["a"], t.solve(in: screen, gap: 6).frames["b"])
    }

    func testDropTargetBands() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(DropTarget.over("a", frame: r, at: CGPoint(x: 5, y: 50)), .edge(.left, of: "a"))
        XCTAssertEqual(DropTarget.over("a", frame: r, at: CGPoint(x: 50, y: 50)), .middle(of: "a"))
        XCTAssertEqual(DropTarget.over("a", frame: r, at: CGPoint(x: 50, y: 97)), .edge(.bottom, of: "a"))
    }

    func testHistory() {
        var h = History<Int>()
        h.push(1); h.push(2)
        XCTAssertEqual(h.goBack(from: 3), 2)
        XCTAssertEqual(h.goForward(from: 2), 3)
        h.push(9)
        XCTAssertTrue(h.forward.isEmpty)
    }

    func testCodableRoundTrip() throws {
        let t = DockNode.split(.v, [.window("a"), DockNode(kind: .tabs, children: [.window("b"), .window("c")], selected: 1)])
        XCTAssertEqual(try JSONDecoder().decode(DockNode.self, from: JSONEncoder().encode(t)), t)
    }
}
