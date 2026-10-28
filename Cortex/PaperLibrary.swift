import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers
import ImageIO

struct PaperFile: Identifiable, Codable {
    let id: UUID
    var title: String
    let kind: String
    let ruled: Bool
}
@MainActor
final class PaperLibrary: ObservableObject {
    static let shared = PaperLibrary()
    @Published private(set) var files: [PaperFile] = []
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Paper", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: self.directory.appendingPathComponent("index.json")), let saved = try? JSONDecoder().decode([PaperFile].self, from: data) { files = saved }
    }
    func url(_ file: PaperFile) -> URL { directory.appendingPathComponent(file.id.uuidString + ".pdf") }
    private func commit(_ updated: [PaperFile]) throws {
        try JSONEncoder().encode(updated).write(to: directory.appendingPathComponent("index.json"), options: [.atomic, .completeFileProtection])
        files = updated
    }
    func importPDF(_ source: URL) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 100 * 1024 * 1024 else { throw StudyAIError.message("Choose a PDF under 100 MB.") }
        guard let document = PDFDocument(url: source), document.pageCount > 0, !document.isLocked else { throw StudyAIError.message("Choose a readable, unlocked PDF.") }
        let file = PaperFile(id: UUID(), title: source.deletingPathExtension().lastPathComponent, kind: "PDFs", ruled: false)
        try Data(contentsOf: source).write(to: url(file), options: [.atomic, .completeFileProtection])
        do { try commit([file] + files) } catch { try? FileManager.default.removeItem(at: url(file)); throw error }
    }
    func create(title: String, ruled: Bool) throws {
        let file = PaperFile(id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Notebook" : title, kind: "Notebooks", ruled: ruled)
        try blankPage(ruled: ruled).write(to: url(file), options: [.atomic, .completeFileProtection])
        do { try commit([file] + files) } catch { try? FileManager.default.removeItem(at: url(file)); throw error }
    }
    func saveRenderedPDF(_ data: Data, title: String, id: UUID) throws -> PaperFile {
        if let existing = files.first(where: { $0.id == id }) { return existing }
        let file = PaperFile(id: id, title: title, kind: "PDFs", ruled: false)
        try data.write(to: url(file), options: [.atomic, .completeFileProtection])
        do { try commit([file] + files) } catch { try? FileManager.default.removeItem(at: url(file)); throw error }
        return file
    }
    func existing(id: UUID) -> PaperFile? { files.first { $0.id == id } }
    func appendPage(_ file: PaperFile) throws {
        guard let document = PDFDocument(url: url(file)), let blank = PDFDocument(data: blankPage(ruled: file.ruled)), let page = blank.page(at: 0) else { throw StudyAIError.message("The notebook could not be opened.") }
        document.insert(page, at: document.pageCount)
        guard let data = document.dataRepresentation() else { throw StudyAIError.message("The page could not be added.") }
        try data.write(to: url(file), options: [.atomic, .completeFileProtection])
    }
    func appendImage(_ file: PaperFile, source: URL) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 3000] as CFDictionary),
              let document = PDFDocument(url: url(file)) else { throw StudyAIError.message("Choose a readable image file.") }
        let bounds = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage(); UIColor.white.setFill(); context.cgContext.fill(bounds)
            let size = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
            let scale = min((bounds.width - 40) / size.width, (bounds.height - 40) / size.height)
            let target = CGRect(x: (bounds.width - size.width * scale) / 2, y: (bounds.height - size.height * scale) / 2, width: size.width * scale, height: size.height * scale)
            UIImage(cgImage: image).draw(in: target)
        }
        guard let page = PDFDocument(data: data)?.page(at: 0) else { throw StudyAIError.message("The image could not be added.") }
        document.insert(page, at: document.pageCount)
        guard let updated = document.dataRepresentation() else { throw StudyAIError.message("The notebook could not be saved.") }
        try updated.write(to: url(file), options: [.atomic, .completeFileProtection])
    }
    func rename(_ file: PaperFile, title: String) throws {
        var updated = files
        guard let index = updated.firstIndex(where: { $0.id == file.id }), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        updated[index].title = title
        try commit(updated)
    }
    func remove(_ file: PaperFile) throws {
        try commit(files.filter { $0.id != file.id })
        try FileManager.default.removeItem(at: url(file))
        // Drawing files remain recoverable rather than deleting annotations on an index error.
    }
    func drawingURL(_ file: PaperFile, page: Int) -> URL { directory.appendingPathComponent(file.id.uuidString + "-" + String(page) + ".drawing") }
    private func blankPage(ruled: Bool) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            UIColor.white.setFill(); context.cgContext.fill(bounds)
            if ruled {
                context.cgContext.setStrokeColor(UIColor(red: 0.82, green: 0.86, blue: 0.93, alpha: 1).cgColor)
                context.cgContext.setLineWidth(0.5)
                var y: CGFloat = 50
                while y < bounds.height - 35 {
                    context.cgContext.move(to: CGPoint(x: 30, y: y)); context.cgContext.addLine(to: CGPoint(x: bounds.width - 30, y: y))
                    y += 8 * 72 / 25.4
                }
                context.cgContext.strokePath()
            }
        }
    }
}

