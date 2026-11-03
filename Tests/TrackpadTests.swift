import XCTest
@testable import Bower

final class TrackpadSwipeTests: XCTestCase {
    func testSwipeDirection() {
        let left = [(Float(-0.3), Float(0.02)), (-0.28, 0.01), (-0.31, 0.0)]
        XCTAssertEqual(TrackpadTap.swipe(left), 1)                        // fingers move left: next layout
        XCTAssertEqual(TrackpadTap.swipe(left.map { (-$0.0, $0.1) }), -1)  // right: previous
        XCTAssertNil(TrackpadTap.swipe([(0.05, 0), (0.04, 0), (0.06, 0)]))  // too short
        XCTAssertNil(TrackpadTap.swipe([(0.2, 0.3), (0.2, 0.3), (0.2, 0.3)]))  // mostly vertical
        XCTAssertNil(TrackpadTap.swipe([]))
    }
}
