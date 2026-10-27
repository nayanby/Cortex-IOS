import XCTest
@testable import Cortex

final class StudyTests: XCTestCase {
    func testGeminiRequestUsesKeyHeaderAndParsesStructuredDeck() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeminiStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let entry = try await StudyAI.generate(kind: "Flashcards", topic: "Test topic", source: "Local source text",
            suppliedKey: "fake-test-credential", transport: session)
        XCTAssertEqual(entry.content.cards?.first?.front, "Question")
        XCTAssertEqual(entry.content.cards?.first?.back, "Answer")
        XCTAssertTrue(entry.id.hasPrefix("generated-"))
    }

    func testSnapshotWithGroupsTablesAndTextPointsDecodes() throws {
        let source = #"{"title":"Example","sections":[{"heading":"Overview","points":["Plain point",{"text":"Main point","subpoints":["Detail"]}],"groups":[{"heading":"Group","numbered":["First"]}],"tables":[{"headers":["Name","Value"],"rows":[["A","B"]]}]}]}"#
        let content = try JSONDecoder().decode(StudyContent.self, from: Data(source.utf8))
        try StudyAI.validate(content, kind: "Snapshots")
        XCTAssertEqual(content.sections?.first?.points?.first?.text, "Plain point")
        XCTAssertEqual(content.sections?.first?.tables?.first?.rows?.first, ["A", "B"])
        let roundTrip = try JSONDecoder().decode(StudyContent.self, from: JSONEncoder().encode(content))
        XCTAssertEqual(roundTrip.sections?.first?.groups?.first?.numbered, ["First"])
    }
    func testRejectsQuestionAnswerOutsideOptionsAndEmptyDeck() throws {
        let source = #"{"questions":[{"question":"Which?","options":["A","B"],"correctIndex":3,"explanation":"Explanation"}]}"#
        let invalid = try JSONDecoder().decode(StudyContent.self, from: Data(source.utf8))
        XCTAssertThrowsError(try StudyAI.validate(invalid, kind: "Qbank"))
        let empty = try JSONDecoder().decode(StudyContent.self, from: Data(#"{"cards":[]}"#.utf8))
        XCTAssertThrowsError(try StudyAI.validate(empty, kind: "Flashcards"))
    }
}

private final class GeminiStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url?.host, "generativelanguage.googleapis.com")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "fake-test-credential")
        XCTAssertEqual(request.httpMethod, "POST")
        let payload: [String: Any] = ["candidates": [["finishReason": "STOP", "content": ["parts": [["text": #"{"cards":[{"front":"Question","back":"Answer"}]}"#]]]]]]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
