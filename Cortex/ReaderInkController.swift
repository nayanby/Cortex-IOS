import WebKit
import PencilKit

@MainActor
final class ReaderInkController {
    let canvas = ConsumerInputCanvas(frame:.zero)
    let settings = CortexInkSettings()
    var onError:((String)->Void)?
    private weak var webView:WKWebView?
    private let file:URL
    private var observation:NSKeyValueObservation?
    private var saveTask:Task<Void,Never>?
    private var renderTask:Task<Void,Never>?
    private var ready = false
    init(webView:WKWebView,documentID:UUID) {
        self.webView = webView
        let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ReaderInk",isDirectory:true)
        file = directory.appendingPathComponent(documentID.uuidString+".drawing")
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        canvas.widthScale = 4.0/3.0;canvas.backgroundColor = .clear;canvas.isOpaque = false;canvas.isScrollEnabled = false
        canvas.overrideUserInterfaceStyle = .light
        if let data = try? Data(contentsOf:file),let drawing = try? PKDrawing(data:data) {canvas.drawing = drawing}
        canvas.onInkChange = {[weak self] _ in self?.changed()}
        settings.onChange = {[weak self] in self?.updateTools()}
        webView.scrollView.addSubview(canvas)
        observation = webView.scrollView.observe(\.contentSize,options:[.new]) {[weak self] _,_ in Task {@MainActor in self?.resize()}}
        updateTools()
    }
    func documentReady() {ready = true;resize();render()}
    private func resize() {
        guard let webView else {return}
        let zoom = max(0.01,webView.scrollView.zoomScale)
        canvas.transform = .identity
        canvas.bounds = CGRect(origin:.zero,size:CGSize(width:webView.scrollView.contentSize.width/zoom,height:webView.scrollView.contentSize.height/zoom))
        canvas.center = CGPoint(x:webView.scrollView.contentSize.width/2,y:webView.scrollView.contentSize.height/2)
        canvas.transform = CGAffineTransform(scaleX:zoom,y:zoom)
        webView.scrollView.bringSubviewToFront(canvas)
    }
    private func updateTools() {
        canvas.markingMode = settings.mode;canvas.tool = settings.tool;canvas.configureInput()
        canvas.drawingPolicy = settings.stylusOnly ? .pencilOnly : .anyInput
        canvas.isUserInteractionEnabled = settings.drawing && settings.visible;canvas.alpha = settings.visible ? 0.02 : 0
        webView?.scrollView.panGestureRecognizer.isEnabled = !settings.drawing || !settings.visible || settings.stylusOnly
        render()
    }
    func render() {
        guard ready,let webView else {return}
        renderTask?.cancel()
        let payload = ConsumerInkRenderer.webPayload(settings.visible ? canvas.drawing : PKDrawing())
        renderTask = Task {
            guard !Task.isCancelled else {return}
            _ = try? await webView.callAsyncJavaScript("window.cortexRenderInk(strokes);",arguments:["strokes":payload],in:nil,contentWorld:.page)
        }
    }
    private func changed() {
        render();saveTask?.cancel()
        saveTask = Task {[weak self] in
            do {try await Task.sleep(nanoseconds:250_000_000)} catch {return}
            self?.save()
        }
    }
    private func save() {
        do {try canvas.drawing.dataRepresentation().write(to:file,options:[.atomic,.completeFileProtection])}
        catch {onError?("The note’s pen marks could not be saved. Keep this note open and try again.")}
    }
    func undo() {canvas.history.undo()}
    func redo() {canvas.history.redo()}
    func clear() {canvas.clearMarks()}
    func stop() {
        saveTask?.cancel();renderTask?.cancel();save();observation?.invalidate();observation = nil
        canvas.onInkChange = nil;settings.onChange = nil
    }
}
