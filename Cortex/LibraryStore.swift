import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var catalog: LibraryCatalog?
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?
    private let cachedCatalog: URL
    private var backend: FirebaseLibraryBackend?

    init() {
        cachedCatalog = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cortex-catalog.json")
        if let data = try? Data(contentsOf: cachedCatalog), let saved = try? JSONDecoder().decode(LibraryCatalog.self, from: data) {
            catalog = saved
        } else {
            do { catalog = try LibraryCatalog.load() }
            catch { errorMessage = "The library catalog could not be opened." }
        }
    }

    private func configuredBackend() throws -> FirebaseLibraryBackend {
        guard FirebaseApp.app() != nil, Auth.auth().currentUser != nil else { throw LibraryFailure.signInRequired }
        if let backend { return backend }
        let created = FirebaseLibraryBackend(database: Firestore.firestore(), storage: Storage.storage())
        backend = created
        return created
    }

    func refresh(profile: ConsumerProfile) async {
        // Like Android: free accounts use the shipped/cached catalog and can read
        // notes; full/trial/beta accounts also receive remote catalog updates.
        guard profile.hasFullAccess(), !isRefreshing, let existing = catalog else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            guard Auth.auth().currentUser?.uid == profile.uid else { throw LibraryFailure.signInRequired }
            let updated = try await configuredBackend().catalog(fallback: existing)
            try Task.checkCancellation()
            guard Auth.auth().currentUser?.uid == profile.uid else { return }
            try JSONEncoder().encode(updated).write(to: cachedCatalog, options: [.atomic, .completeFileProtection])
            catalog = updated
            errorMessage = nil
        } catch is CancellationError { }
        catch { errorMessage = "Could not refresh the library. The saved catalog is still available." }
    }

    func document(_ note: LibraryNote, profile: ConsumerProfile,
                  progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard profile.canReadLibrary, Auth.auth().currentUser?.uid == profile.uid else { throw LibraryFailure.signInRequired }
        let url = try await configuredBackend().document(note, progress: progress)
        guard Auth.auth().currentUser?.uid == profile.uid else { throw LibraryFailure.signInRequired }
        return url
    }
}
