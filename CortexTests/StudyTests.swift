import XCTest
@testable import Cortex

final class StudyTests: XCTestCase {
    func testSubjectAndChapterSelectionExcludesOtherStudySets() throws {
        func entry(_ id:String,_ kind:String,_ folder:String,_ document:String) throws -> StudyEntry {
            let source = kind == "Qbank" ? #"{"questions":[{"question":"Q","options":["A","B"],"correctIndex":0,"explanation":"E"}]}"# : #"{"cards":[{"front":"Q","back":"A"}]}"#
            let content = try JSONDecoder().decode(StudyContent.self,from:Data(source.utf8))
            return StudyEntry(id:id,kind:kind,document:document,folder:folder,title:id,content:content)
        }
        let rows = try [entry("a","Flashcards","Cardiology","I. Heart"),entry("b","Flashcards","Cardiology","II. ECG"),entry("c","Flashcards","Neurology","I. Heart"),entry("d","Qbank","Cardiology","I. Heart")]
        XCTAssertEqual(StudySelection.scope(rows,kind:"Flashcards",subject:"cardiology",chapter:nil).map(\.id),["a","b"])
        XCTAssertEqual(StudySelection.scope(rows,kind:"Flashcards",subject:"Cardiology",chapter:"I. Heart").map(\.id),["a"])
        XCTAssertEqual(StudySelection.scope(rows,kind:"Qbank",subject:"Cardiology",chapter:"I. Heart").map(\.id),["d"])
    }
    @MainActor
    func testCombinedFlashcardsKeepOriginalReviewProgress() throws {
        let content = try JSONDecoder().decode(StudyContent.self,from:Data(#"{"cards":[{"front":"First","back":"Answer"},{"front":"Second","back":"Answer"}]}"#.utf8))
        let a = StudyEntry(id:"deck-a",kind:"Flashcards",document:"A",folder:"Cardiology",title:"A",content:content)
        let b = StudyEntry(id:"deck-b",kind:"Flashcards",document:"B",folder:"Neurology",title:"B",content:content)
        let combined = StudySelection.aggregate([a,b],kind:"Flashcards",title:"Selected subjects")
        XCTAssertEqual(combined.content.cards?.count,4)
        XCTAssertEqual(combined.id,StudySelection.aggregate([b,a],kind:"Flashcards",title:"Selected subjects").id)
        XCTAssertEqual(StudyProgress.cardKey(combined,index:0),"deck-a/0")
        let suite = "selection-tests-"+UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite));defer { defaults.removePersistentDomain(forName:suite) }
        let progress = StudyProgress(defaults:defaults)
        progress.review(entry:a.id,index:0,grade:2)
        XCTAssertFalse(progress.dueQueue(combined).contains(0))
        XCTAssertEqual(progress.dueQueue(combined).count,3)
    }

    func testAndroidReviewIntervalProgressionAndBounds() {
        var days = 0.0
        // Verified against Android's aiFlashcardNextIntervalDays: Math.round(4.5) is 5.
        for expected in [2.0, 5, 11, 30, 68, 180, 365] {
            days = StudyProgress.nextInterval(current: days, grade: 2)
            XCTAssertEqual(days, expected)
        }
        XCTAssertEqual(StudyProgress.nextInterval(current: 30, grade: 0), 0)
        XCTAssertEqual(StudyProgress.nextInterval(current: 10, grade: 3, maximum: 20), 20)
        XCTAssertLessThan(StudyProgress.nextInterval(current: 30, grade: 2, retention: 0.99), StudyProgress.nextInterval(current: 30, grade: 2, retention: 0.80))
    }

    @MainActor
    func testStudyAttemptReviewAndScoreSurviveRelaunch() throws {
        let suite = "cortex-study-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let progress = StudyProgress(defaults: defaults)
        progress.review(entry: "example", index: 0, grade: 2)
        progress.saveAttempt(entry: "quiz", answers: [0: 1, 2: 3], completed: false)
        progress.recordQuiz(title: "Example quiz", correct: 2, total: 3)
        let restored = StudyProgress(defaults: defaults)
        XCTAssertEqual(restored.attempts["quiz"]?.answers, [0: 1, 2: 3])
        XCTAssertEqual(restored.attempts["quiz"]?.completed, false)
        XCTAssertEqual(restored.quizzes.first?.correct, 2)
        XCTAssertGreaterThan(try XCTUnwrap(restored.cards["example/0"]).due.timeIntervalSinceNow, 23 * 3600)
    }

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
