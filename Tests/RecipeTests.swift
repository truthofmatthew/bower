import XCTest
@testable import Bower

final class RecipeTests: XCTestCase {
    func testPlanParsesThroughProseAndFences() {
        let reply = """
        Sure! Here's the plan:
        ```json
        {"layouts":[{"number":1,"name":"Dev","windows":[{"app":"Code","display":"main monitor"},{"app":"Terminal"}]}],
         "modes":[{"display":"main monitor","mode":"Bento Box"}]}
        ```
        """
        let plan = RecipePlan.parse(reply)
        XCTAssertEqual(plan?.layouts.first?.windows.count, 2)
        XCTAssertNil(plan?.layouts.first?.windows[1].display)
        XCTAssertEqual(plan?.mode(for: "Main Monitor"), .bento)
        XCTAssertEqual(plan?.mode(for: "side monitor"), .native)
    }

    func testPlanWithoutModesStillParses() {
        XCTAssertEqual(RecipePlan.parse(#"{"layouts":[{"number":2,"name":"Comms","windows":[]}]}"#)?.modes, [])
        XCTAssertNil(RecipePlan.parse("I can't help with that."))
    }

    func testMentionsPreferTheLongestKnownName() {
        let line = "- Dev — @Code + @Terminal on @main monitor"
        let found = Mentions.find(in: line, known: ["Code", "Terminal", "main monitor", "main"])
        XCTAssertEqual(found.map(\.name), ["Code", "Terminal", "main monitor"])
        XCTAssertTrue(found.allSatisfy(\.known))
        XCTAssertEqual((line as NSString).substring(with: found[2].range), "@main monitor")
    }

    func testUnknownMentionStopsAtConnectors() {
        let line = "- Design — @Figma on @main monitor"
        let found = Mentions.find(in: line, known: ["main monitor"])
        XCTAssertEqual(found.first?.name, "Figma")
        XCTAssertEqual(found.first?.known, false)
        XCTAssertEqual((line as NSString).substring(with: found[0].range), "@Figma")
        XCTAssertEqual(found.last?.known, true)
    }

    /// Ranges are UTF-16, so text before the mention with accents or emoji doesn't shift the highlight.
    func testMentionRangesAreUTF16() {
        let line = "- Café 🎨 — @Figma, @Notes"
        let found = Mentions.find(in: line, known: ["Notes"])
        XCTAssertEqual((line as NSString).substring(with: found[0].range), "@Figma")
        XCTAssertEqual((line as NSString).substring(with: found[1].range), "@Notes")
    }
}
