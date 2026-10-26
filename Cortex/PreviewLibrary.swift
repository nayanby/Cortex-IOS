import Foundation

// Optional documents supplied only to a Debug preview app after compilation.
// This does not bypass Firebase access or retrieve shared files anonymously.
enum PreviewLibrary {
    static func file(for note: LibraryNote) -> URL? {
        #if DEBUG
        guard let manifest = Bundle.main.url(forResource: "preview-library", withExtension: "json"),
              let data = try? Data(contentsOf: manifest),
              let mapping = try? JSONDecoder().decode([String: String].self, from: data),
              let name = mapping[note.id], !name.contains("/"), !name.contains("\\"),
              let file = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "PreviewNotes") else { return nil }
        return file
        #else
        return nil
        #endif
    }
}
