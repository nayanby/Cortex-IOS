import SwiftUI
import WebKit

struct ReaderBookmark: Identifiable, Codable {
    let id: UUID
    let title: String
    let fraction: Double
}

struct ReaderHeading: Identifiable {
    let id: Int
    let text: String
    let level: Int
}

@MainActor
final class ReaderController: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var headings: [ReaderHeading] = []
    @Published var bookmarks: [ReaderBookmark] = []
    @Published var annotationMessage: String?
    let webView: WKWebView
    private let fileURL: URL
    private let progressKey: String
    private var loadTask: Task<Void, Never>?

    init(fileURL: URL, documentID: UUID) {
        self.fileURL = fileURL
        progressKey = "reading.\(documentID.uuidString)"
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        if let data = UserDefaults.standard.data(forKey: progressKey + ".bookmarks"), let saved = try? JSONDecoder().decode([ReaderBookmark].self, from: data) { bookmarks = saved }
        webView.navigationDelegate = self
        // WKWebView copies its configuration. Register on the actual controller,
        // rather than lazily creating one on the original configuration copy.
        webView.configuration.userContentController.add(self, name: "readingProgress")
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
    }

    func load() {
        guard let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Reader") else {
            fail("The document reader is missing from this build.")
            return
        }
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = fileURL
                let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
                try Task.checkCancellation()
                let result = try await webView.callAsyncJavaScript(
                    "return await window.cortexLoadDocument(base64, position, typography);",
                    arguments: ["base64": data.base64EncodedString(), "position": UserDefaults.standard.double(forKey: progressKey),
                                "typography": typographyArguments()],
                    in: nil, contentWorld: .page)
                try Task.checkCancellation()
                headings = (result as? [[String: Any]] ?? []).compactMap { item in
                    guard let index = item["index"] as? Int, let text = item["text"] as? String,
                          let level = item["level"] as? Int else { return nil }
                    return ReaderHeading(id: index, text: text, level: level)
                }
                if let data = UserDefaults.standard.data(forKey: progressKey + ".highlights"),
                   let records = try? JSONSerialization.jsonObject(with: data) {
                    _ = try? await webView.callAsyncJavaScript("return window.cortexApplyHighlights(records);", arguments: ["records": records], in: nil, contentWorld: .page)
                }
                isLoading = false
            } catch is CancellationError { }
            catch { fail("Could not open this Word document. \(error.localizedDescription)") }
        }
    }

    func highlight(color: String) {
        Task {
            guard let result = try? await webView.callAsyncJavaScript("return window.cortexHighlightSelection(color);", arguments: ["color": color], in: nil, contentWorld: .page),
                  let records = result as? [[String: Any]], let data = try? JSONSerialization.data(withJSONObject: records) else {
                annotationMessage = "Select text in the note first, then choose a highlight color."
                return
            }
            UserDefaults.standard.set(data, forKey: progressKey + ".highlights")
        }
    }
    func clearHighlights() {
        UserDefaults.standard.removeObject(forKey: progressKey + ".highlights")
        Task { _ = try? await webView.callAsyncJavaScript("return window.cortexApplyHighlights([]);", arguments: [:], in: nil, contentWorld: .page) }
    }
    func addBookmark() {
        Task {
            guard let fraction = try? await webView.evaluateJavaScript("window.cortexReadingProgress()") as? Double else { return }
            let title = (try? await webView.evaluateJavaScript("document.elementFromPoint(innerWidth / 2, 100)?.closest('.doc-p')?.textContent || 'Reading position'")) as? String ?? "Reading position"
            bookmarks.append(ReaderBookmark(id: UUID(), title: String(title.prefix(100)), fraction: fraction))
            saveBookmarks()
        }
    }
    func removeBookmarks(at offsets: IndexSet) { bookmarks.remove(atOffsets: offsets); saveBookmarks() }
    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) { UserDefaults.standard.set(data, forKey: progressKey + ".bookmarks") }
    }
    func jump(to bookmark: ReaderBookmark) {
        Task { _ = try? await webView.callAsyncJavaScript("window.cortexRestoreProgress(fraction);", arguments: ["fraction": bookmark.fraction], in: nil, contentWorld: .page) }
    }

    private func typographyArguments() -> [String: Double] {
        let defaults = UserDefaults.standard
        return ["delta": defaults.double(forKey: "reader.fontDelta"),
                "line": defaults.object(forKey: "reader.line") as? Double ?? 1.4375,
                "paragraph": defaults.object(forKey: "reader.paragraph") as? Double ?? 0.16]
    }

    func applyTypography() {
        let arguments = typographyArguments()
        Task {
            _ = try? await webView.callAsyncJavaScript("return window.cortexSetTypography(delta, line, paragraph);",
                arguments: arguments, in: nil, contentWorld: .page)
        }
    }

    func jump(to heading: ReaderHeading) {
        Task {
            _ = try? await webView.callAsyncJavaScript("return window.cortexJumpToHeading(index);",
                arguments: ["index": heading.id], in: nil, contentWorld: .page)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.name == "readingProgress",
              let fraction = message.body as? Double, fraction.isFinite else { return }
        UserDefaults.standard.set(min(1, max(0, fraction)), forKey: progressKey)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url,
              let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Reader"),
              url.isFileURL, url.standardizedFileURL.path == page.standardizedFileURL.path else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("The reader stopped. Reopen this note to continue.")
    }
    func stop() {
        loadTask?.cancel()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "readingProgress")
        webView.navigationDelegate = nil
    }
    private func fail(_ message: String) { isLoading = false; errorMessage = message }
}

