import SwiftUI
import UniformTypeIdentifiers

enum CortexStyle {
    static let ink = Color(red: 41/255, green: 38/255, blue: 100/255)
    static let muted = Color(red: 102/255, green: 115/255, blue: 149/255)
    static let background = Color(red: 252/255, green: 252/255, blue: 254/255)
    static let blue = [Color(red: 234/255, green: 243/255, blue: 252/255),
                       Color(red: 207/255, green: 225/255, blue: 245/255)]
    static func title(_ size: CGFloat = 18) -> Font { .custom("AveriaSerifLibre-Bold", size: size) }
}

struct LibraryView: View {
    @State private var catalog: LibraryCatalog?
    @State private var loadError: String?
    @State private var query = ""
    @StateObject private var localDocuments = LocalDocuments()
    @State private var importing = false
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Group {
                if let catalog {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if !localDocuments.documents.isEmpty {
                                HStack {
                                    Text("My notes").font(CortexStyle.title())
                                    Spacer()
                                }
                                ForEach(localDocuments.documents.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { document in
                                    NavigationLink {
                                        DocumentReader(document: document, fileURL: localDocuments.fileURL(for: document))
                                    } label: {
                                        LibraryCard(title: document.title, subtitle: "Imported Word document", symbol: "doc.text")
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Delete imported note", role: .destructive) {
                                            do { try localDocuments.remove(document) }
                                            catch { localDocuments.errorMessage = error.localizedDescription }
                                        }
                                    }
                                }
                            }
                            if query.isEmpty {
                                ForEach(catalog.subjects, id: \.self) { subject in
                                    NavigationLink {
                                        ChapterList(catalog: catalog, subject: subject)
                                    } label: {
                                        LibraryCard(title: subject,
                                            subtitle: "\(catalog.notes(in: subject).count) chapters",
                                            symbol: "books.vertical")
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                let matches = catalog.notes.filter { $0.matches(query) }
                                if matches.isEmpty {
                                    ContentUnavailableView.search(text: query)
                                }
                                ForEach(matches) { note in
                                    NavigationLink { ChapterOutline(note: note) } label: {
                                        LibraryCard(title: note.displayName, subtitle: note.subject,
                                                    symbol: "doc.text")
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.padding(16)
                    }
                } else if let loadError {
                    ContentUnavailableView("Library unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(loadError))
                } else {
                    ProgressView("Loading library…")
                }
            }
            .background(CortexStyle.background)
            .navigationTitle("DEEP DIVE")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search notes and headings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Label("Import Word document", systemImage: "square.and.arrow.down") }
                        .disabled(isImporting)
                }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [UTType(filenameExtension: "docx") ?? .data]) { result in
                switch result {
                case .success(let url):
                    isImporting = true
                    Task {
                        defer { isImporting = false }
                        do { try await localDocuments.importDocument(from: url) }
                        catch { localDocuments.errorMessage = error.localizedDescription }
                    }
                case .failure(let error): localDocuments.errorMessage = error.localizedDescription
                }
            }
            .overlay {
                if isImporting { ProgressView("Importing note…").padding(24).background(.regularMaterial) }
            }
            .alert("Imported notes", isPresented: Binding(
                get: { localDocuments.errorMessage != nil },
                set: { if !$0 { localDocuments.errorMessage = nil } })) {
                    Button("OK") { localDocuments.errorMessage = nil }
                } message: { Text(localDocuments.errorMessage ?? "") }
            .task {
                guard catalog == nil, loadError == nil else { return }
                do { catalog = try LibraryCatalog.load() }
                catch { loadError = "The bundled catalog could not be read. \(error.localizedDescription)" }
            }
        }.tint(CortexStyle.ink)
    }
}

struct LibraryCard: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28)).frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(CortexStyle.title()).multilineTextAlignment(.leading)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(CortexStyle.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 14)).accessibilityHidden(true)
        }
        .foregroundStyle(CortexStyle.ink)
        .padding(12).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(LinearGradient(colors: CortexStyle.blue, startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ChapterList: View {
    let catalog: LibraryCatalog
    let subject: String
    @State private var query = ""

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                let notes = catalog.notes(in: subject, matching: query)
                if notes.isEmpty { ContentUnavailableView.search(text: query) }
                ForEach(notes) { note in
                    NavigationLink { ChapterOutline(note: note) } label: {
                        LibraryCard(title: note.displayName,
                                    subtitle: "\((note.headings ?? []).count) headings", symbol: "doc.text")
                    }.buttonStyle(.plain)
                }
            }.padding(16)
        }
        .background(CortexStyle.background)
        .navigationTitle(subject).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search chapters and headings")
    }
}

struct ChapterOutline: View {
    let note: LibraryNote

    var body: some View {
        List {
            Section {
                Text("The catalog is available offline. Reading this document will become available after the iOS sign-in and document download services are connected.")
                    .font(.callout).foregroundStyle(CortexStyle.muted)
            }
            Section("Outline") {
                ForEach(Array((note.headings ?? []).enumerated()), id: \.offset) { _, heading in
                    Text(heading.text)
                        .font(CortexStyle.title(heading.level == 1 ? 17 : 15))
                        .foregroundStyle(CortexStyle.ink)
                        .padding(.leading, heading.level == 1 ? 0 : 16)
                }
            }
        }
        .navigationTitle(note.displayName).navigationBarTitleDisplayMode(.inline)
    }
}
