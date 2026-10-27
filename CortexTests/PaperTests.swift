import XCTest
import PDFKit
import PencilKit
@testable import Cortex

@MainActor
final class PaperTests: XCTestCase {
    func testLongSlideExportFlowsWithoutDroppingLastPoint() throws {
        let points = (0..<100).map { ["text": "Point \($0): a sentence that must remain readable in the exported presentation."] } + [["text": "Final slide sentinel"]]
        let content = try JSONDecoder().decode(StudyContent.self, from: JSONSerialization.data(withJSONObject: ["title": "Test", "sections": [["heading": "Long slide", "points": points]]]))
        let entry = StudyEntry(id: "test", kind: "Slides", document: "Test", folder: "Test", title: "Test", content: content)
        let url = try SlideExport.pdf(entry)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue((document.string ?? "").contains("Final slide sentinel"))
    }

    func testNotebookPagesAndPenMarksSurviveReopenAndExport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = PaperLibrary(directory: directory)
        try library.create(title: "Test notebook", ruled: true)
        let file = try XCTUnwrap(library.files.first)
        try library.appendPage(file)
        XCTAssertEqual(PDFDocument(url: library.url(file))?.pageCount, 2)
        XCTAssertEqual(PaperLibrary(directory: directory).files.first?.title, "Test notebook")
        let points = [CGPoint(x: 40, y: 50), CGPoint(x: 180, y: 150)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index), size: CGSize(width: 5, height: 5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .red), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        let drawing = PKDrawing(strokes: [stroke])
        try drawing.dataRepresentation().write(to: library.drawingURL(file, page: 1))
        let controller = PaperController(file: file, store: library)
        defer { controller.stop() }
        let output = try controller.export()
        defer { try? FileManager.default.removeItem(at: output) }
        let exported = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(exported.pageCount, 2)
        let page = try XCTUnwrap(exported.page(at: 1))
        let image = page.thumbnail(of: CGSize(width: 595, height: 842), for: .mediaBox)
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        XCTAssertTrue(rendered)
        let redPixels = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 180 && pixels[$0 + 1] < 100 && pixels[$0 + 2] < 100 }.count
        XCTAssertGreaterThan(redPixels, 50, "The exported PDF must contain the saved red pen stroke")
        XCTAssertEqual(try PKDrawing(data: Data(contentsOf: library.drawingURL(file, page: 1))).strokes.count, 1)
        try library.remove(file)
        XCTAssertTrue(PaperLibrary(directory: directory).files.isEmpty)
    }
}
