import SwiftUI
import CoreText

struct SlideDeckView: View {
    let entry: StudyEntry
    @State private var index = 0
    @State private var exportURL: URL?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 10) {
            Text(entry.content.title ?? entry.title).font(CortexStyle.title(22)).padding(.horizontal)
            if let sections = entry.content.sections, !sections.isEmpty {
                TabView(selection: $index) {
                    ForEach(sections.indices, id: \.self) { number in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text(sections[number].heading ?? "").font(CortexStyle.title(30))
                                Text(.init(SlideExport.body(sections[number]))).font(.system(size: 22)).lineSpacing(8)
                            }.padding(28).frame(maxWidth: 960, alignment: .leading)
                        }.background(.white, in: RoundedRectangle(cornerRadius: 20)).padding(16).tag(number)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                HStack {
                    Button("Previous") { index = max(0, index - 1) }.disabled(index == 0)
                    Spacer(); Text("\(index + 1) / \(sections.count)"); Spacer()
                    Button("Next") { index = min(sections.count - 1, index + 1) }.disabled(index + 1 >= sections.count)
                }.padding()
            }
        }.background(CortexStyle.background).foregroundStyle(CortexStyle.ink)
            .navigationTitle("Slides").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .toolbar { Button { do { exportURL = try SlideExport.pdf(entry) } catch { self.error = error.localizedDescription } } label: { Label("Export slides as PDF", systemImage: "square.and.arrow.up") } }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) { if let exportURL { ShareSheet(items: [exportURL]) } }
            .alert("Slides", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}

enum SlideExport {
    static func body(_ section: SnapshotSection) -> String {
        var lines = (section.points ?? []).flatMap { point in ["• " + point.text] + (point.subpoints ?? []).map { "    – " + $0 } }
        lines += (section.numbered ?? []).enumerated().map { "\($0.offset + 1). " + $0.element }
        for group in section.groups ?? [] {
            if let heading = group.heading { lines.append(heading) }
            lines += (group.points ?? []).flatMap { ["• " + $0.text] + ($0.subpoints ?? []).map { "    – " + $0 } }
            lines += group.numbered ?? []
        }
        for table in section.tables ?? [] {
            if let title = table.title { lines.append(title) }
            if let headers = table.headers { lines.append(headers.joined(separator: " | ")) }
            lines += (table.rows ?? []).map { $0.joined(separator: " | ") }
        }
        return lines.joined(separator: "\n\n")
    }
    static func pdf(_ entry: StudyEntry) throws -> URL {
        guard let sections = entry.content.sections, !sections.isEmpty else { throw StudyAIError.message("No slides are available to export.") }
        let bounds = CGRect(x: 0, y: 0, width: 960, height: 540)
        var failed = false
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for (index, section) in sections.enumerated() {
                let text = body(section).replacingOccurrences(of: "**", with: "")
                let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 7
                let attributed = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor(red: 0.16, green: 0.15, blue: 0.39, alpha: 1), .paragraphStyle: paragraph])
                let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
                var offset = 0
                repeat {
                    context.beginPage()
                    UIColor.white.setFill(); context.cgContext.fill(bounds)
                    let heading = (section.heading ?? entry.title) + (offset > 0 ? " (continued)" : "")
                    (heading as NSString).draw(in: CGRect(x: 40, y: 28, width: 880, height: 92), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 30), .foregroundColor: UIColor.darkGray])
                    let path = CGPath(rect: CGRect(x: 40, y: 40, width: 880, height: 365), transform: nil)
                    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
                    context.cgContext.saveGState(); context.cgContext.translateBy(x: 0, y: bounds.height); context.cgContext.scaleBy(x: 1, y: -1)
                    CTFrameDraw(frame, context.cgContext); context.cgContext.restoreGState()
                    let visible = CTFrameGetVisibleStringRange(frame).length
                    ("\(index + 1) / \(sections.count)" as NSString).draw(at: CGPoint(x: 870, y: 510), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                    if visible == 0 && attributed.length > offset { failed = true; break }
                    offset += visible
                } while offset < attributed.length
            }
        }
        guard !failed else { throw StudyAIError.message("A slide could not be formatted for export.") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-slides.pdf")
        try data.write(to: output, options: [.atomic, .completeFileProtection])
        return output
    }
}
