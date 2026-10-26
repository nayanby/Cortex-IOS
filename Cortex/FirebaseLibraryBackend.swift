import Foundation
import FirebaseFirestore
import FirebaseStorage

// Cancellation may arrive before Storage has returned its task handle.
private final class DownloadHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: StorageDownloadTask?
    private var cancelled = false
    func install(_ task: StorageDownloadTask) {
        lock.lock(); self.task = task; let stop = cancelled; lock.unlock()
        if stop { task.cancel() }
    }
    func cancel() {
        lock.lock(); cancelled = true; let active = task; lock.unlock()
        active?.cancel()
    }
}

final class FirebaseLibraryBackend {
    let database: Firestore
    let storage: Storage
    let cache: SharedDocumentCache
    init(database: Firestore, storage: Storage, cache: SharedDocumentCache = SharedDocumentCache()) {
        self.database = database; self.storage = storage; self.cache = cache
    }

    func catalog(fallback: LibraryCatalog) async throws -> LibraryCatalog {
        let snapshot = try await database.collection("library").document("catalog").collection("notes").getDocuments()
        var paths: [String: LibraryNote] = [:]
        let bundled = Dictionary(fallback.notes.map { ($0.path.lowercased(), $0) }, uniquingKeysWith: { old, _ in old })
        for (index, row) in snapshot.documents.enumerated() {
            let fields = row.data()
            let fileName = (fields["fileName"] as? String).nonEmpty ?? "\(row.documentID).docx"
            let subject = (fields["subject"] as? String).nonEmpty ?? "Library"
            let path = (fields["path"] as? String).nonEmpty ?? "\(subject)/\(fileName)"
            var headings = bundled[path.lowercased()]?.headings
            if let json = fields["headingsJson"] as? String, let bytes = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([LibraryHeading].self, from: bytes) { headings = decoded }
            let note = LibraryNote(id: row.documentID, path: path, subject: subject,
                displayName: (fields["displayName"] as? String).nonEmpty ?? (fileName as NSString).deletingPathExtension,
                fileName: fileName, sizeBytes: (fields["sizeBytes"] as? NSNumber)?.int64Value ?? 0,
                storagePath: (fields["storagePath"] as? String).nonEmpty ?? "files/\(path)",
                sortOrder: (fields["sortOrder"] as? NSNumber)?.intValue ?? index, headings: headings,
                eTag: fields["etag"] as? String)
            let key = path.lowercased()
            if let previous = paths[key], !previous.id.hasPrefix("files-") { continue }
            paths[key] = note
        }
        return LibraryCatalog(notes: paths.values.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending })
    }

    func document(_ note: LibraryNote, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard Self.validStoragePath(note.storagePath) else { throw LibraryFailure.invalidPath }
        if let saved = await cache.cachedFile(for: note) { progress(1); return saved }
        try Task.checkCancellation()
        let reference = storage.reference().child(note.storagePath)
        let metadata = try await reference.getMetadata()
        guard metadata.size <= Int64(SharedDocumentCache.maximumBytes) else { throw LibraryFailure.tooLarge }
        try Task.checkCancellation()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("docx")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let handle = DownloadHandle()
        try await withTaskCancellationHandler {
            let _: URL = try await withCheckedThrowingContinuation { continuation in
                let task = reference.write(toFile: temporary) { url, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: LibraryFailure.downloadFailed) }
                }
                handle.install(task)
                task.observe(.progress) { snapshot in
                    guard let p = snapshot.progress, p.totalUnitCount > 0 else { return }
                    progress(min(1, max(0, p.fractionCompleted)))
                }
            }
        } onCancel: { handle.cancel() }
        try Task.checkCancellation()
        let saved = try await cache.commit(download: temporary, for: note)
        progress(1)
        return saved
    }

    static func validStoragePath(_ path: String) -> Bool {
        (path.hasPrefix("files/") || path.hasPrefix("notes/")) &&
            !path.contains("\\") && !path.split(separator: "/").contains("..") && path.lowercased().hasSuffix(".docx")
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? { flatMap { $0.isEmpty ? nil : $0 } }
}
