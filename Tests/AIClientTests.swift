import SwiftUI
import XCTest
@testable import Bower

/// Answers requests from canned (status, body) pairs keyed by path suffix, and records the last request body.
final class MockEndpoint: URLProtocol {
    static var replies: [String: (Int, String)] = [:]
    static var lastBody: [String: Any]?

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "mock.local" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data(), buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            Self.lastBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        let path = request.url!.path
        let (code, body) = Self.replies.first { path.hasSuffix($0.key) }?.value ?? (404, "{}")
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class AIClientTests: XCTestCase {
    override func setUp() { URLProtocol.registerClass(MockEndpoint.self) }
    override func tearDown() { URLProtocol.unregisterClass(MockEndpoint.self); MockEndpoint.replies = [:] }

    private let settings = AISettings(preset: .custom, endpoint: "http://mock.local/v1", model: "stub-model")
    private let context = MentionContext(apps: [.init(kind: .app, name: "Finder", detail: "running", icon: nil)],
                                         displays: [.init(kind: .display, name: "main monitor", detail: "Built-in", icon: nil)],
                                         screens: [:])

    func testModelsAndPlan() async throws {
        let plan = #"{\"layouts\":[{\"number\":1,\"name\":\"Mail\",\"windows\":[{\"app\":\"Finder\",\"display\":\"main monitor\"}]}]}"#
        MockEndpoint.replies = [
            "/models": (200, #"{"data":[{"id":"b-model"},{"id":"a-model"}]}"#),
            "/chat/completions": (200, #"{"choices":[{"message":{"content":"Here you go:\n```json\n"# + plan + #"\n```"}}]}"#)
        ]
        let client = AIClient(settings: settings, key: "")
        let models = try await client.models()
        XCTAssertEqual(models, ["a-model", "b-model"])
        let result = try await client.plan(recipe: "- Mail — @Finder on @main monitor", context: context, layouts: ["Mail"])
        XCTAssertEqual(result.layouts.first?.windows.first?.app, "Finder")
        // The request carries the model, the recipe and what @ can refer to.
        XCTAssertEqual(MockEndpoint.lastBody?["model"] as? String, "stub-model")
        let user = ((MockEndpoint.lastBody?["messages"] as? [[String: Any]])?.last?["content"] as? String) ?? ""
        XCTAssertTrue(user.contains("Running apps: Finder"))
        XCTAssertTrue(user.contains("main monitor (Built-in)"))
        XCTAssertTrue(user.contains("@Finder"))
    }

    func testUnauthorizedAndNonPlanReplies() async {
        MockEndpoint.replies = ["/models": (401, #"{"error":{"message":"bad key"}}"#),
                                "/chat/completions": (200, #"{"choices":[{"message":{"content":"I can't do that."}}]}"#)]
        let client = AIClient(settings: settings, key: "sk-wrong")
        do { _ = try await client.models(); XCTFail("expected 401") } catch {
            XCTAssertEqual(error.localizedDescription, "401 Unauthorized · check the API key")
        }
        do { _ = try await client.plan(recipe: "x", context: context, layouts: []); XCTFail("expected notAPlan") } catch {
            XCTAssertEqual(error.localizedDescription, "The model's reply wasn't a plan")
        }
    }

    @MainActor func testRecipeWindowKeepsTheDesignSize() {
        let w = HostedWindow(title: "Recipe", size: CGSize(width: 1020, height: 604), bareTitlebar: true, hideButtons: true) {
            Color.clear.frame(width: 1020, height: 604)
        }
        XCTAssertEqual(w.frame.size, CGSize(width: 1020, height: 604))
    }
}
