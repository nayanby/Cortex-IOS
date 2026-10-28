import SwiftUI

struct CortexArtwork: View {
    let name: String
    var size: CGFloat = 40
    var body: some View {
        Image("art_" + name).resizable().scaledToFit().frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct CortexHeader: View {
    let title: String
    var isHome = false
    let leading: () -> Void
    let search: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: leading) { CortexArtwork(name: isHome ? "menu" : "back", size: 28).frame(width: 40, height: 48) }
                .accessibilityLabel(isHome ? "Open menu" : "Back")
            Text(title).font(CortexStyle.title(isHome ? 24 : 20))
                .foregroundStyle(isHome ? Color(hex: 0x87434D) : CortexStyle.ink).lineLimit(1)
            Spacer(minLength: 4)
            Button(action: search) { CortexArtwork(name: "search", size: 28).frame(width: 44, height: 48) }
                .accessibilityLabel("Search")
        }.padding(.horizontal, 12).frame(height: 56).background(.white)
            .overlay(alignment: .bottom) { CortexStyle.line.frame(height: 1) }
    }
}

struct CortexBottomNavigation: View {
    var selected = "home"
    let action: (String) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(["home", "create", "flashcards", "quiz"], id: \.self) { item in
                Button { action(item) } label: {
                    CortexArtwork(name: item, size: 40).frame(width: 56, height: 48)
                        .background(selected == item ? Color(hex: 0xE4EBFA) : .clear, in: Capsule())
                }.accessibilityLabel(item == "quiz" ? "Qbank" : item.capitalized)
            }
        }.padding(.horizontal, 16).frame(width:256,height:56)
            .background(.white, in: Capsule()).overlay(Capsule().stroke(CortexStyle.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            .padding(.bottom, 10).frame(maxWidth: .infinity)
    }
}

struct ConsumerHomeView: View {
    @EnvironmentObject private var session: AccountSession
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject private var history = ReadingHistory.shared
    @ObservedObject private var studies = StudyLibrary.shared
    @ObservedObject private var studyProgress = StudyProgress.shared
    @State private var path:[String] = []
    @State private var drawer = false
    @State private var showAccount = false
    @State private var searching = false
    @State private var query = ""
    @State private var showingAISettings = false

