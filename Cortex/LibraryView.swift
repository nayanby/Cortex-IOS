import SwiftUI
import UniformTypeIdentifiers

enum CortexStyle {
    static let ink = Color(red: 41/255, green: 38/255, blue: 100/255)
    static let muted = Color(red: 102/255, green: 115/255, blue: 149/255)
    static let background = Color(red: 252/255, green: 252/255, blue: 254/255)
    static let line = Color(hex: 0xDDE1EF)
    static let blue = [Color(red: 234/255, green: 243/255, blue: 252/255),
                       Color(red: 207/255, green: 225/255, blue: 245/255)]
    static func title(_ size: CGFloat = 18) -> Font { .custom("AveriaSerifLibre-Bold", size: size) }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var session: AccountSession
    @State private var query = ""
    @StateObject private var localDocuments: LocalDocuments
    @State private var importing = false
    @State private var isImporting = false
    @State private var showingAccount = false
    @State private var searching = false
    @Environment(\.dismiss) private var dismiss

    init(accountID: String? = nil) {
        let directory = accountID.map { id in
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("AccountNotes", isDirectory: true)
                .appendingPathComponent(SharedDocumentCache.identifier(for: id).uuidString, isDirectory: true)
        }
        _localDocuments = StateObject(wrappedValue: LocalDocuments(directory: directory))
    }

    var body: some View {
            Group {
                if let catalog = library.catalog {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if StudyLibrary.shared.entries.contains(where: { $0.kind == "Notes" }) {
                                NavigationLink { StudyBrowser(kind: "Notes") } label: {
                                    LibraryCard(title: "Created notes", subtitle: "Saved AI notes on this device", symbol: "doc.text")
                                }.buttonStyle(.plain)
                            }
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
                                    NavigationLink { SharedNoteView(note: note) } label: {
                                        LibraryCard(title: note.displayName, subtitle: note.subject,
                                                    symbol: "doc.text")
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.padding(.horizontal, 14).padding(.top, 12)
                    }
                } else if let loadError = library.errorMessage {
                    ContentUnavailableView("Library unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(loadError))
                } else {
                    ProgressView("Loading library…")
                }
            }
            .background(CortexStyle.background)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    CortexHeader(title: "Deep dive", leading: { dismiss() }, search: { searching.toggle() })
                    if searching { TextField("Search notes and headings", text: $query).textFieldStyle(.roundedBorder).padding(12) }
                }.background(.white)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Button { importing = true } label: { Label("Import Word document", systemImage: "square.and.arrow.down") }
                        .disabled(isImporting).font(.system(size: 13))
                    Spacer()
                    Button("Home") { dismiss() }.font(CortexStyle.title(14))
                }.padding(14).background(.white)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if session.profile != nil {
                        Button { showingAccount = true } label: { Label("Account", systemImage: "person.crop.circle") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Label("Import Word document", systemImage: "square.and.arrow.down") }
                        .disabled(isImporting)
                }
            }
            .sheet(isPresented: $showingAccount) { ConsumerAccountView() }
            .refreshable {
                if let profile = session.profile { await library.refresh(profile: profile) }
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
            .tint(CortexStyle.ink).consumerTabs("home")
    }
}

struct LibraryCard: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            if symbol == "books.vertical" {
                Image(Self.subjectArtwork(title)).resizable().scaledToFit().frame(width: 48, height: 48).accessibilityHidden(true)
            } else { CortexArtwork(name: "book", size: 48) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(CortexStyle.title(16)).multilineTextAlignment(.leading)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(CortexStyle.muted)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(CortexStyle.ink)
        .padding(12).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0xF4F7FD), Color(hex: 0xE7EDF9)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xD9E2F2), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private static func subjectArtwork(_ title: String) -> String {
        let name = title.lowercased()
        let mappings: [(String, [String])] = [
            ("heart", ["cardio", "heart"]), ("lungs", ["pulmon", "respir", "lung"]),
            ("neurology", ["neurolog"]), ("psychiatry", ["psychiatr", "mental"]),
            ("kidney", ["nephro", "renal", "kidney"]), ("rheumatology", ["rheumat", "orthop", "joint"]),
            ("infectious", ["infect", "microbiol"]), ("hematology", ["hemat", "haemat", "blood"]),
            ("thyroid", ["thyroid", "endocrin"]), ("liver", ["liver", "hepat"]),
            ("gi", ["gastro", "intestinal", "digest"]), ("clinical", ["clinical", "exam", "medicine"])
        ]
        return "deepdive_icon_" + (mappings.first { row in row.1.contains { name.contains($0) } }?.0 ?? "notebook")
    }
}

struct ChapterList: View {
    let catalog: LibraryCatalog
    let subject: String
    @State private var query = ""
    @State private var searching = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                let notes = catalog.notes(in: subject, matching: query)
                if notes.isEmpty { ContentUnavailableView.search(text: query) }
                ForEach(notes) { note in
                    NavigationLink { SharedNoteView(note: note) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CHAPTER \((catalog.notes(in: subject).firstIndex(where: { $0.id == note.id }) ?? 0) + 1)")
                                .font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(CortexStyle.muted)
                            Text(note.displayName).font(CortexStyle.title(16)).foregroundStyle(CortexStyle.ink)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(LinearGradient(colors: [Color(hex: 0xF4F7FD), Color(hex: 0xE7EDF9)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xD9E2F2), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }.padding(16)
        }
        .background(CortexStyle.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                CortexHeader(title: subject, leading: { dismiss() }, search: { searching.toggle() })
                if searching { TextField("Search chapters and headings", text: $query).textFieldStyle(.roundedBorder).padding(12) }
            }.background(.white)
        }
    }
}

struct ChapterOutline: View {
    let note: LibraryNote

    var body: some View {
        List {
            Section {
                Text("Sign in to read this note. The catalog and outline are available in this offline preview.")
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
