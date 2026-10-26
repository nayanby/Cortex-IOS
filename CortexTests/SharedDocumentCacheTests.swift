import XCTest
@testable import Cortex

final class SharedDocumentCacheTests: XCTestCase {
    func testDownloadsAreAtomicAndExpireAfterOneDay() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = SharedDocumentCache(directory: root)
        let fixture = try XCTUnwrap(Bundle(for: ReaderTests.self).url(forResource: "reader-check", withExtension: "docx", subdirectory: "Fixtures"))
        let note = LibraryNote(id: "fixture", path: "Tests/reader-check.docx", subject: "Tests", displayName: "Reader",
            fileName: "reader-check.docx", sizeBytes: 1, storagePath: "files/Tests/reader-check.docx", sortOrder: 0, headings: [], eTag: "v1")
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        let saved = try await cache.commit(download: fixture, for: note, now: time)
        XCTAssertEqual(try Data(contentsOf: saved), try Data(contentsOf: fixture))
        let fresh = await cache.cachedFile(for: note, now: time.addingTimeInterval(86_399))
        XCTAssertEqual(fresh, saved)
        let expired = await cache.cachedFile(for: note, now: time.addingTimeInterval(86_400))
        XCTAssertNil(expired)
        var changed = note; changed.eTag = "v2"
        let stale = await cache.cachedFile(for: changed, now: time)
        XCTAssertNil(stale)
        let invalid = root.appendingPathComponent("invalid.docx")
        try Data("Not a Word file".utf8).write(to: invalid)
        do { _ = try await cache.commit(download: invalid, for: note, now: time); XCTFail("Accepted non-Word data") }
        catch { }
        XCTAssertEqual(try Data(contentsOf: saved), try Data(contentsOf: fixture), "A failed import replaced the valid cached note")
    }
}