struct PaperBrowser: View {
    let kind: String
    @ObservedObject private var store = PaperLibrary.shared
    @State private var importing = false
    @State private var creating = false
    @State private var title = ""
    @State private var ruled = true
    @State private var error: String?
    var body: some View {
        ScrollView {
            LazyVStack(spacing:8) {
                if store.files.filter({$0.kind == kind}).isEmpty {
                    Text(kind == "PDFs" ? "No PDFs yet. Import a PDF to read and write on it." : "No notebooks yet. Create a notebook to start writing.")
                        .font(.system(size:15)).foregroundStyle(CortexStyle.muted).multilineTextAlignment(.center).padding(32)
                }
                ForEach(store.files.filter {$0.kind == kind}) {file in
                    NavigationLink {PaperReader(file:file)} label: {
                        HStack(spacing:12) {
                            CortexArtwork(name:kind == "PDFs" ? "pdf" : "notebook",size:40)
                            Text(file.title).font(CortexStyle.title(16));Spacer();CortexArtwork(name:"right",size:22)
                        }.padding(16).frame(maxWidth:.infinity,minHeight:76,alignment:.leading)
                            .background(LinearGradient(colors:kind == "PDFs" ? [Color(hex:0xE8F2EA),Color(hex:0xCFE4D4)] : [Color(hex:0xF6EFE4),Color(hex:0xE8D9C4)],startPoint:.leading,endPoint:.trailing),in:RoundedRectangle(cornerRadius:16))
                    }.buttonStyle(.plain).contextMenu {
                        Button("Delete",role:.destructive) {do {try store.remove(file)} catch {self.error = error.localizedDescription}}
                    }
                }
            }.padding(12)
        }.foregroundStyle(CortexStyle.ink).background(CortexStyle.background)
            .cortexToolbar(kind) {
                Button {if kind == "PDFs" {importing = true} else {creating = true}} label: {Image(systemName:"plus").frame(width:40,height:48)}.accessibilityLabel(kind == "PDFs" ? "Import PDF" : "New notebook")
            }
            .consumerTabs("home")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
                do { try store.importPDF(result.get()) } catch { self.error = error.localizedDescription }
            }
            .sheet(isPresented: $creating) {
                VStack(alignment:.leading,spacing:16) {
                    Text("New notebook").font(CortexStyle.title(18))
                    TextField("Notebook title",text:$title).font(.custom("AveriaSerifLibre-Regular",size:16)).padding(12)
                        .background(CortexStyle.background,in:RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(CortexStyle.line,lineWidth:1))
                    Toggle("8 mm ruled paper",isOn:$ruled).font(CortexStyle.title(16)).tint(CortexStyle.ink)
                    HStack(spacing:10) {
                        Button("Cancel") {creating = false}.buttonStyle(ConsumerButtonStyle(outlined:true))
                        Button("Create") {do {try store.create(title:title,ruled:ruled);title = "";creating = false} catch {self.error = error.localizedDescription}}.buttonStyle(ConsumerButtonStyle())
                    }
                }.foregroundStyle(CortexStyle.ink).padding(22).presentationDetents([.medium])
            }
            .alert("Paper library", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}

@MainActor
final class PaperController: NSObject, ObservableObject, @preconcurrency PDFPageOverlayViewProvider, PKCanvasViewDelegate {
    let view = PDFView()
    let file: PaperFile
    private let store: PaperLibrary
    let ink = CortexInkSettings()
    private var canvases: [Int: PKCanvasView] = [:]
    private var inkAnnotations:[Int:ConsumerInkAnnotation] = [:]
    private var pendingSaves: [Int: Task<Void, Never>] = [:]
    @Published var error: String?
    init(file: PaperFile, store: PaperLibrary? = nil) {
        self.file = file
        self.store = store ?? .shared
        super.init()
        ink.onChange = { [weak self] in self?.updateTools() }
        view.autoScales = true
        view.displayDirection = .vertical
        view.displayMode = .singlePageContinuous
        view.pageOverlayViewProvider = self
        reload()
    }
    func reload() {
        let oldIndex = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
        canvases.keys.forEach {saveCanvas($0)}
        canvases.removeAll();inkAnnotations.removeAll()
        view.document = PDFDocument(url: store.url(file))
        if let page = view.document?.page(at: min(oldIndex, max(0, (view.document?.pageCount ?? 1) - 1))) { view.go(to: page) }
    }
    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let document = view.document else { return nil }
        let index = document.index(for: page)
        if let canvas = canvases[index] { return canvas }
        let canvas = PKCanvasView(frame: page.bounds(for: .mediaBox))
        canvas.backgroundColor = .clear; canvas.isOpaque = false
        canvas.isScrollEnabled = false; canvas.drawingPolicy = .anyInput
        canvas.tool = ink.tool
        canvas.overrideUserInterfaceStyle = .light
        if let data = try? Data(contentsOf: store.drawingURL(file, page: index)), let drawing = try? PKDrawing(data: data) { canvas.drawing = drawing }
        canvas.delegate = self
        canvas.isUserInteractionEnabled = ink.drawing
        canvases[index] = canvas
        renderInk(index)
        return canvas
    }
    func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        DispatchQueue.main.async { [weak self] in self?.updateTools() }
    }
    func canvasViewDidEndUsingTool(_ canvasView:PKCanvasView) {
        if ink.mode == .underliner {canvasView.drawing = ConsumerInkRenderer.straightenLastStroke(canvasView.drawing)}
    }
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard let index = canvases.first(where: { $0.value === canvasView })?.key else { return }
        renderInk(index)
        pendingSaves[index]?.cancel()
        pendingSaves[index] = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            self?.saveCanvas(index)
        }
    }
    private func renderInk(_ index:Int) {
        guard let page = view.document?.page(at:index),let canvas = canvases[index] else {return}
        if let old = inkAnnotations[index] {page.removeAnnotation(old)}
        let annotation = ConsumerInkAnnotation(bounds:page.bounds(for:.mediaBox),forType:.ink,withProperties:nil)
        annotation.drawing = canvas.drawing;annotation.marksVisible = ink.visible
        annotation.shouldDisplay = true;annotation.shouldPrint = true
        inkAnnotations[index] = annotation;page.addAnnotation(annotation)
    }
    private func saveCanvas(_ index: Int) {
        guard let canvas = canvases[index] else { return }
        do { try canvas.drawing.dataRepresentation().write(to: store.drawingURL(file, page: index), options: [.atomic, .completeFileProtection]) }
        catch { self.error = "The pen marks could not be saved. Keep this page open and try again." }
    }
    private func updateTools() {
        view.isInMarkupMode = ink.drawing
        for canvas in canvases.values {
            canvas.isUserInteractionEnabled = ink.drawing
            canvas.tool = ink.tool
            canvas.drawingPolicy = ink.stylusOnly ? .pencilOnly : .anyInput
            canvas.alpha = 0.02
        }
        canvases.keys.forEach {renderInk($0)}
        if ink.drawing, let current = view.currentPage, let index = view.document?.index(for: current), let canvas = canvases[index] { canvas.becomeFirstResponder() }
        else { canvases.values.forEach { $0.resignFirstResponder() } }
    }
    func clearInk() { activeCanvas?.drawing = PKDrawing() }
    func undo() { activeCanvas?.undoManager?.undo() }
    func redo() { activeCanvas?.undoManager?.redo() }
    private var activeCanvas: PKCanvasView? {
        guard let page = view.currentPage, let index = view.document?.index(for: page) else { return nil }
        return canvases[index]
    }
    func export() throws -> URL {
        guard let document = view.document else { throw StudyAIError.message("The document could not be opened.") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(file.id.uuidString + "-annotated.pdf")
        inkAnnotations.values.forEach {$0.marksVisible = false}
        defer {inkAnnotations.values.forEach {$0.marksVisible = ink.visible}}
        let firstBounds = document.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: firstBounds).pdfData { context in
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: 0, y: bounds.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: context.cgContext)
                context.cgContext.restoreGState()
                let drawing = canvases[index]?.drawing ?? (try? Data(contentsOf: store.drawingURL(file, page: index))).flatMap { try? PKDrawing(data: $0) }
                if let drawing {ConsumerInkRenderer.draw(drawing,in:context.cgContext)}
            }
        }
        try data.write(to: output, options: [.atomic, .completeFileProtection])
        return output
    }
    func stop() {
        pendingSaves.values.forEach { $0.cancel() }
        pendingSaves = [:]
        canvases.keys.forEach { saveCanvas($0) }
        ink.drawing = false; canvases.values.forEach { $0.delegate = nil }; view.pageOverlayViewProvider = nil }
}
private struct PaperPDFView: UIViewRepresentable {
    @ObservedObject var controller: PaperController
    func makeUIView(context: Context) -> PDFView { controller.view }
    func updateUIView(_ uiView: PDFView, context: Context) { }
    static func dismantleUIView(_ uiView: PDFView, coordinator: ()) { (uiView.pageOverlayViewProvider as? PaperController)?.stop() }
}
struct PaperReader: View {
    let file: PaperFile
    @StateObject private var controller: PaperController
    @State private var exportURL: URL?
    @State private var importingImage = false
    init(file: PaperFile) { self.file = file; _controller = StateObject(wrappedValue: PaperController(file: file)) }
    var body: some View {
        PaperPDFView(controller: controller)
            .cortexToolbar(file.title) {
                if file.kind == "Notebooks" {
                    Button { importingImage = true } label: { Label("Add image page", systemImage: "photo.badge.plus") }
                    Button { do { try PaperLibrary.shared.appendPage(file); controller.reload() } catch { controller.error = error.localizedDescription } } label: { Label("Add page", systemImage: "doc.badge.plus") }
                }
                Button { do { exportURL = try controller.export() } catch { controller.error = error.localizedDescription } } label: { Label("Export annotated PDF", systemImage: "square.and.arrow.up") }
            }
            .safeAreaInset(edge:.bottom,spacing:0) { CortexInkToolbar(settings:controller.ink,undo:controller.undo,redo:controller.redo,clear:controller.clearInk) }
            .fileImporter(isPresented: $importingImage, allowedContentTypes: [.image]) { result in
                do { try PaperLibrary.shared.appendImage(file, source: result.get()); controller.reload() }
                catch { controller.error = error.localizedDescription }
            }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                if let exportURL { ShareSheet(items: [exportURL]) }
            }
            .alert("Paper", isPresented: Binding(get: { controller.error != nil }, set: { if !$0 { controller.error = nil } })) { Button("OK") { controller.error = nil } } message: { Text(controller.error ?? "") }
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
