import SwiftUI
import WebKit
import PencilKit
import PDFKit

@MainActor
final class SnapshotController: NSObject, ObservableObject, WKNavigationDelegate, PKCanvasViewDelegate {
    let webView = WKWebView(frame:.zero,configuration:WKWebViewConfiguration())
    let canvas = PKCanvasView()
    let ink = CortexInkSettings()
    @Published private(set) var isLoading = true
    @Published var error: String?
    private let entry: StudyEntry
    private var observation: NSKeyValueObservation?
    private var task: Task<Void,Never>?
    private var saveTask: Task<Void,Never>?
    private let drawingURL: URL
    init(entry: StudyEntry) {
        self.entry = entry
        let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("SnapshotInk",isDirectory:true)
        drawingURL = directory.appendingPathComponent(SharedDocumentCache.identifier(for:entry.id).uuidString + ".drawing")
        super.init()
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        webView.navigationDelegate = self
        webView.isOpaque = false; webView.backgroundColor = .white
        canvas.backgroundColor = .clear; canvas.isOpaque = false; canvas.isScrollEnabled = false
        canvas.overrideUserInterfaceStyle = .light
        if let data = try? Data(contentsOf:drawingURL), let drawing = try? PKDrawing(data:data) { canvas.drawing = drawing }
        canvas.delegate = self
        webView.scrollView.addSubview(canvas)
        ink.onChange = { [weak self] in self?.updateTools() }
        observation = webView.scrollView.observe(\.contentSize,options:[.new]) { [weak self] _, _ in
            Task { @MainActor in self?.resizeCanvas() }
        }
        updateTools()
    }
    func load() {
        guard let page = Bundle.main.url(forResource:"snapshot",withExtension:"html",subdirectory:"Reader") else { error = "The Snapshot reader is missing."; isLoading = false; return }
        webView.loadFileURL(page,allowingReadAccessTo:page.deletingLastPathComponent())
    }
    func webView(_ view: WKWebView,didFinish navigation: WKNavigation!) {
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try JSONSerialization.jsonObject(with:JSONEncoder().encode(entry.content))
                _ = try await view.callAsyncJavaScript("return await window.cortexLoadSnapshot(data, type);",arguments:["data":data,"type":typeArguments()],in:nil,contentWorld:.page)
                try Task.checkCancellation(); resizeCanvas(); isLoading = false
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription; isLoading = false }
        }
    }
    func typeArguments() -> [String:Double] {
        let defaults = UserDefaults.standard
        return ["delta":defaults.double(forKey:"snapshot.fontDelta"),"line":defaults.object(forKey:"snapshot.line") as? Double ?? 1.375,"paragraph":defaults.object(forKey:"snapshot.paragraph") as? Double ?? 0.16]
    }
    func applyType() {
        Task {
            let values = typeArguments()
            _ = try? await webView.callAsyncJavaScript("return await window.cortexSnapshotType(delta,line,paragraph);",arguments:values,in:nil,contentWorld:.page)
            resizeCanvas()
        }
    }
    private func resizeCanvas() {
        canvas.frame = CGRect(origin:.zero,size:webView.scrollView.contentSize)
        webView.scrollView.bringSubviewToFront(canvas)
    }
    private func updateTools() {
        canvas.tool = ink.tool; canvas.drawingPolicy = ink.stylusOnly ? .pencilOnly : .anyInput
        canvas.isUserInteractionEnabled = ink.drawing; canvas.alpha = ink.visible ? 1 : 0
        webView.scrollView.panGestureRecognizer.isEnabled = !ink.drawing || ink.stylusOnly
        if ink.drawing { canvas.becomeFirstResponder() } else { canvas.resignFirstResponder() }
    }
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:250_000_000) } catch { return }
            self?.saveInk()
        }
    }
    private func saveInk() {
        do { try canvas.drawing.dataRepresentation().write(to:drawingURL,options:[.atomic,.completeFileProtection]) }
        catch { self.error = "The Snapshot ink could not be saved." }
    }
    func undo() { canvas.undoManager?.undo() }
    func redo() { canvas.undoManager?.redo() }
    func clearInk() { canvas.drawing = PKDrawing() }
    func exportPDF() async throws -> URL {
        let geometry = try await webView.callAsyncJavaScript("const p=document.getElementById('paper'); return {x:p.offsetLeft,width:p.offsetWidth,height:document.documentElement.scrollHeight};",arguments:[:],in:nil,contentWorld:.page) as? [String:Double]
        guard let geometry else { throw StudyAIError.message("The Snapshot could not be prepared for export.") }
        let x = CGFloat(geometry["x"] ?? 0), width = CGFloat(geometry["width"] ?? 680), height = CGFloat(geometry["height"] ?? 1)
        guard width > 0, height > 0 else { throw StudyAIError.message("The Snapshot is empty.") }
        let configuration = WKPDFConfiguration(); configuration.rect = CGRect(x:x,y:0,width:width,height:height)
        let data = try await webView.pdf(configuration:configuration)
        guard let page = PDFDocument(data:data)?.page(at:0) else { throw StudyAIError.message("The Snapshot PDF could not be created.") }
        let bounds = CGRect(x:0,y:0,width:595.28,height:841.89), margin: CGFloat = 28
        let scale = (bounds.width - 2 * margin) / width, tileHeight = (bounds.height - 2 * margin) / scale
        let drawing = canvas.drawing
        let result = UIGraphicsPDFRenderer(bounds:bounds).pdfData { context in
            var top: CGFloat = 0
            while top < height {
                let length = min(tileHeight,height-top)
                context.beginPage()
                context.cgContext.saveGState()
                context.cgContext.translateBy(x:margin,y:margin); context.cgContext.scaleBy(x:scale,y:scale)
                context.cgContext.clip(to:CGRect(x:0,y:0,width:width,height:length))
                context.cgContext.translateBy(x:0,y:-top + page.bounds(for:.mediaBox).height)
                context.cgContext.scaleBy(x:1,y:-1); page.draw(with:.mediaBox,to:context.cgContext)
                context.cgContext.restoreGState()
                if !drawing.strokes.isEmpty { drawing.image(from:CGRect(x:x,y:top,width:width,height:length),scale:2).draw(in:CGRect(x:margin,y:margin,width:width*scale,height:length*scale)) }
                top += tileHeight
            }
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-snapshot.pdf")
        try result.write(to:output,options:[.atomic,.completeFileProtection]); return output
    }
    func webView(_ view: WKWebView,decidePolicyFor action: WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        let allowed = Bundle.main.url(forResource:"snapshot",withExtension:"html",subdirectory:"Reader")
        decisionHandler(action.request.url?.standardizedFileURL == allowed?.standardizedFileURL ? .allow : .cancel)
    }
    func webView(_ view: WKWebView,didFailProvisionalNavigation navigation: WKNavigation!,withError error:Error) { self.error = error.localizedDescription; isLoading = false }
    func stop() {
        task?.cancel(); saveTask?.cancel(); saveInk(); observation?.invalidate(); observation = nil
        webView.stopLoading(); webView.navigationDelegate = nil; canvas.delegate = nil; ink.onChange = nil
    }
}
private extension WKWebView {
    func pdf(configuration:WKPDFConfiguration) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in createPDF(configuration:configuration) { continuation.resume(with:$0) } }
    }
}
private struct SnapshotWebView: UIViewRepresentable {
    let controller: SnapshotController
    func makeUIView(context:Context) -> WKWebView { controller.load(); return controller.webView }
    func updateUIView(_ view:WKWebView,context:Context) { }
    static func dismantleUIView(_ view:WKWebView,coordinator:()) { (view.navigationDelegate as? SnapshotController)?.stop() }
}
struct SnapshotReader: View {
    let entry: StudyEntry
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var controller: SnapshotController
    @State private var fonts = false
    @State private var makeNew = false
    @State private var exportURL: URL?
    @State private var exporting = false
    @AppStorage("snapshot.fontDelta") private var delta = 0.0
    @AppStorage("snapshot.line") private var line = 1.375
    @AppStorage("snapshot.paragraph") private var paragraph = 0.16
    init(entry:StudyEntry) { self.entry = entry; _controller = StateObject(wrappedValue:SnapshotController(entry:entry)) }
    private var note: LibraryNote? { library.catalog?.notes.first { $0.subject.caseInsensitiveCompare(entry.folder) == .orderedSame && $0.displayName.caseInsensitiveCompare(entry.document) == .orderedSame } }
    var body: some View {
        ZStack {
            SnapshotWebView(controller:controller)
            if controller.isLoading || exporting { ProgressView(exporting ? "Preparing PDF…" : "Opening Snapshot…").padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:14)) }
        }.navigationTitle("Snapshots").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)
            .safeAreaInset(edge:.bottom,spacing:0) { CortexInkToolbar(settings:controller.ink,undo:controller.undo,redo:controller.redo,clear:controller.clearInk) }
            .toolbar {
                Button("Aa") { fonts = true }.accessibilityLabel("Font settings")
                if let note { NavigationLink { SharedNoteView(note:note) } label: { Image(systemName:"book") }.accessibilityLabel("Deep dive") }
                Menu {
                    Button("Make New") { makeNew = true }
                    Button("Share as PDF") {
                        exporting = true
                        Task { do { exportURL = try await controller.exportPDF() } catch { controller.error = error.localizedDescription }; exporting = false }
                    }.disabled(controller.isLoading || exporting)
                } label: { Image(systemName:"ellipsis") }.accessibilityLabel("Snapshot menu")
            }
            .navigationDestination(isPresented:$makeNew) { CreateStudyView(note:note,initialSource:(entry.content.sections ?? []).map(SlideExport.body).joined(separator:"\n\n")) }
            .sheet(isPresented:$fonts) {
                NavigationStack {
                    Form {
                        Stepper("Font size: \(delta,specifier:"%+.2f") pt",value:$delta,in:-1.5...1.5,step:0.25)
                        Stepper("Line spacing: \(line,specifier:"%.2f")",value:$line,in:1...2,step:0.0625)
                        Picker("Paragraph spacing",selection:$paragraph) {
                            ForEach([0.08,0.11313708498984761,0.16,0.22627416997969524,0.32],id:\.self) { Text($0.formatted(.number.precision(.fractionLength(2)))).tag($0) }
                        }
                        Button("Reset to default") { delta = 0; line = 1.375; paragraph = 0.16 }
                    }.navigationTitle("Font settings").toolbar { Button("Done") { fonts = false } }
                }.presentationDetents([.medium])
            }
            .onChange(of:delta) { _,_ in controller.applyType() }
            .onChange(of:line) { _,_ in controller.applyType() }
            .onChange(of:paragraph) { _,_ in controller.applyType() }
            .sheet(isPresented:Binding(get:{exportURL != nil},set:{if !$0 { exportURL = nil }})) { if let exportURL { ShareSheet(items:[exportURL]) } }
            .alert("Snapshot",isPresented:Binding(get:{controller.error != nil},set:{if !$0 { controller.error = nil }})) { Button("OK") { controller.error = nil } } message: { Text(controller.error ?? "") }
            .onAppear { StudyProgress.shared.opened(entry) }
    }
}
