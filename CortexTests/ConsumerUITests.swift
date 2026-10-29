import XCTest
import SwiftUI
import PencilKit
@testable import Cortex

@MainActor
final class ConsumerUITests:XCTestCase {
    func testMultiplyWashPreservesBlackAndTintsWhite() throws {
        let points = [CGPoint(x:5,y:20),CGPoint(x:95,y:20)].enumerated().map {i,p in
            PKStrokePoint(location:p,timeOffset:Double(i),size:CGSize(width:14,height:14),opacity:1,force:1,azimuth:0,altitude:.pi/2)
        }
        let ink = PKInk(.marker,color:UIColor(red:1,green:249.0/255,blue:189.0/255,alpha:1))
        let stroke = PKStroke(ink:ink,path:PKStrokePath(controlPoints:points,creationDate:Date()))
        let drawing = PKDrawing(strokes:[stroke,stroke])
        let format = UIGraphicsImageRendererFormat();format.scale = 1
        let image = UIGraphicsImageRenderer(size:CGSize(width:100,height:40),format:format).image {renderer in
            UIColor.white.setFill();renderer.fill(CGRect(x:0,y:0,width:100,height:40))
            UIColor.black.setFill();renderer.fill(CGRect(x:45,y:10,width:10,height:20))
            ConsumerInkRenderer.draw(drawing,in:renderer.cgContext)
        }
        let cg = try XCTUnwrap(image.cgImage)
        var rgba = [UInt8](repeating:0,count:100*40*4)
        rgba.withUnsafeMutableBytes {bytes in
            let context = CGContext(data:bytes.baseAddress,width:100,height:40,bitsPerComponent:8,bytesPerRow:400,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(cg,in:CGRect(x:0,y:0,width:100,height:40))
        }
        let black = (20*100+50)*4, wash = (20*100+20)*4
        XCTAssertLessThan(rgba[black],5);XCTAssertLessThan(rgba[black+1],5);XCTAssertLessThan(rgba[black+2],5)
        XCTAssertGreaterThan(rgba[wash],245);XCTAssertEqual(Double(rgba[wash+2]),189,accuracy:3)
        let payload = ConsumerInkRenderer.webPayload(drawing)
        XCTAssertEqual(payload.first?["wash"] as? Bool,true)
        XCTAssertGreaterThan((payload.first?["points"] as? [[Double]])?.count ?? 0,50)
    }
    func testErasedStrokeRangesStayErasedInVectorRendering() throws {
        let points = [CGPoint(x:10,y:20),CGPoint(x:100,y:20)].enumerated().map {i,p in PKStrokePoint(location:p,timeOffset:Double(i),size:CGSize(width:2,height:2),opacity:1,force:1,azimuth:0,altitude:.pi/2)}
        let stroke = PKStroke(ink:PKInk(.monoline,color:.red),path:PKStrokePath(controlPoints:points,creationDate:Date()),mask:UIBezierPath(rect:CGRect(x:0,y:0,width:45,height:40)))
        let visible = ConsumerInkRenderer.strokes(PKDrawing(strokes:[stroke])).flatMap(\.points)
        XCTAssertFalse(visible.isEmpty)
        XCTAssertLessThan(try XCTUnwrap(visible.map(\.x).max()),46)
    }
    func testUnderlinerLocksToStartBaseline() throws {
        let points = [CGPoint(x:10,y:10),CGPoint(x:100,y:40)].enumerated().map {i,p in PKStrokePoint(location:p,timeOffset:Double(i),size:CGSize(width:2,height:2),opacity:1,force:1,azimuth:0,altitude:.pi/2)}
        let original = PKDrawing(strokes:[PKStroke(ink:PKInk(.monoline,color:.red),path:PKStrokePath(controlPoints:points,creationDate:Date()))])
        let line = try XCTUnwrap(ConsumerInkRenderer.straightenLastStroke(original).strokes.first)
        XCTAssertEqual(line.path.first?.location.y,line.path.last?.location.y)
        XCTAssertEqual(line.path.last?.location.x,100)
    }
    func testInkClearUndoRedoKeepsOriginalDrawing() throws {
        let points = [CGPoint(x:10,y:10),CGPoint(x:100,y:40)].enumerated().map {i,p in PKStrokePoint(location:p,timeOffset:Double(i),size:CGSize(width:2,height:2),opacity:1,force:1,azimuth:0,altitude:.pi/2)}
        let canvas = ConsumerInputCanvas(frame:CGRect(x:0,y:0,width:200,height:200))
        canvas.drawing = PKDrawing(strokes:[PKStroke(ink:PKInk(.monoline,color:.red),path:PKStrokePath(controlPoints:points,creationDate:Date()))])
        canvas.clearMarks();XCTAssertTrue(canvas.drawing.strokes.isEmpty)
        canvas.history.undo();XCTAssertEqual(canvas.drawing.strokes.count,1)
        canvas.history.redo();XCTAssertTrue(canvas.drawing.strokes.isEmpty)
    }
    func testConsumerScreensRenderAtPhoneAndIPadSizes() async throws {
        let content = try JSONDecoder().decode(StudyContent.self,from:Data(#"{"cards":[{"front":"A sample question","back":"A sample answer"}]}"#.utf8))
        let card = StudyEntry(id:"ui-synthetic-card",kind:"Flashcards",document:"Example chapter",folder:"Example subject",title:"Example heading",content:content)
        for size in [CGSize(width:390,height:844),CGSize(width:744,height:1133)] {
            try await capture(ConsumerHomeView(),name:"Home",size:size)
            try await capture(StudySelectionView(kind:"Flashcards"),name:"Flashcards",size:size)
            try await capture(StudySelectionView(kind:"Qbank"),name:"Qbank",size:size)
            try await capture(CreateStudyView(),name:"Create",size:size)
            try await capture(FlashcardPlayer(entry:card,documentOrder:true),name:"Review",size:size)
            try await capture(StudyScopePopup(subjects:[ConsumerChoice(id:"Cardiology",title:"Cardiology",detail:"2 saved topics")],topics:[ConsumerChoice(id:"a",title:"Arrhythmia",detail:"III. Arrhythmia")],selectedSubject:.constant(["Cardiology"]),selectedTopics:.constant([]),startsWithTopics:true,close:{}),name:"TopicsPopup",size:size)
            let fixture = try XCTUnwrap(Bundle(for:ConsumerUITests.self).url(forResource:"reader-check",withExtension:"docx",subdirectory:"Fixtures"))
            try await capture(DocumentReader(document:LocalDocument(id:UUID(),title:"Reader check",importedAt:Date()),fileURL:fixture),name:"NoteControls",size:size)
            let snapshotContent = try JSONDecoder().decode(StudyContent.self,from:Data(#"{"title":"Example Snapshot","sections":[{"heading":"Example","points":["Readable text"]}]}"#.utf8))
            try await capture(SnapshotReader(entry:StudyEntry(id:"ui-snapshot",kind:"Snapshots",document:"Example",folder:"Example",title:"Example",content:snapshotContent)),name:"SnapshotControls",size:size)
        }
    }
    private func capture<V:View>(_ content:V,name:String,size:CGSize) async throws {
        let root = NavigationStack {content}.environmentObject(LibraryStore()).environmentObject(AccountSession()).preferredColorScheme(.light)
        let host = UIHostingController(rootView:root)
        let window = UIWindow(frame:CGRect(origin:.zero,size:size));window.rootViewController = host;window.makeKeyAndVisible()
        defer {window.isHidden = true}
        try await Task.sleep(nanoseconds:350_000_000)
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds:host.view.bounds).image {_ in host.view.drawHierarchy(in:host.view.bounds,afterScreenUpdates:true)}
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count,5000)
        let attachment = XCTAttachment(image:image);attachment.name="\(name)-\(Int(size.width))";attachment.lifetime = .keepAlways;add(attachment)
    }
}
