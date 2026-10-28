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
    let kind:String
    var note:LibraryNote? = nil
    @EnvironmentObject private var catalog:LibraryStore
    @ObservedObject private var library = StudyLibrary.shared
    @ObservedObject private var progress = StudyProgress.shared
    @State private var subjects:Set<String> = ["all"]
    @State private var topics:Set<String> = []
    @State private var counts:Set<String> = ["30"]
    @State private var picker:String?
    @State private var settings = false
    @State private var solving = false
    @State private var creating = false
    @State private var combined:StudyEntry?
    @State private var documentOrder = false
    @State private var query = ""
    private var entries:[StudyEntry] { StudySelection.scope(library.entries,kind:kind,subject:note?.subject,chapter:note?.displayName) }
    private var subject:String? { subjects.first == "all" ? nil : subjects.first }
    private var scoped:[StudyEntry] { entries.filter { subject == nil || $0.folder == subject } }
    private var chosen:[StudyEntry] { topics.isEmpty ? scoped : scoped.filter { topics.contains($0.id) } }
    private var cardLimit:Int { Int(counts.first ?? "30") ?? Int.max }
    private var count:Int { chosen.reduce(0) { $0 + (kind == "Flashcards" ? ($1.content.cards?.count ?? 0) : ($1.content.questions?.count ?? 0)) } }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                if kind == "Qbank" && !solving {
                    ConsumerCallout(text:"Solve a Qbank already written, or create a new one.")
                    Button { solving = true } label: { actionCard("Solve Qbank",blue:true) }.buttonStyle(.plain)
                    Button { creating = true } label: { actionCard("Create Qbank",blue:false) }.buttonStyle(.plain)
                } else {
                    ConsumerCallout(text:kind == "Flashcards" ? "Tick all topics or the headings of them, then solve what is due or make more cards." : "Choose the subject and topics you want to solve.")
                    if note == nil { ConsumerField(title:"Subject",value:subject ?? "All subjects") { picker = "Subject" } }
                    if subject != nil || note != nil {
                        ConsumerField(title:note == nil ? "Topics" : "Study material",value:topics.isEmpty ? "All topics" : "\(topics.count) headings") { picker = "Topics" }
                    }
                    if let error = library.loadError { Text(error).font(.system(size:13)).foregroundStyle(.red) }
                    if kind == "Flashcards" {
                        HStack(spacing:8) {
                            ConsumerCallout(text:"\(count) flashcards · \(chosen.reduce(0) { $0 + progress.dueQueue($1).count }) ready to review")
                            Button { settings = true } label: { CortexArtwork(name:"settings",size:20).frame(width:46,height:46).overlay(RoundedRectangle(cornerRadius:10).stroke(CortexStyle.line,lineWidth:1)) }.buttonStyle(.plain).accessibilityLabel("Flashcard settings")
                        }
                        ConsumerField(title:"Number of flashcards",value:cardLimit == Int.max ? "All flashcards" : "\(cardLimit) flashcards") { picker = "Number of flashcards" }
                        HStack(spacing:8) {
                            Button("Solve Due Today") { start(ordered:false) }.buttonStyle(ConsumerButtonStyle())
                            Button("Solve In Document Order") { start(ordered:true) }.buttonStyle(ConsumerButtonStyle(outlined:true))
                        }.disabled(count == 0)
                        Button("Add More Flashcards") { creating = true }.buttonStyle(ConsumerButtonStyle())
                    } else {
                        Text("Ready-made Qbanks").font(CortexStyle.title(15))
                        Button("Solve selected topics · \(count) questions") { start(ordered:true) }.buttonStyle(ConsumerButtonStyle()).disabled(count == 0)
                        ForEach(chosen.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.document.localizedCaseInsensitiveContains(query) }) { entry in
                            NavigationLink { QuizPlayer(entry:entry) } label: {
                                VStack(alignment:.leading,spacing:4) {
                                    Text(entry.title).font(CortexStyle.title(16))
                                    Text(entry.document + " · \(entry.content.questions?.count ?? 0) questions").font(.system(size:12)).foregroundStyle(CortexStyle.muted)
                                }.frame(maxWidth:.infinity,alignment:.leading).padding(12)
                                    .background(CortexStyle.background,in:RoundedRectangle(cornerRadius:9))
                                    .overlay(RoundedRectangle(cornerRadius:9).stroke(CortexStyle.line,lineWidth:1))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.consumerPanel().padding(.horizontal,12).padding(.top,kind == "Flashcards" ? 12 : 6).padding(.bottom,12)
        }.foregroundStyle(CortexStyle.ink).cortexPage(kind,search:kind == "Qbank" && solving ? $query : nil)
            .consumerTabs(kind == "Qbank" ? "quiz" : "flashcards",visible:note == nil)
            .onChange(of:subjects) { _,_ in topics.removeAll() }
            .sheet(isPresented:Binding(get:{picker != nil},set:{if !$0 {picker = nil}})) {
                if picker == "Subject" {
                    ConsumerPicker(title:"Subject",choices:subjectChoices,selected:$subjects)
                } else if picker == "Topics" {
                    ConsumerPicker(title:"Topics",choices:topicChoices,selected:$topics,multiple:true)
                } else {
                    ConsumerPicker(title:"Number of flashcards",choices:[10,20,30,50,100].map { ConsumerChoice(id:String($0),title:"\($0) flashcards") } + [ConsumerChoice(id:"all",title:"All flashcards")],selected:$counts)
                }
            }
            .sheet(isPresented:$settings) { ReviewSettingsView() }
            .navigationDestination(isPresented:$creating) { CreateStudyView(note:note,initialKind:kind) }
            .navigationDestination(isPresented:Binding(get:{combined != nil},set:{if !$0 {combined = nil}})) {
                if let combined {
                    if kind == "Flashcards" { FlashcardPlayer(entry:combined,documentOrder:documentOrder,limit:cardLimit) }
                    else { QuizPlayer(entry:combined) }
                }
            }
    }
    private var subjectChoices:[ConsumerChoice] {
        [ConsumerChoice(id:"all",title:"All subjects",detail:"\(entries.count) saved sets")] + Array(Set(entries.map(\.folder))).sorted().map { name in
            ConsumerChoice(id:name,title:name,detail:"\(entries.filter {$0.folder == name}.count) saved sets")
        }
    }
    private var topicChoices:[ConsumerChoice] {
        // Keep document and heading order, independently of a deck's card order.
        let notes = catalog.catalog?.notes ?? []
        return scoped.sorted { a,b in
            if a.document != b.document {
                let ai = notes.first {$0.subject == a.folder && $0.displayName == a.document}?.sortOrder ?? Int.max
                let bi = notes.first {$0.subject == b.folder && $0.displayName == b.document}?.sortOrder ?? Int.max
                return ai == bi ? a.document.localizedStandardCompare(b.document) == .orderedAscending : ai < bi
            }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }.map { ConsumerChoice(id:$0.id,title:$0.title,detail:$0.document) }
    }
    private func start(ordered:Bool) {
        documentOrder = ordered
        combined = StudySelection.aggregate(chosen,kind:kind,title:note?.displayName ?? subject ?? "All subjects",catalog:catalog.catalog)
    }
    private func actionCard(_ title:String,blue:Bool) -> some View {
        HStack {
            Text(title).font(CortexStyle.title(17));Spacer();CortexArtwork(name:"right",size:22)
        }.padding(18).background(LinearGradient(colors:blue ? [Color(hex:0xEAF3FC),Color(hex:0xCFE1F5)] : [Color(hex:0xEEEEF0),Color(hex:0xD8D9DD)],startPoint:.leading,endPoint:.trailing),in:RoundedRectangle(cornerRadius:16))
    }
}