    var body: some View {
        NavigationStack(path:$path) {
            ZStack(alignment: .leading) {
                VStack(spacing: 0) {
                    CortexHeader(title: "Cortex", isHome: true, leading: { drawer = true }, search: { searching.toggle() })
                    if searching {
                        TextField("Search notes and headings", text: $query).textFieldStyle(.roundedBorder).padding(12)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if searching, !query.isEmpty { searchResults }
                            else { homeContents }
                        }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 90)
                    }
                }
                .background(CortexStyle.background)
                .overlay(alignment: .bottom) {
                    CortexBottomNavigation { item in
                        path = item == "home" ? [] : [item]
                    }
                }
                if drawer { drawerContents }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAISettings) { AISettingsView() }
            .navigationDestination(for:String.self) { route in
                switch route {
                case "create": CreateStudyView()
                case "flashcards": StudyBrowser(kind:"Flashcards")
                case "quiz": StudyBrowser(kind:"Qbank")
                case "Deep dive": LibraryView(accountID:OfflineLibrary.available ? nil : session.profile?.uid)
                case "Snapshots", "Slides": StudyBrowser(kind:route)
                default: UtilityView(name:route)
                }
            }
            .sheet(isPresented: $showAccount) { ConsumerAccountView() }
        }.tint(CortexStyle.ink).environment(\.consumerTabAction,{item in path = item == "home" ? [] : [item]})
    }

    private var homeContents: some View {
        Group {
            NavigationLink(value:"Deep dive") {
                homeCard("DEEP DIVE", "Long form notes, flashcards and Qbank", "book", 0xEAF3FC, 0xCFE1F5)
            }.buttonStyle(.plain)
            Button { path = ["Snapshots"] } label: { homeCard("SNAPSHOTS", "Concise notes", "snapshot", 0xF0E8EB, 0xE1D0DC) }.buttonStyle(.plain)
            Button { path = ["PDFs"] } label: { homeCard("PDFS", "Import a PDF and mark it with the pen", "pdf", 0xE8F2EA, 0xCFE4D4) }.buttonStyle(.plain)
            Button { path = ["Notebooks"] } label: { homeCard("NOTEBOOKS", "Same paper width as notes, blank or 8 mm ruling", "notebook", 0xF6EFE4, 0xE8D9C4) }.buttonStyle(.plain)
            Text("Continue reading").font(CortexStyle.title(18)).padding(.top,6)
            let recent = history.recent.compactMap { record in library.catalog?.notes.first { $0.path == record.path } }
            if recent.isEmpty {
                VStack(alignment:.leading,spacing:2) {
                    Text("No notes opened yet").font(CortexStyle.title(16))
                    Text("Notes you open will appear here.").font(.system(size:12)).foregroundStyle(CortexStyle.muted)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
                    .background(.white,in:RoundedRectangle(cornerRadius:12))
                    .overlay(RoundedRectangle(cornerRadius:12).stroke(CortexStyle.line,lineWidth:1))
                NavigationLink(value:"Deep dive") {
                    Text("Find your first topic")
                }.buttonStyle(ConsumerButtonStyle())
            } else {
                ForEach(Array(recent.prefix(3))) { note in
                    NavigationLink { SharedNoteView(note:note) } label: {
                        LibraryCard(title:note.displayName,subtitle:note.subject,symbol:"doc.text")
                    }.buttonStyle(.plain)
                }
            }
            Text("Previously Reviewed").font(CortexStyle.title(16)).padding(.top,8)
            let snapshots = studyProgress.recentStudy.compactMap { id in studies.entries.first {$0.id == id && $0.kind == "Snapshots"} }
            if snapshots.isEmpty {
                Text("No snapshots opened yet").font(CortexStyle.title(16))
                Text("Snapshots you open will appear here.").font(.system(size:12)).foregroundStyle(CortexStyle.muted)
            } else {
                ForEach(Array(snapshots.prefix(5))) { entry in
                    NavigationLink { StudyDetail(entry:entry) } label: { LibraryCard(title:entry.title,subtitle:entry.document,symbol:"doc.text") }.buttonStyle(.plain)
                }
            }
        }.foregroundStyle(CortexStyle.ink)
    }

    private var searchResults: some View {
        ForEach((library.catalog?.notes ?? []).filter { $0.matches(query) }) { note in
            NavigationLink { SharedNoteView(note: note) } label: {
                LibraryCard(title: note.displayName, subtitle: note.subject, symbol: "doc.text")
            }.buttonStyle(.plain)
        }
    }

    private func homeCard(_ title: String, _ subtitle: String, _ icon: String, _ start: UInt, _ end: UInt) -> some View {
        HStack(spacing: 12) {
            CortexArtwork(name: icon, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(CortexStyle.title(16))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(CortexStyle.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            CortexArtwork(name: "right", size: 22)
        }.foregroundStyle(CortexStyle.ink).padding(16).frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(gradient(start, end), in: RoundedRectangle(cornerRadius: 16))
    }

    private var drawerContents: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { drawer = false }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Button { drawer = false } label: { Image(systemName: "xmark").frame(width: 44, height: 48) }
                    Text("Cortex").font(CortexStyle.title(18))
                }
                Divider()
                Button { drawer = false;path = [] } label: { drawerRow("Home", "home") }
                NavigationLink(value:"Deep dive") { drawerRow("Deep dive", "book") }
                    .simultaneousGesture(TapGesture().onEnded { drawer = false })
                ForEach([("Snapshots", "snapshot"), ("Notebooks", "notebook"), ("PDFs", "pdf"), ("Performance", "quiz"), ("Storage", "storage")], id: \.0) { item in
                    Button { drawer = false; path = [item.0] } label: { drawerRow(item.0, item.1) }
                }
                Divider().padding(.vertical,8)
                Button { drawer = false; showingAISettings = true } label: { drawerRow("AI settings", "settings") }
                Button { drawer = false; path = ["create"] } label: { drawerRow("Create with AI", "create") }
                Button { drawer = false; if session.profile != nil { showAccount = true } else { path = ["Account sign-in"] } } label: { drawerRow("Account", "settings") }
                Button { drawer = false; path = ["How-to"] } label: { drawerRow("How-to", "help") }
                Spacer()
            }.padding(12).frame(width: 260).background(.white)
        }.buttonStyle(.plain).foregroundStyle(CortexStyle.ink)
    }

    private func drawerRow(_ label: String, _ icon: String) -> some View {
        HStack(spacing: 12) { Image("consumer_" + (["snapshot":"snapshots","notebook":"notebooks","quiz":"performance","settings":"account","create":"book"][icon] ?? icon)).resizable().scaledToFit().frame(width:22,height:22); Text(label).font(CortexStyle.title(16)); Spacer() }
            .padding(.horizontal, 4).frame(height: 44).contentShape(Rectangle())
    }
    private func gradient(_ start: UInt, _ end: UInt) -> LinearGradient {
        LinearGradient(colors: [Color(hex: start), Color(hex: end)], startPoint: .leading, endPoint: .trailing)
    }
}

extension Color {
    init(hex: UInt) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
