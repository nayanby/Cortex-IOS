import XCTest
import WebKit
@testable import Cortex

@MainActor
final class ReaderTests: XCTestCase {
    func testWordRenderingWithTableFormulaAndEscapedText() async throws {
        let fixture = try XCTUnwrap(Bundle(for: ReaderTests.self).url(forResource: "reader-check", withExtension: "docx", subdirectory: "Fixtures"))
        let documentID = UUID()
        let progressKey = "reading.\(documentID.uuidString)"
        UserDefaults.standard.set(0.35, forKey: progressKey)
        defer { UserDefaults.standard.removeObject(forKey: progressKey) }
        let controller = ReaderController(fileURL: fixture, documentID: documentID)
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
        let restored = try await controller.webView.evaluateJavaScript("window.cortexReadingProgress()") as? Double
        XCTAssertEqual(try XCTUnwrap(restored), 0.35, accuracy: 0.02)
        let baseline = try await controller.webView.evaluateJavaScript("parseFloat(getComputedStyle(document.querySelector('#paper .doc-p')).fontSize)") as? Double
        for _ in 0..<2 {
            let applied = try await controller.webView.callAsyncJavaScript("return window.cortexSetTypography(delta, line, paragraph);",
                arguments: ["delta": 1.5, "line": 1.75, "paragraph": 0.32], in: nil, contentWorld: .page) as? Bool
            XCTAssertEqual(applied, true)
            let enlarged = try await controller.webView.evaluateJavaScript("parseFloat(getComputedStyle(document.querySelector('#paper .doc-p')).fontSize)") as? Double
            XCTAssertEqual(try XCTUnwrap(enlarged), try XCTUnwrap(baseline) + 2, accuracy: 0.05)
        }
        _ = try await controller.webView.callAsyncJavaScript("return window.cortexSetTypography(0, 1.4375, 0.16);", arguments: [:], in: nil, contentWorld: .page)
        let reset = try await controller.webView.evaluateJavaScript("parseFloat(getComputedStyle(document.querySelector('#paper .doc-p')).fontSize)") as? Double
        XCTAssertEqual(try XCTUnwrap(reset), try XCTUnwrap(baseline), accuracy: 0.05)
        let jumped = try await controller.webView.callAsyncJavaScript("return window.cortexJumpToHeading(index);",
            arguments: ["index": 0], in: nil, contentWorld: .page) as? Bool
        XCTAssertEqual(jumped, true)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertLessThan(UserDefaults.standard.double(forKey: progressKey), 0.02)
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