struct ReaderWebView: UIViewRepresentable {
    let controller: ReaderController
    func makeUIView(context: Context) -> WKWebView { controller.load(); return controller.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        (uiView.navigationDelegate as? ReaderController)?.stop()
    }
}

private final class NotePrintRenderer: UIPrintPageRenderer {
    override var paperRect: CGRect { CGRect(x: 0, y: 0, width: 595.28, height: 841.89) }
    override var printableRect: CGRect { paperRect.insetBy(dx: 28, dy: 28) }
}

struct DocumentReader: View {
    let document: LocalDocument
    let fileURL: URL
    let allowsSharing: Bool
    let note: LibraryNote?
    @StateObject private var controller: ReaderController
    @StateObject private var audio: AudiobookController
    @State private var showingOutline = false
    @State private var showingFonts = false
    @State private var studyKind: String?
    @State private var showingCreate = false
    @State private var sourceText = ""
    @State private var showingAudio = false
    @State private var showingBookmarks = false
    @State private var annotatedCopy: PaperFile?
    @AppStorage("reader.fontDelta") private var fontDelta = 0.0
    @AppStorage("reader.line") private var line = 1.4375
    @AppStorage("reader.paragraph") private var paragraph = 0.16

    init(document: LocalDocument, fileURL: URL, allowsSharing: Bool = true, note: LibraryNote? = nil) {
        self.document = document
        self.fileURL = fileURL
        self.allowsSharing = allowsSharing
        self.note = note
        _controller = StateObject(wrappedValue: ReaderController(fileURL: fileURL, documentID: document.id))
        _audio = StateObject(wrappedValue: AudiobookController(documentID: document.id))
    }

