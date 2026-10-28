import SwiftUI

struct FlashcardPlayer: View {
    let entry:StudyEntry
    var documentOrder = false
    var limit = Int.max
    @ObservedObject private var progress = StudyProgress.shared
    @ObservedObject private var library = StudyLibrary.shared
    @EnvironmentObject private var catalog:LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var queue:[Int] = []
    @State private var revealed = false
    @State private var initialized = false
    private var cards:[StudyCard] { entry.content.cards ?? [] }
    private var current:Int? { queue.first }
    private var source:StudyEntry? {
        guard let current,cards.indices.contains(current) else {return nil}
        return library.entries.first {$0.id == (cards[current].sourceEntryID ?? entry.id)}
    }
    private var note:LibraryNote? {
        guard let source else {return nil}
        return catalog.catalog?.notes.first {$0.subject.caseInsensitiveCompare(source.folder) == .orderedSame && $0.displayName.caseInsensitiveCompare(source.document) == .orderedSame}
    }
    var body: some View {
        VStack(spacing:0) {
            if let current,cards.indices.contains(current) {
                Text("\(entry.title) · \(queue.count) cards left").font(.system(size:12,weight:.bold)).foregroundStyle(CortexStyle.muted)
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,20).padding(.top,14)
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment:.leading,spacing:16) {
                            Text(.init(cards[current].front)).font(CortexStyle.title(20)).textSelection(.enabled)
                            if revealed { Text(.init(cards[current].back)).font(.custom("AveriaSerifLibre-Regular",size:17)).textSelection(.enabled) }
                            Spacer(minLength:24)
                            if let source {
                                VStack(spacing:2) {
                                    Text(source.title).font(CortexStyle.title(15))
                                    Text(source.document).font(.system(size:13))
                                    Text(source.folder).font(.system(size:11)).foregroundStyle(CortexStyle.muted)
                                }.multilineTextAlignment(.center).frame(maxWidth:.infinity)
                            }
                        }.padding(20).frame(maxWidth:.infinity,minHeight:max(0,geometry.size.height),alignment:.topLeading)
                    }.background(.white,in:RoundedRectangle(cornerRadius:16))
                        .overlay(RoundedRectangle(cornerRadius:16).stroke(CortexStyle.line,lineWidth:1))
                        .shadow(color:.black.opacity(0.07),radius:2,y:2)
                }.padding(16)
                if let note {
                    NavigationLink { SharedNoteView(note:note) } label: { Text("Go to notes").font(.system(size:14)).frame(maxWidth:.infinity,minHeight:44) }.buttonStyle(.plain)
                }
                if revealed {
                    HStack(spacing:8) {
                        ForEach(Array(["Again","Hard","Good","Easy"].enumerated()),id:\.offset) { grade,title in
                            Button(title) { rate(grade,current:current) }.buttonStyle(ConsumerButtonStyle(outlined:grade < 2))
                        }
                    }.padding(.horizontal,16).padding(.bottom,16)
                } else {
                    Button("Show answer") { revealed = true }.buttonStyle(ConsumerButtonStyle()).padding(.horizontal,16).padding(.bottom,16)
                }
            } else {
                Spacer()
                Text("All done for now").font(CortexStyle.title(19))
                Text("Your review ratings have been saved.").font(.system(size:14)).foregroundStyle(CortexStyle.muted).padding(.top,8)
                Button("Back") { dismiss() }.buttonStyle(ConsumerButtonStyle()).frame(maxWidth:220).padding(.top,20)
                Spacer()
            }
        }.foregroundStyle(CortexStyle.ink).cortexPage("Flashcards")
            .onAppear {
                guard !initialized else {return};initialized = true
                queue = Array((documentOrder ? Array(cards.indices) : progress.dueQueue(entry)).prefix(limit))
                progress.opened(entry)
            }
    }
    private func rate(_ grade:Int,current:Int) {
        let card = cards[current]
        progress.review(entry:card.sourceEntryID ?? entry.id,index:card.sourceIndex ?? current,grade:grade)
        queue.removeFirst()
        if grade == 0 {queue.append(current)}
        revealed = false
    }
}
