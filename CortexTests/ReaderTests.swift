import XCTest
import WebKit
@testable import Cortex

@MainActor
final class ReaderTests: XCTestCase {
    func testWordRenderingWithTableFormulaAndEscapedText() async throws {
        let fixture = try XCTUnwrap(Bundle(for: ReaderTests.self).url(forResource: "reader-check", withExtension: "docx", subdirectory: "Fixtures"))
        let controller = ReaderController(fileURL: fixture, documentID: UUID())
        // A visible host gives WebKit a normal drawing and layout lifecycle.
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.addSubview(controller.webView)
        controller.webView.frame = host.view.bounds
        defer { controller.stop(); window.isHidden = true }
        controller.load()
        let deadline = Date().addingTimeInterval(30)
        while controller.isLoading && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertFalse(controller.isLoading, "Reader timed out")
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(controller.headings.first?.text, "Reader integration check")
        let text = try await controller.webView.evaluateJavaScript("document.getElementById('paper').textContent") as? String
        XCTAssertTrue(text?.contains("Table value") == true)
        XCTAssertTrue(text?.contains("eGFR = 90") == true)
        XCTAssertTrue(text?.contains("<script>window.injected=true</script>") == true)
        let injected = try await controller.webView.evaluateJavaScript("window.injected === true") as? Bool
        XCTAssertEqual(injected, false)
        let tableCount = try await controller.webView.evaluateJavaScript("document.querySelectorAll('#paper table').length") as? Int
        XCTAssertEqual(tableCount, 1)
        let fontReady = try await controller.webView.evaluateJavaScript("document.fonts.check('16px \"Averia Serif Libre\"')") as? Bool
        XCTAssertEqual(fontReady, true)
        let jumped = try await controller.webView.callAsyncJavaScript("return window.cortexJumpToHeading(index);",
            arguments: ["index": 0], in: nil, contentWorld: .page) as? Bool
        XCTAssertEqual(jumped, true)
    }

    func testImportPersistsAndDeletesOriginalBytes() async throws {
        let fixture = try XCTUnwrap(Bundle(for: ReaderTests.self).url(forResource: "reader-check", withExtension: "docx", subdirectory: "Fixtures"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalDocuments(directory: dir)
        try await store.importDocument(from: fixture)
        let document = try XCTUnwrap(store.documents.first)
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: document)), try Data(contentsOf: fixture))
        let reloaded = LocalDocuments(directory: dir)
        XCTAssertEqual(reloaded.documents.first?.id, document.id)
        try reloaded.remove(document)
        XCTAssertTrue(LocalDocuments(directory: dir).documents.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: document).path))
    }
}