    var body: some View {
        ZStack {
            ReaderWebView(controller: controller)
            if controller.isLoading {
                ProgressView("Opening note…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            if let error = controller.errorMessage {
                ContentUnavailableView("Could not open note", systemImage: "doc.badge.ellipsis", description: Text(error))
                    .background(.white)
            }
        }
        .navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Highlight selected text · rose") { controller.highlight(color: "rose") }
                    Button("Highlight selected text · lemon") { controller.highlight(color: "lemon") }
                    Button("Highlight selected text · aqua") { controller.highlight(color: "aqua") }
                    Button("Clear highlights", role: .destructive) { controller.clearHighlights() }
                    Button("Write on a PDF copy") { openPaperCopy() }
                        .disabled(controller.isLoading || controller.errorMessage != nil)
                    Button("Add bookmark") { controller.addBookmark() }
                    Button("Bookmarks") { showingBookmarks = true }
                } label: { Label("Annotations", systemImage: "highlighter") }
                Button { showingFonts = true } label: { Label("Font settings", systemImage: "textformat.size") }
                Menu {
                    ForEach(["Snapshots", "Flashcards", "Qbank", "Slides"], id: \.self) { kind in
                        Button(kind) { studyKind = kind }
                    }
                    Button("Read aloud") {
                        Task {
                            let text = (try? await controller.webView.evaluateJavaScript("document.getElementById('paper').innerText")) as? String ?? ""
                            audio.prepare(text); showingAudio = true
                        }
                    }.disabled(controller.isLoading || controller.errorMessage != nil)
                    Button("Create with AI") {
                        Task {
                            sourceText = (try? await controller.webView.evaluateJavaScript("getSelection()?.toString().trim() || document.getElementById('paper').innerText")) as? String ?? ""
                            showingCreate = true
                        }
                    }.disabled(controller.isLoading || controller.errorMessage != nil)
                } label: { Label("Study tools", systemImage: "rectangle.stack") }
                if allowsSharing {
                    ShareLink(item: fileURL) { Label("Share Word document", systemImage: "square.and.arrow.up") }
                }
                Button { showingOutline = true } label: { Label("Outline", systemImage: "list.bullet") }
                    .disabled(controller.headings.isEmpty)
            }
        }
        .onAppear { fontDelta = min(12,max(-1,fontDelta.rounded())) }
        .onChange(of: fontDelta) { _, _ in controller.applyTypography() }
        .onChange(of: line) { _, _ in controller.applyTypography() }
        .onChange(of: paragraph) { _, _ in controller.applyTypography() }
        .alert("Highlights", isPresented: Binding(get: { controller.annotationMessage != nil }, set: { if !$0 { controller.annotationMessage = nil } })) { Button("OK") { controller.annotationMessage = nil } } message: { Text(controller.annotationMessage ?? "") }
        .navigationDestination(isPresented: Binding(get: { annotatedCopy != nil }, set: { if !$0 { annotatedCopy = nil } })) {
            if let file = annotatedCopy { PaperReader(file: file) }
        }
        .sheet(isPresented: $showingBookmarks) {
            NavigationStack {
                List {
                    if controller.bookmarks.isEmpty { Text("No bookmarks yet. Use Add bookmark to save this reading position.") }
                    ForEach(controller.bookmarks) { bookmark in
                        Button(bookmark.title) { controller.jump(to: bookmark); showingBookmarks = false }
                    }.onDelete(perform: controller.removeBookmarks)
                }.navigationTitle("Bookmarks").toolbar { Button("Done") { showingBookmarks = false } }
            }
        }
        .onDisappear { audio.stop() }
        .sheet(isPresented: $showingAudio) { AudiobookView(controller: audio) }
        .navigationDestination(isPresented: $showingCreate) { CreateStudyView(note: note, initialSource: sourceText) }
        .sheet(isPresented: $showingFonts) {
            NavigationStack {
                Form {
                    Stepper("Font size: \(12.25 + fontDelta, specifier: "%.2f") pt", value: $fontDelta, in: -1...12, step: 1)
                    Stepper("Line spacing: \(line, specifier: "%.2f")", value: $line, in: 1...2, step: 0.0625)
                    Picker("Paragraph spacing", selection: $paragraph) {
                        ForEach([0.08, 0.11313708498984761, 0.16, 0.22627416997969524, 0.32], id: \.self) { value in
                            Text(value.formatted(.number.precision(.fractionLength(2)))).tag(value)
                        }
                    }
                    Button("Reset to default") { fontDelta = 0; line = 1.4375; paragraph = 0.16 }
                }.navigationTitle("Font settings").toolbar { Button("Done") { showingFonts = false } }
            }.presentationDetents([.medium])
        }
        .navigationDestination(isPresented: Binding(get: { studyKind != nil }, set: { if !$0 { studyKind = nil } })) {
            StudyBrowser(kind: studyKind ?? "Snapshots", note: note)
        }
        .sheet(isPresented: $showingOutline) {
            NavigationStack {
                List(controller.headings) { heading in
                    Button { controller.jump(to: heading); showingOutline = false } label: {
                        Text(heading.text).font(CortexStyle.title(heading.level == 1 ? 17 : 15))
                            .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
                    }
                }
                .navigationTitle("Outline").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { showingOutline = false } }
            }.tint(CortexStyle.ink)
        }
    }
    private func openPaperCopy() {
        let library = PaperLibrary.shared
        if let saved = library.existing(id: document.id) { annotatedCopy = saved; return }
        let renderer = NotePrintRenderer()
        renderer.addPrintFormatter(controller.webView.viewPrintFormatter(), startingAtPageAt: 0)
        let count = renderer.numberOfPages
        guard count > 0 else { controller.annotationMessage = "The note could not be prepared for writing. Try reopening it."; return }
        let data = UIGraphicsPDFRenderer(bounds: renderer.paperRect).pdfData { context in
            for index in 0..<count { context.beginPage(); renderer.drawPage(at: index, in: renderer.paperRect) }
        }
        do { annotatedCopy = try library.saveRenderedPDF(data, title: document.title, id: document.id) }
        catch { controller.annotationMessage = error.localizedDescription }
    }

}
