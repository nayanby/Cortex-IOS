import Foundation

struct LocalDocument: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let importedAt: Date
}

@MainActor
final class LocalDocuments: ObservableObject {
    @Published private(set) var documents: [LocalDocument] = []
    @Published var errorMessage: String?
    private let directory: URL
    private let indexURL: URL
    static let maximumBytes = 32 * 1024 * 1024

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedNotes", isDirectory: true)
        self.directory = base
        indexURL = base.appendingPathComponent("index.json")
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                documents = try JSONDecoder().decode([LocalDocument].self, from: Data(contentsOf: indexURL))
            }
        } catch { errorMessage = "Could not open imported notes: \(error.localizedDescription)" }
    }

    func fileURL(for document: LocalDocument) -> URL {
        directory.appendingPathComponent(document.id.uuidString).appendingPathExtension("docx")
    }

    func importDocument(from source: URL) async throws {
        let destinationDirectory = directory
        let document = try await Task.detached(priority: .userInitiated) {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            guard source.pathExtension.lowercased() == "docx" else { throw ImportError.notDocx }
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= LocalDocuments.maximumBytes else { throw ImportError.tooLarge }
            let data = try Data(contentsOf: source)
            guard data.count <= LocalDocuments.maximumBytes else { throw ImportError.tooLarge }
            guard data.starts(with: [0x50, 0x4b, 0x03, 0x04]) else { throw ImportError.notDocx }
            let document = LocalDocument(id: UUID(), title: source.deletingPathExtension().lastPathComponent, importedAt: Date())
            let target = destinationDirectory.appendingPathComponent(document.id.uuidString).appendingPathExtension("docx")
            try data.write(to: target, options: [.atomic, .completeFileProtection])
            return document
        }.value
        let updated = [document] + documents
        do {
            try JSONEncoder().encode(updated).write(to: indexURL, options: [.atomic, .completeFileProtection])
            documents = updated
        } catch {
            try? FileManager.default.removeItem(at: fileURL(for: document))
            throw error
        }
    }

    func remove(_ document: LocalDocument) throws {
        let updated = documents.filter { $0.id != document.id }
        try JSONEncoder().encode(updated).write(to: indexURL, options: [.atomic, .completeFileProtection])
        documents = updated
        // An orphan is harmless if removal fails; it must not restore a deleted index row.
        try FileManager.default.removeItem(at: fileURL(for: document))
        UserDefaults.standard.removeObject(forKey: "reading.\(document.id.uuidString)")
    }

    enum ImportError: LocalizedError {
        case notDocx, tooLarge
        var errorDescription: String? {
            switch self {
            case .notDocx: return "Choose a Word document (.docx)."
            case .tooLarge: return "This document exceeds the current 32 MB import limit."
            }
        }
    }
}
