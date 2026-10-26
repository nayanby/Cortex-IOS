import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseAppCheck
@testable import Cortex

final class FirebaseConsumerIntegrationTests: XCTestCase {
    @MainActor
    func testAccountTrialCatalogDownloadAndKeychainAgainstDemoEmulators() async throws {
        guard ProcessInfo.processInfo.environment["CORTEX_TEST_EMULATORS"] == "1" else {
            XCTFail("The account/download integration test must run through the demo emulator workflow.")
            return
        }
        // Always a named demo app with all network endpoints explicitly local.
        // This does not use or require cortex-v1b's production configuration.
        let options = FirebaseOptions(googleAppID: "1:123456789:ios:abcdef123456", gcmSenderID: "123456789")
        options.apiKey = "fake-api-key-for-local-emulators-only"
        options.projectID = "demo-cortex-ios"
        options.storageBucket = "demo-cortex-ios.appspot.com"
        options.bundleID = "com.cortex.notes"
        let name = "Emulator-\(UUID().uuidString)"
        AppCheck.setAppCheckProviderFactory(DemoAppCheckFactory())
        FirebaseApp.configure(name: name, options: options)
        let app = try XCTUnwrap(FirebaseApp.app(name: name))
        let auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        let database = Firestore.firestore(app: app)
        database.useEmulator(withHost: "127.0.0.1", port: 8080)
        let storage = Storage.storage(app: app)
        storage.useEmulator(withHost: "127.0.0.1", port: 9199)

        let email = "ios-\(UUID().uuidString.lowercased())@example.test"
        let result = try await auth.createUser(withEmail: email, password: "emulator-test-password-only")
        let identity = ConsumerIdentity(uid: result.user.uid, email: email, name: "Synthetic reader")
        let account = FirebaseAccountBackend(database: database)
        async let first = account.profile(for: identity, startTrial: true)
        async let second = account.profile(for: identity, startTrial: true)
        let profiles = try await (first, second)
        XCTAssertEqual(profiles.0.trialStartedAt, profiles.1.trialStartedAt, "Concurrent sign-ins restarted the trial")
        XCTAssertGreaterThan(profiles.0.trialStartedAt, 0)
        XCTAssertEqual(profiles.0.plan, "trial")
        let keychain = KeychainProfileCache()
        try keychain.save(profiles.0)
        defer { keychain.remove(uid: identity.uid) }
        XCTAssertEqual(keychain.read(uid: identity.uid), profiles.0)
        XCTAssertNil(keychain.read(uid: "different-user"))
        try await database.collection("users").document(email).setData(["plan": "full"], merge: true)
        let full = try await account.profile(for: identity, startTrial: true)
        XCTAssertEqual(full.plan, "full")
        XCTAssertEqual(full.trialStartedAt, profiles.0.trialStartedAt)
        do {
            _ = try await database.collection("users").document("other@example.test").getDocument(source: .server)
            XCTFail("Emulator rules allowed another account's profile")
        } catch { XCTAssertEqual((error as NSError).code, 7) }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SharedDocumentCache(directory: directory)
        let library = FirebaseLibraryBackend(database: database, storage: storage, cache: cache)
        let catalog = try await library.catalog(fallback: LibraryCatalog(notes: []))
        let note = try XCTUnwrap(catalog.notes.first)
        XCTAssertEqual(note.storagePath, "files/Tests/reader-check.docx")
        let downloaded = try await library.document(note) { _ in }
        let fixture = try XCTUnwrap(Bundle(for: ReaderTests.self).url(forResource: "reader-check", withExtension: "docx", subdirectory: "Fixtures"))
        XCTAssertEqual(try Data(contentsOf: downloaded), try Data(contentsOf: fixture))
        let cached = await cache.cachedFile(for: note)
        XCTAssertEqual(cached, downloaded)
        let cancelledBackend = FirebaseLibraryBackend(database: database, storage: storage,
            cache: SharedDocumentCache(directory: directory.appendingPathComponent("cancelled")))
        let cancelled = Task { try await cancelledBackend.document(note) { _ in } }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled download completed") }
        catch is CancellationError { }
        try auth.signOut()
    }
}

// Test bundle only: no attestation request leaves the demo emulator workflow.
private final class DemoAppCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        guard app.options.projectID == "demo-cortex-ios" else { return nil }
        return DemoAppCheckProvider()
    }
}
private final class DemoAppCheckProvider: NSObject, AppCheckProvider {
    func getToken(completion handler: @escaping (AppCheckToken?, Error?) -> Void) {
        handler(AppCheckToken(token: "local-demo-emulator-only", expirationDate: Date().addingTimeInterval(3600)), nil)
    }
}
