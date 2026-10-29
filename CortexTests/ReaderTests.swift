import XCTest
import WebKit
import PencilKit
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
                arguments: ["delta": 1.0, "line": 1.75, "paragraph": 0.32], in: nil, contentWorld: .page) as? Bool
            XCTAssertEqual(applied, true)
            let enlarged = try await controller.webView.evaluateJavaScript("parseFloat(getComputedStyle(document.querySelector('#paper .doc-p')).fontSize)") as? Double
            XCTAssertEqual(try XCTUnwrap(enlarged), try XCTUnwrap(baseline) + 4.0/3.0, accuracy: 0.05)
        }
        let expanded = try await controller.webView.callAsyncJavaScript("return window.cortexSetTypography(3, 1.4375, 0.16);",arguments:[:],in:nil,contentWorld:.page) as? Bool
        XCTAssertEqual(expanded,true,"Font adjustments must work beyond the old 1.5-point limit")
        let large = try await controller.webView.evaluateJavaScript("parseFloat(getComputedStyle(document.querySelector('#paper .doc-p')).fontSize)") as? Double
        XCTAssertEqual(try XCTUnwrap(large),try XCTUnwrap(baseline)+4,accuracy:0.05)
        _ = try await controller.webView.callAsyncJavaScript("return window.cortexSetTypography(0, 1.4375, 0.16);", arguments: [:], in: nil, contentWorld: .page)
        let reset = try await controller.webView.evaluateJavaScript("parseFloat(getComputedStyle(document.querySelector('#paper .doc-p')).fontSize)") as? Double
        XCTAssertEqual(try XCTUnwrap(reset), try XCTUnwrap(baseline), accuracy: 0.05)
        let highlighted = try await controller.webView.evaluateJavaScript("""
            (() => {
              const node = document.querySelector('#paper .doc-p').firstChild;
              const walker = document.createTreeWalker(document.querySelector('#paper .doc-p'), NodeFilter.SHOW_TEXT);
              const text = walker.nextNode();
              const range = document.createRange(); range.setStart(text, 0); range.setEnd(text, Math.min(6, text.length));
              const selection = getSelection(); selection.removeAllRanges(); selection.addRange(range);
              const records = window.cortexHighlightSelection('yellow');
              window.cortexApplyHighlights(records);
              return document.querySelectorAll('mark[data-cortex-highlight]').length > 0;
            })()
            """) as? Bool
        XCTAssertEqual(highlighted, true)
        let afterHighlight = try await controller.webView.evaluateJavaScript("document.getElementById('paper').textContent") as? String
        XCTAssertEqual(afterHighlight, text, "Highlighting must preserve all document text")
        let stale = try await controller.webView.callAsyncJavaScript("return window.cortexApplyHighlights(records).length;",
            arguments: ["records": [["start": 0, "end": 5, "quote": "WRONG", "color": "yellow"]]], in: nil, contentWorld: .page) as? Int
        XCTAssertEqual(stale, 0, "Changed document text must not receive an old highlight")
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
    func testNoteInkRestoresAsBlendedVectorsAfterReopening() async throws {
        let fixture = try XCTUnwrap(Bundle(for:ReaderTests.self).url(forResource:"reader-check",withExtension:"docx",subdirectory:"Fixtures"))
        let id = UUID()
        let path = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ReaderInk").appendingPathComponent(id.uuidString+".drawing")
        defer {try? FileManager.default.removeItem(at:path)}
        let first = ReaderController(fileURL:fixture,documentID:id)
        let points = [CGPoint(x:30,y:60),CGPoint(x:180,y:60)].enumerated().map {i,p in PKStrokePoint(location:p,timeOffset:Double(i),size:CGSize(width:14,height:14),opacity:1,force:1,azimuth:0,altitude:.pi/2)}
        first.pen.canvas.drawing = PKDrawing(strokes:[PKStroke(ink:PKInk(.marker,color:.yellow),path:PKStrokePath(controlPoints:points,creationDate:Date()))])
        first.stop()
        let reopened = ReaderController(fileURL:fixture,documentID:id)
        XCTAssertEqual(reopened.pen.canvas.drawing.strokes.count,1)
        let host = UIViewController(),window = UIWindow(frame:CGRect(x:0,y:0,width:390,height:844))
        window.rootViewController = host;window.makeKeyAndVisible();host.view.addSubview(reopened.webView);reopened.webView.frame = host.view.bounds
        defer {reopened.stop();window.isHidden = true}
        reopened.load()
        let deadline = Date().addingTimeInterval(30)
        while reopened.isLoading && Date()<deadline {try await Task.sleep(nanoseconds:100_000_000)}
        XCTAssertFalse(reopened.isLoading);XCTAssertNil(reopened.errorMessage)
        try await Task.sleep(nanoseconds:200_000_000)
        let result = try await reopened.webView.evaluateJavaScript("({count:document.querySelectorAll('#cortex-ink-wash path').length,blend:getComputedStyle(document.getElementById('cortex-ink-wash')).mixBlendMode})") as? [String:Any]
        XCTAssertEqual(result?["count"] as? Int,1);XCTAssertEqual(result?["blend"] as? String,"multiply")
    }

}
