import SwiftUI

struct UtilityView: View {
    let name: String
    var body: some View {
        switch name {
        case "PDFs", "Notebooks": PaperBrowser(kind: name)
        case "Performance": PerformanceView()
        case "Storage": StorageView()
        case "Account sign-in": ConsumerSignInView().navigationTitle("Account")
        default: HelpView()
        }
    }
}
struct StorageView: View {
    @ObservedObject private var studies = StudyLibrary.shared
    @ObservedObject private var paper = PaperLibrary.shared
    @State private var bundledBytes: Int64 = 0
    @State private var personalBytes: Int64 = 0
    var body: some View {
        List {
            Section("Local catalog") {
                LabeledContent("Notes", value: String(OfflineLibrary.catalog?.notes.count ?? 0))
                LabeledContent("Saved study sets", value: String(studies.entries.filter { !$0.id.hasPrefix("generated-") }.count))
                LabeledContent("Bundled content", value: ByteCountFormatter.string(fromByteCount: bundledBytes, countStyle: .file))
                Text(OfflineLibrary.available ? "The bundled catalog is used offline. No sign-in is required for these files." : "This build does not include a local content bundle.").font(.callout)
            }
            Section("Created and imported") {
                LabeledContent("AI creations", value: String(studies.entries.filter { $0.id.hasPrefix("generated-") }.count))
                LabeledContent("PDFs and notebooks", value: String(paper.files.count))
                LabeledContent("Saved app data", value: ByteCountFormatter.string(fromByteCount: personalBytes, countStyle: .file))
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).cortexPage("Storage")
            .task {
                let root = OfflineLibrary.root
                let personal = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                let result = await Task.detached {
                    func size(_ root: URL?) -> Int64 {
                        guard let root, let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
                        return files.compactMap { $0 as? URL }.reduce(Int64(0)) { sum, url in
                            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true else { return sum }
                            return sum + Int64(values.fileSize ?? 0)
                        }
                    }
                    return (size(root), size(personal))
                }.value
                bundledBytes = result.0; personalBytes = result.1
            }
    }
}
struct HelpView: View {
    var body: some View {
        List {
            Section("Notes") {
                Text("Open Deep dive, choose a subject and chapter. Use Aa for font size and spacing, and Outline to jump between headings.")
                Text("The study tools menu opens saved Snapshots, Flashcards and Qbank for the current chapter. Create with AI can use the open note as source text.")
            }
            Section("AI creation") {
                Text("Open AI settings in the sidebar and save your Google Gemini API key. Choose Create with AI, enter a topic, optionally add source text, then tap Generate and save.")
                Text("Saved creations work offline. Generation requires internet and uses your Gemini API quota.")
            }
            Section("Pen and paper") {
                Text("Import a PDF or create a blank or 8 mm ruled notebook. Turn Pen on to draw with Apple Pencil or a finger; turn it off to scroll. Marks save on this device. Export annotated PDF includes your marks.")
            }
            Section("Study") {
                Text("Reveal a flashcard answer and rate it Again, Hard, Good or Easy to schedule its next review. Qbank shows explanations after each answer and saves completed quiz scores in Performance.")
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).cortexPage("How-to")
    }
}
