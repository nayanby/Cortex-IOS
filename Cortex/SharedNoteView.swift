import SwiftUI

struct SharedNoteView: View {
    let note: LibraryNote
    @EnvironmentObject private var session: AccountSession
    @EnvironmentObject private var library: LibraryStore
    @State private var localURL: URL?
    @State private var progress: Double = 0
    @State private var errorMessage: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let bundled = OfflineLibrary.file(for: note) {
                DocumentReader(document: LocalDocument(id: SharedDocumentCache.identifier(for: "offline/" + note.path),
                    title: note.displayName, importedAt: .distantPast), fileURL: bundled, allowsSharing: false, note: note)
            } else if let profile = session.profile, let localURL {
                DocumentReader(document: LocalDocument(id: SharedDocumentCache.identifier(for: profile.uid + "/" + note.path),
                    title: note.displayName, importedAt: .distantPast), fileURL: localURL, allowsSharing: false, note: note)
            } else if session.profile == nil, let preview = PreviewLibrary.file(for: note) {
                DocumentReader(document: LocalDocument(id: SharedDocumentCache.identifier(for: "preview/" + note.path),
                    title: note.displayName, importedAt: .distantPast), fileURL: preview, allowsSharing: false)
            } else if session.profile == nil {
                ChapterOutline(note: note)
            } else if let errorMessage {
                VStack(spacing: 16) {
                    ContentUnavailableView("Could not open note", systemImage: "doc.badge.ellipsis", description: Text(errorMessage))
                    Button("Try again") { attempt += 1 }.buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 16) {
                    Text("Downloading note…").font(CortexStyle.title())
                    ProgressView(value: progress).frame(maxWidth: 260)
                    Text("\(Int(progress * 100))%").font(.callout).foregroundStyle(CortexStyle.muted)
                }
            }
        }
        .navigationTitle(note.displayName).navigationBarTitleDisplayMode(.inline)
        .task(id: "\(session.profile?.uid ?? ""):\(attempt)") {
            guard OfflineLibrary.file(for: note) == nil, let profile = session.profile else { return }
            localURL = nil; errorMessage = nil; progress = 0
            do {
                let file = try await library.document(note, profile: profile) { value in
                    Task { @MainActor in progress = value }
                }
                try Task.checkCancellation()
                guard session.profile?.uid == profile.uid else { return }
                localURL = file
            } catch is CancellationError { }
            catch {
                if !Task.isCancelled { errorMessage = AccountFailurePolicy.message(error) }
            }
        }
    }
}
