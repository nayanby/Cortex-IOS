import Foundation
import CryptoKit

actor SharedDocumentCache {
    static let lifetime: TimeInterval = 24 * 60 * 60 // Same 1-day TTL as Android.
    nonisolated static let maximumBytes = 32 * 1024 * 1024
    private let directory: URL
    private struct Entry: Codable { let storagePath: String; let eTag: String?; let savedAt: Date }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SharedNotes", isDirectory: true)
    }

    nonisolated static func identifier(for path: String) -> UUID {
        let b = Array(SHA256.hash(data: Data(path.utf8)))
        return UUID(uuid: (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]))
    }

    private func file(_ note: LibraryNote) -> URL {
        directory.appendingPathComponent(Self.identifier(for: note.storagePath).uuidString).appendingPathExtension("docx")
    }
    private func metadata(_ note: LibraryNote) -> URL { file(note).appendingPathExtension("json") }

    func cachedFile(for note: LibraryNote, now: Date = Date()) -> URL? {
        guard let bytes = try? Data(contentsOf: metadata(note)), let entry = try? JSONDecoder().decode(Entry.self, from: bytes),
              entry.storagePath == note.storagePath, now.timeIntervalSince(entry.savedAt) < Self.lifetime,
              FileManager.default.fileExists(atPath: file(note).path) else { return nil }
        if let remote = note.eTag, let cached = entry.eTag, remote != cached { return nil }
        return file(note)
    }

    func commit(download: URL, for note: LibraryNote, now: Date = Date()) throws -> URL {
        let size = try download.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumBytes else { throw LibraryFailure.tooLarge }
        let bytes = try Data(contentsOf: download)
        guard bytes.count <= Self.maximumBytes else { throw LibraryFailure.tooLarge }
        guard bytes.starts(with: [0x50, 0x4b, 0x03, 0x04]) else { throw LibraryFailure.notWord }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bytes.write(to: file(note), options: [.atomic, .completeFileProtection])
        try JSONEncoder().encode(Entry(storagePath: note.storagePath, eTag: note.eTag, savedAt: now))
            .write(to: metadata(note), options: [.atomic, .completeFileProtection])
        return file(note)
    }
}

enum LibraryFailure: LocalizedError {
    case signInRequired, invalidPath, tooLarge, notWord, downloadFailed
    var errorDescription: String? {
        switch self {
        case .signInRequired: return "Sign in to read this note."
        case .invalidPath: return "This note has an invalid library location. Refresh the library and try again."
        case .tooLarge: return "This note exceeds the current 32 MB reader limit."
        case .notWord: return "The downloaded file is not a readable Word document."
        case .downloadFailed: return "Could not download this note. Check the connection and try again."
        }
    }
}
