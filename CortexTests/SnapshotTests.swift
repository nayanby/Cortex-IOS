import XCTest
import WebKit
import PencilKit
@testable import Cortex

@MainActor
final class SnapshotTests: XCTestCase {
    func testConsumerSnapshotLayoutTablesColorsAndEscaping() async throws {
        let source = #"{"title":"Snapshot <script>window.injected=true</script>","sections":[{"heading":"First section","points":[{"text":"**Definition:** A **key finding**","subpoints":["Nested detail"]}],"groups":[{"heading":"Group heading","numbered":["1. Numbered item"]}],"tables":[{"headers":["Feature","Value"],"rows":[["A","B"],["C","D"]]}]},{"heading":"Second section","points":[{"text":"Another point"}]}]}"#
        let content = try JSONDecoder().decode(StudyContent.self,from:Data(source.utf8))
        let entry = StudyEntry(id:"snapshot-test-"+UUID().uuidString,kind:"Snapshots",document:"Test",folder:"Test",title:"Test",content:content)
        let controller = SnapshotController(entry:entry)
        let host = UIViewController(), window = UIWindow(frame:CGRect(x:0,y:0,width:390,height:844))
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.addSubview(controller.webView); controller.webView.frame = host.view.bounds
        defer { controller.stop(); window.isHidden = true }
        controller.load()
        let deadline = Date().addingTimeInterval(30)
        while controller.isLoading && Date() < deadline { try await Task.sleep(nanoseconds:100_000_000) }
        XCTAssertFalse(controller.isLoading); XCTAssertNil(controller.error)
        let result = try await controller.webView.evaluateJavaScript("""
            (()=>({sections:document.querySelectorAll('.section').length,
              tableRows:document.querySelectorAll('.poster-table tr').length,
              nested:document.querySelectorAll('.doc-li.sub').length,
              label:getComputedStyle(document.querySelector('.label')).color,
              emphasis:getComputedStyle(document.querySelector('strong')).color,
              family:getComputedStyle(document.querySelector('.section-body')).fontFamily,
              text:document.body.textContent, injected:window.injected===true}))()
            """) as? [String:Any]
        XCTAssertEqual(result?["sections"] as? Int,2)
        XCTAssertEqual(result?["tableRows"] as? Int,3)
        XCTAssertEqual(result?["nested"] as? Int,1)
        XCTAssertEqual(result?["label"] as? String,"rgb(40, 70, 124)")
        XCTAssertEqual(result?["emphasis"] as? String,"rgb(111, 61, 93)")
        XCTAssertTrue((result?["family"] as? String ?? "").contains("Lato"))
        XCTAssertEqual(result?["injected"] as? Bool,false)
        XCTAssertTrue((result?["text"] as? String ?? "").contains("<script>window.injected=true</script>"))
        let output = try await controller.exportPDF()
        defer { try? FileManager.default.removeItem(at:output) }
        XCTAssertGreaterThan((try Data(contentsOf:output)).count,1000)
    }
    func testConsumerPenPaletteUsesExactColorsAndWidths() throws {
        let suite = "cortex-ink-tests-"+UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite)); defer { defaults.removePersistentDomain(forName:suite) }
        let settings = CortexInkSettings(defaults:defaults)
        XCTAssertEqual(settings.hexColors,[0x28467C,0x6F3D5D,0xAF3E3E])
        settings.select(.highlighter)
        XCTAssertEqual(settings.hexColors,[0xFFEAEA,0xFFF9BD,0xCCFBFA])
        XCTAssertEqual(try XCTUnwrap(settings.tool as? PKInkingTool).width,14,accuracy:0.001)
        settings.select(.underliner)
        XCTAssertEqual(settings.hexColors,[0xE89090,0xD4C04A,0xB1E5E6])
        settings.select(.pen);settings.color(1)
        let tool = try XCTUnwrap(settings.tool as? PKInkingTool)
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        XCTAssertTrue(tool.color.getRed(&r,green:&g,blue:&b,alpha:&a))
        XCTAssertEqual(r,111.0/255,accuracy:0.001);XCTAssertEqual(g,61.0/255,accuracy:0.001);XCTAssertEqual(b,93.0/255,accuracy:0.001);XCTAssertEqual(a,1)
    }
}
