import SwiftUI

// A selection keeps each flashcard's original review identity across combined decks.
enum StudySelection {
    static func aggregate(_ entries:[StudyEntry],kind:String,title:String,catalog:LibraryCatalog? = nil) -> StudyEntry {
        let notes = catalog?.notes ?? []
        let rows = entries.filter { $0.kind == kind }.sorted { left,right in
            if left.folder != right.folder { return left.folder.localizedStandardCompare(right.folder) == .orderedAscending }
            let a = notes.first { $0.subject.caseInsensitiveCompare(left.folder) == .orderedSame && $0.displayName.caseInsensitiveCompare(left.document) == .orderedSame }
            let b = notes.first { $0.subject.caseInsensitiveCompare(right.folder) == .orderedSame && $0.displayName.caseInsensitiveCompare(right.document) == .orderedSame }
            if a?.sortOrder != b?.sortOrder { return (a?.sortOrder ?? Int.max) < (b?.sortOrder ?? Int.max) }
            if left.document != right.document { return left.document.localizedStandardCompare(right.document) == .orderedAscending }
            let ai = a?.headings?.firstIndex { $0.text.caseInsensitiveCompare(left.title) == .orderedSame } ?? Int.max
            let bi = b?.headings?.firstIndex { $0.text.caseInsensitiveCompare(right.title) == .orderedSame } ?? Int.max
            if ai != bi { return ai < bi }
            return left.title == right.title ? left.id < right.id : left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
        let id = "selection-" + SharedDocumentCache.identifier(for:kind + ":" + rows.map(\.id).joined(separator:"|")).uuidString
        let cards:[StudyCard]? = kind == "Flashcards" ? rows.flatMap { entry in
            (entry.content.cards ?? []).enumerated().map { index,card in
                StudyCard(front:card.front,back:card.back,sourceEntryID:card.sourceEntryID ?? entry.id,sourceIndex:card.sourceIndex ?? index)
            }
        } : nil
        let questions:[StudyQuestion]? = kind == "Qbank" ? rows.flatMap { $0.content.questions ?? [] } : nil
        return StudyEntry(id:id,kind:kind,document:title,folder:"Selected subjects",title:title,
            content:StudyContent(title:title,sections:nil,cards:cards,questions:questions))
    }
    static func scope(_ entries:[StudyEntry],kind:String,subject:String?,chapter:String?) -> [StudyEntry] {
        entries.filter { $0.kind == kind && (subject == nil || $0.folder.caseInsensitiveCompare(subject!) == .orderedSame) && (chapter == nil || $0.document.caseInsensitiveCompare(chapter!) == .orderedSame) }
    }
}

struct StudySelectionView: View {
    let kind: String
    var note: LibraryNote? = nil
    var subject: String? = nil
    var chapter: String? = nil
    @EnvironmentObject private var catalog: LibraryStore
    @ObservedObject private var library = StudyLibrary.shared
    @ObservedObject private var progress = StudyProgress.shared
    @State private var selected: Set<String> = []
    @State private var query = ""
    @State private var reviewSettings = false
    @State private var combined: StudyEntry?
    private var currentSubject: String? { note?.subject ?? subject }
    private var currentChapter: String? { note?.displayName ?? chapter }
    private var entries: [StudyEntry] { StudySelection.scope(library.entries,kind:kind,subject:currentSubject,chapter:currentChapter) }
    private var isSubjects: Bool { currentSubject == nil }
    private var isChapters: Bool { currentSubject != nil && currentChapter == nil }
    private var visibleEntries: [StudyEntry] {
        entries.filter { query.isEmpty || $0.folder.localizedCaseInsensitiveContains(query) || $0.document.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query) }
    }
    private var chosen: [StudyEntry] {
        guard !selected.isEmpty else { return visibleEntries }
        return entries.filter { selected.contains("subject:" + $0.folder) || selected.contains("chapter:" + $0.document) || selected.contains("entry:" + $0.id) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:10) {
                Text(isSubjects ? "Choose subjects" : isChapters ? "Choose chapters" : "Choose headings").font(CortexStyle.title(22))
                Text("Select one or more, or open a card to narrow your selection.").font(.system(size:13)).foregroundStyle(CortexStyle.muted)
                NavigationLink { CreateStudyView(note:note,initialKind:kind) } label: {
                    Label(kind == "Qbank" ? "Create questions with AI" : "Create flashcards with AI",systemImage:"sparkles").font(.system(size:14,weight:.semibold))
                }.padding(.bottom,4)
                if let error = library.loadError { Text(error).foregroundStyle(.red) }
                if entries.isEmpty { ContentUnavailableView("No saved \(kind.lowercased())",systemImage:"books.vertical",description:Text("Create a set with AI to study this topic.")) }
                if !query.isEmpty {
                    ForEach(visibleEntries) { entry in
                        entryRow(entry)
                    }
                } else if isSubjects {
                    ForEach(Array(Set(entries.map(\.folder))).sorted { $0.localizedStandardCompare($1) == .orderedAscending },id:\.self) { name in
                        HStack(spacing:6) {
                            check("subject:" + name,title:name)
                            NavigationLink { StudySelectionView(kind:kind,subject:name) } label: {
                                LibraryCard(title:name,subtitle:summary(entries.filter { $0.folder == name }),symbol:"books.vertical")
                            }.buttonStyle(.plain)
                        }
                    }
                } else if isChapters {
                    ForEach(chapters,id:\.self) { name in
                        HStack(spacing:6) {
                            check("chapter:" + name,title:name)
                            NavigationLink { StudySelectionView(kind:kind,subject:currentSubject,chapter:name) } label: {
                                LibraryCard(title:name,subtitle:summary(entries.filter { $0.document == name }),symbol:"doc.text")
                            }.buttonStyle(.plain)
                        }
                    }
                } else {
                    ForEach(orderedEntries) { entry in entryRow(entry) }
                }
            }.padding(14)
        }.background(CortexStyle.background).navigationTitle(currentChapter ?? currentSubject ?? kind)
            .navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)
            .searchable(text:$query,prompt:"Search subjects, chapters and headings")
            .toolbar {
                if kind == "Flashcards" { Button { reviewSettings = true } label: { Label("Review settings",systemImage:"gearshape") } }
                if !selected.isEmpty { Button("Clear selection") { selected.removeAll() } }
            }
            .safeAreaInset(edge:.bottom,spacing:0) {
                if !entries.isEmpty {
                    Button { combined = StudySelection.aggregate(chosen,kind:kind,title:currentChapter ?? currentSubject ?? (selected.isEmpty ? (query.isEmpty ? "All subjects" : "Search results") : "Selected subjects"),catalog:catalog.catalog) } label: {
                        VStack(spacing:3) {
                            Text(kind == "Flashcards" ? "Review \(selected.isEmpty ? "all" : "selection")" : "Solve \(selected.isEmpty ? "all" : "selection")").font(CortexStyle.title(17))
                            Text(summary(chosen)).font(.system(size:12))
                        }.frame(maxWidth:.infinity).padding(12)
                    }.buttonStyle(.borderedProminent).disabled(chosen.isEmpty).padding(12).background(.white)
                }
            }
            .navigationDestination(isPresented:Binding(get:{combined != nil},set:{if !$0 { combined = nil }})) { if let combined { StudyDetail(entry:combined) } }
            .sheet(isPresented:$reviewSettings) { ReviewSettingsView() }
    }
    private func check(_ id:String,title:String) -> some View {
        Button { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } } label: {
            Image(systemName:selected.contains(id) ? "checkmark.square.fill" : "square").font(.system(size:22)).frame(width:36,height:48)
        }.buttonStyle(.plain).accessibilityLabel((selected.contains(id) ? "Deselect " : "Select ") + title)
    }
    private func entryRow(_ entry:StudyEntry) -> some View {
        HStack(spacing:6) {
            check("entry:" + entry.id,title:entry.title)
            NavigationLink { StudyDetail(entry:entry) } label: {
                LibraryCard(title:entry.title,subtitle:summary([entry]),symbol:"doc.text")
            }.buttonStyle(.plain)
        }
    }
    private func summary(_ rows:[StudyEntry]) -> String {
        if kind == "Flashcards" {
            let cards = rows.reduce(0) { $0 + ($1.content.cards?.count ?? 0) }
            return "\(cards) cards · \(rows.count) sets"
        }
        let questions = rows.reduce(0) { $0 + ($1.content.questions?.count ?? 0) }
        return "\(questions) questions · \(rows.count) sets"
    }
    private var chapters: [String] {
        Array(Set(entries.map(\.document))).sorted { left,right in
            let notes = catalog.catalog?.notes ?? []
            let a = notes.first { $0.subject == currentSubject && $0.displayName == left }?.sortOrder ?? Int.max
            let b = notes.first { $0.subject == currentSubject && $0.displayName == right }?.sortOrder ?? Int.max
            return a == b ? left.localizedStandardCompare(right) == .orderedAscending : a < b
        }
    }
    private var orderedEntries: [StudyEntry] {
        let headings = catalog.catalog?.notes.first { $0.subject == currentSubject && $0.displayName == currentChapter }?.headings ?? []
        return entries.sorted { left,right in
            let a = headings.firstIndex { $0.text.caseInsensitiveCompare(left.title) == .orderedSame } ?? Int.max
            let b = headings.firstIndex { $0.text.caseInsensitiveCompare(right.title) == .orderedSame } ?? Int.max
            return a == b ? left.title.localizedStandardCompare(right.title) == .orderedAscending : a < b
        }
    }
}
