import Foundation

// Only explicitly packaged local content enables this mode. No remote access is bypassed.
enum OfflineLibrary {
    static var root: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("OfflineLibrary", isDirectory: true),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("catalog.json").path) else { return nil }
        return url
    }
    static var available: Bool { catalog != nil }
    static let catalog: LibraryCatalog? = {
        guard let root, let data = try? Data(contentsOf: root.appendingPathComponent("catalog.json")) else { return nil }
        return try? JSONDecoder().decode(LibraryCatalog.self, from: data)
    }()
    static func file(for note: LibraryNote) -> URL? {
        guard let root, note.id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
        let file = root.appendingPathComponent(note.id + ".docx")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
}

struct StudyEntry: Identifiable, Codable {
    let id: String
    let kind: String
    let document: String
    let folder: String
    let title: String
    let content: StudyContent
}
struct StudyContent: Codable {
    var title: String?
    var sections: [SnapshotSection]?
    var cards: [StudyCard]?
    var questions: [StudyQuestion]?
}
struct StudyCard: Codable {
    let front: String
    let back: String
    var sourceEntryID: String? = nil
    var sourceIndex: Int? = nil
}
struct StudyQuestion: Codable {
    let question: String
    let options: [String]
    let correctIndex: Int
    let explanation: String
}
struct SnapshotPoint: Codable {
    let text: String
    let subpoints: [String]?
    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) { self.text = text; subpoints = nil }
        else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            text = try c.decode(String.self, forKey: .text)
            subpoints = try c.decodeIfPresent([String].self, forKey: .subpoints)
        }
    }
    enum CodingKeys: String, CodingKey { case text, subpoints }
}
struct SnapshotSection: Codable {
    let heading: String?
    let points: [SnapshotPoint]?
    let numbered: [String]?
    let groups: [SnapshotGroup]?
    let tables: [SnapshotTable]?
}
struct SnapshotGroup: Codable {
    let heading: String?
    let points: [SnapshotPoint]?
    let numbered: [String]?
}
struct SnapshotTable: Codable {
    let title: String?
    let headers: [String]?
    let rows: [[String]]?
}

@MainActor
final class StudyLibrary: ObservableObject {
    static let shared = StudyLibrary()
    @Published private(set) var entries: [StudyEntry] = []
    @Published private(set) var loadError: String?
    private let savedURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("generated-study.json")
    init() {
        if let root = OfflineLibrary.root {
            do { entries = try JSONDecoder().decode([StudyEntry].self, from: Data(contentsOf: root.appendingPathComponent("study.json"))) }
            catch { loadError = "The bundled study catalog could not be opened." }
        }
        if let data = try? Data(contentsOf: savedURL), let saved = try? JSONDecoder().decode([StudyEntry].self, from: data) { entries += saved }
    }
    func save(_ entry: StudyEntry) throws {
        let updated = entries.filter { $0.id.hasPrefix("generated-") } + [entry]
        try FileManager.default.createDirectory(at: savedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: savedURL, options: [.atomic, .completeFileProtection])
        entries.append(entry)
    }
    func matching(kind: String, note: LibraryNote?) -> [StudyEntry] {
        entries.filter { entry in
            entry.kind == kind && (note == nil || (entry.document.localizedCaseInsensitiveCompare(note!.displayName) == .orderedSame && entry.folder.localizedCaseInsensitiveCompare(note!.subject) == .orderedSame))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
