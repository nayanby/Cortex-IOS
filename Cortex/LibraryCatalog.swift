import Foundation

struct LibraryCatalog: Codable, Sendable {
    let notes: [LibraryNote]

    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "library_catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    var subjects: [String] {
        Array(Set(notes.map(\.subject))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func notes(in subject: String, matching query: String = "") -> [LibraryNote] {
        notes.filter { $0.subject == subject && $0.matches(query) }
            .sorted { $0.sortOrder == $1.sortOrder
                ? $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                : $0.sortOrder < $1.sortOrder }
    }
}

struct LibraryNote: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let subject: String
    let displayName: String
    let fileName: String
    let sizeBytes: Int64
    let storagePath: String
    let sortOrder: Int
    let headings: [LibraryHeading]?
    var eTag: String? = nil

    func matches(_ query: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || displayName.localizedCaseInsensitiveContains(term)
            || subject.localizedCaseInsensitiveContains(term)
            || (headings ?? []).contains { $0.text.localizedCaseInsensitiveContains(term) }
    }
}

struct LibraryHeading: Codable, Hashable, Sendable {
    let level: Int
    let text: String
    let flash: Bool?
    let quiz: Bool?
    let snapshot: Bool?
}
