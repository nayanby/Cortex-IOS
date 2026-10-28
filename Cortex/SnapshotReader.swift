import SwiftUI
import WebKit
import PencilKit
import PDFKit

@MainActor
final class SnapshotController: NSObject, ObservableObject, WKNavigationDelegate, PKCanvasViewDelegate {
    let webView = WKWebView(frame:.zero,configuration:WKWebViewConfiguration())
    let canvas = ConsumerInputCanvas(frame:.zero)
    let ink = CortexInkSettings()
    @Published private(set) var isLoading = true
    @Published var error: String?
    private let entry: StudyEntry
    private var observation: NSKeyValueObservation?
    private var task: Task<Void,Never>?
    private var saveTask: Task<Void,Never>?
    private var renderTask:Task<Void,Never>?
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
        canvas.widthScale = 4.0/3.0
        canvas.onInkChange = {[weak self] in self?.canvasViewDrawingDidChange($0)}
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
                try Task.checkCancellation(); resizeCanvas(); isLoading = false; renderInk()
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
        let zoom = max(0.01,webView.scrollView.zoomScale)
        canvas.transform = .identity
        canvas.bounds = CGRect(origin:.zero,size:CGSize(width:webView.scrollView.contentSize.width/zoom,height:webView.scrollView.contentSize.height/zoom))
        canvas.center = CGPoint(x:webView.scrollView.contentSize.width/2,y:webView.scrollView.contentSize.height/2)
        canvas.transform = CGAffineTransform(scaleX:zoom,y:zoom)
        canvas.contentScaleFactor = (webView.window?.screen.scale ?? UIScreen.main.scale)*zoom
        webView.scrollView.bringSubviewToFront(canvas)
    }
    private func updateTools() {
        canvas.markingMode = ink.mode;canvas.configureInput()
        canvas.tool = ink.tool; canvas.drawingPolicy = ink.stylusOnly ? .pencilOnly : .anyInput
        canvas.isUserInteractionEnabled = ink.drawing; canvas.alpha = 0.02
        renderInk()
        webView.scrollView.panGestureRecognizer.isEnabled = !ink.drawing || ink.stylusOnly
        if ink.drawing { canvas.becomeFirstResponder() } else { canvas.resignFirstResponder() }
    }
    private func renderInk() {
        guard !isLoading else {return}
        renderTask?.cancel()
        let payload = ConsumerInkRenderer.webPayload(ink.visible ? canvas.drawing : PKDrawing())
        renderTask = Task { [weak self] in
            guard let self,!Task.isCancelled else {return}
            _ = try? await webView.callAsyncJavaScript("window.cortexRenderInk(strokes);",arguments:["strokes":payload],in:nil,contentWorld:.page)
        }
    }
    func canvasViewDidEndUsingTool(_ canvasView:PKCanvasView) {
        if ink.mode == .underliner {canvasView.drawing = ConsumerInkRenderer.straightenLastStroke(canvasView.drawing)}
    }
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        renderInk()
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
    func undo() { canvas.history.undo() }
    func redo() { canvas.history.redo() }
    func clearInk() { canvas.clearMarks() }
    func exportPDF() async throws -> URL {
        await renderTask?.value
        let geometry = try await webView.callAsyncJavaScript("const p=document.getElementById('paper'); return {x:p.offsetLeft,width:p.offsetWidth,height:document.documentElement.scrollHeight};",arguments:[:],in:nil,contentWorld:.page) as? [String:Double]
        guard let geometry else { throw StudyAIError.message("The Snapshot could not be prepared for export.") }
        let x = CGFloat(geometry["x"] ?? 0), width = CGFloat(geometry["width"] ?? 680), height = CGFloat(geometry["height"] ?? 1)
        guard width > 0, height > 0 else { throw StudyAIError.message("The Snapshot is empty.") }
        let configuration = WKPDFConfiguration(); configuration.rect = CGRect(x:x,y:0,width:width,height:height)
        let data = try await webView.pdf(configuration:configuration)
        guard let page = PDFDocument(data:data)?.page(at:0) else { throw StudyAIError.message("The Snapshot PDF could not be created.") }
        let bounds = CGRect(x:0,y:0,width:595.28,height:841.89), margin: CGFloat = 28
        let scale = (bounds.width - 2 * margin) / width, tileHeight = (bounds.height - 2 * margin) / scale
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
                // The WebKit PDF already includes the SVG ink at vector resolution.
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
        task?.cancel(); renderTask?.cancel(); saveTask?.cancel(); saveInk(); observation?.invalidate(); observation = nil
        webView.stopLoading(); webView.navigationDelegate = nil; canvas.delegate = nil;canvas.onInkChange = nil; ink.onChange = nil
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
        }
            .safeAreaInset(edge:.bottom,spacing:0) { CortexInkToolbar(settings:controller.ink,undo:controller.undo,redo:controller.redo,clear:controller.clearInk) }
            .cortexToolbar("Snapshots") {
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
            .navigationDestination(isPresented:$makeNew) { CreateStudyView(note:note,initialSource:(entry.content.sections ?? []).map(SlideExport.body).joined(separator:"\n\n"),initialKind:"Snapshots") }
            .sheet(isPresented:$fonts) {
                ConsumerTypeSettings(delta:$delta,line:$line,paragraph:$paragraph,defaultLine:1.375)
            }
            .onChange(of:delta) { _,_ in controller.applyType() }
            .onChange(of:line) { _,_ in controller.applyType() }
            .onChange(of:paragraph) { _,_ in controller.applyType() }
            .sheet(isPresented:Binding(get:{exportURL != nil},set:{if !$0 { exportURL = nil }})) { if let exportURL { ShareSheet(items:[exportURL]) } }
            .alert("Snapshot",isPresented:Binding(get:{controller.error != nil},set:{if !$0 { controller.error = nil }})) { Button("OK") { controller.error = nil } } message: { Text(controller.error ?? "") }
            .onAppear { delta = min(12,max(-1,delta.rounded())); StudyProgress.shared.opened(entry) }
    }
}
