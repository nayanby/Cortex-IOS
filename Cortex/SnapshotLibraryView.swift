import SwiftUI

struct SnapshotLibraryView: View {
    var note: LibraryNote? = nil
    var folder: String? = nil
    var document: String? = nil
    @EnvironmentObject private var catalog: LibraryStore
    @ObservedObject private var library = StudyLibrary.shared
    @State private var query = ""
    private var entries: [StudyEntry] {
        library.entries.filter { entry in
            entry.kind == "Snapshots" && (folder == nil || entry.folder == folder) && (document == nil || entry.document == document) &&
            (note == nil || (entry.folder.caseInsensitiveCompare(note!.subject) == .orderedSame && entry.document.caseInsensitiveCompare(note!.displayName) == .orderedSame))
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing:8) {
                if let error = library.loadError { Text(error).foregroundStyle(.red) }
                if entries.isEmpty { ContentUnavailableView("No saved Snapshots",systemImage:"rectangle.stack",description:Text("No Snapshots are available for this chapter.")) }
                if !query.isEmpty || note != nil || document != nil {
                    ForEach(entries.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.document.localizedCaseInsensitiveContains(query) || $0.folder.localizedCaseInsensitiveContains(query) }) { entry in
                        NavigationLink { SnapshotReader(entry:entry) } label: { SnapshotLibraryCard(title:entry.title,subtitle:entry.document) }.buttonStyle(.plain)
                    }
                } else if folder == nil {
                    ForEach(Array(Set(entries.map(\.folder))).sorted(),id:\.self) { name in
                        let chapters = Set(entries.filter { $0.folder == name }.map(\.document)).count
                        NavigationLink { SnapshotLibraryView(folder:name) } label: { SnapshotLibraryCard(title:name,subtitle:"\(chapters) chapters") }.buttonStyle(.plain)
                    }
                } else {
                    ForEach(documents,id:\.self) { name in
                        let count = entries.filter { $0.document == name }.count
                        NavigationLink { SnapshotLibraryView(folder:folder,document:name) } label: { SnapshotLibraryCard(title:name,subtitle:"\(count) Snapshots") }.buttonStyle(.plain)
                    }
                }
            }.padding(14)
        }.cortexPage(document ?? folder ?? "Snapshots",search:$query).consumerTabs("home",visible:note == nil && folder == nil && document == nil)
    }
    private var documents: [String] {
        Array(Set(entries.map(\.document))).sorted { left,right in
            let notes = catalog.catalog?.notes ?? []
            let a = notes.first { $0.subject == folder && $0.displayName == left }?.sortOrder ?? Int.max
            let b = notes.first { $0.subject == folder && $0.displayName == right }?.sortOrder ?? Int.max
            return a == b ? left.localizedStandardCompare(right) == .orderedAscending : a < b
        }
    }
}
private struct SnapshotLibraryCard: View {
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing:12) {
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(CortexStyle.title(16)).multilineTextAlignment(.leading)
                Text(subtitle).font(.system(size:12)).foregroundStyle(CortexStyle.muted)
            }
            Spacer(minLength:4); CortexArtwork(name:"right",size:22)
        }.foregroundStyle(CortexStyle.ink).padding(12).frame(maxWidth:.infinity,minHeight:70,alignment:.leading)
            .background(LinearGradient(colors:[Color(hex:0xFCF6F8),Color(hex:0xF3E5EB)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).stroke(Color(hex:0xE9D5DE),lineWidth:1))
    }
}
