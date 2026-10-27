import XCTest
@testable import Cortex

final class StudyTests: XCTestCase {
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
