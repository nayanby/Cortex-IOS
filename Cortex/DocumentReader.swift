import SwiftUI
import WebKit

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
        webView.navigationDelegate = self
        configuration.userContentController.add(self, name: "readingProgress")
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
                    "return await window.cortexLoadDocument(base64, position);",
                    arguments: ["base64": data.base64EncodedString(), "position": UserDefaults.standard.double(forKey: progressKey)],
                    in: nil, contentWorld: .page)
                try Task.checkCancellation()
                headings = (result as? [[String: Any]] ?? []).compactMap { item in
                    guard let index = item["index"] as? Int, let text = item["text"] as? String,
                          let level = item["level"] as? Int else { return nil }
                    return ReaderHeading(id: index, text: text, level: level)
                }
                isLoading = false
            } catch is CancellationError { }
            catch { fail("Could not open this Word document. \(error.localizedDescription)") }
        }
    }

    func jump(to heading: ReaderHeading) {
        webView.callAsyncJavaScript("return window.cortexJumpToHeading(index);",
            arguments: ["index": heading.id], in: nil, contentWorld: .page, completionHandler: nil)
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

struct DocumentReader: View {
    let document: LocalDocument
    let fileURL: URL
    @StateObject private var controller: ReaderController
    @State private var showingOutline = false

    init(document: LocalDocument, fileURL: URL) {
        self.document = document
        self.fileURL = fileURL
        _controller = StateObject(wrappedValue: ReaderController(fileURL: fileURL, documentID: document.id))
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
                ShareLink(item: fileURL) { Label("Share Word document", systemImage: "square.and.arrow.up") }
                Button { showingOutline = true } label: { Label("Outline", systemImage: "list.bullet") }
                    .disabled(controller.headings.isEmpty)
            }
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
}
