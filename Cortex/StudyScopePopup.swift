import SwiftUI

struct StudyScopePopup:View {
    let subjects:[ConsumerChoice]
    let topics:[ConsumerChoice]
    @Binding var selectedSubject:Set<String>
    @Binding var selectedTopics:Set<String>
    var startsWithTopics = false
    let close:()->Void
    @State private var showingTopics = false
    @State private var query = ""
    private var subjectName:String {selectedSubject.first == "all" ? "All subjects" : selectedSubject.first ?? "All subjects"}
    var body:some View {
        GeometryReader {geometry in
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform:close)
                VStack(spacing:0) {
                    HStack(spacing:12) {
                        if showingTopics {
                            Button {showingTopics = false;query = ""} label: {Label("Back",systemImage:"chevron.left").font(CortexStyle.title(16)).frame(minHeight:48)}
                        }
                        VStack(alignment:.leading,spacing:2) {
                            Text(showingTopics ? "Select topics" : "Select subject").font(CortexStyle.title(20))
                            if showingTopics {Text(subjectName).font(.system(size:13)).foregroundStyle(CortexStyle.muted)}
                        }
                        Spacer(minLength:4)
                        Button("Done",action:close).font(CortexStyle.title(16)).frame(minWidth:56,minHeight:48)
                    }.padding(.horizontal,20).padding(.vertical,8)
                    CortexStyle.line.frame(height:1)
                    TextField(showingTopics ? "Search chapters and headings" : "Search subjects",text:$query)
                        .font(.system(size:15)).padding(12).background(CortexStyle.background,in:RoundedRectangle(cornerRadius:9)).padding(16)
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:0) {
                            if showingTopics {
                                Button {selectedTopics.removeAll()} label: {
                                    row("All topics",detail:"Use every saved heading in this subject",selected:selectedTopics.isEmpty)
                                }.buttonStyle(.plain)
                                ForEach(topics.filter {query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query)}) {choice in
                                    Button {
                                        if selectedTopics.contains(choice.id) {selectedTopics.remove(choice.id)} else {selectedTopics.insert(choice.id)}
                                    } label: {row(choice.title,detail:choice.detail,selected:selectedTopics.contains(choice.id))}.buttonStyle(.plain)
                                }
                                if topics.isEmpty {Text("No saved topics in this subject.").font(.system(size:15)).foregroundStyle(CortexStyle.muted).padding(20)}
                            } else {
                                ForEach(subjects.filter {query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)}) {choice in
                                    Button {
                                        if selectedSubject != [choice.id] {selectedTopics.removeAll()}
                                        selectedSubject = [choice.id];query = "";showingTopics = true
                                    } label: {row(choice.title,detail:choice.detail,selected:selectedSubject.contains(choice.id),opens:true)}.buttonStyle(.plain)
                                }
                            }
                        }
                    }.scrollDismissesKeyboard(.interactively)
                    if showingTopics {
                        CortexStyle.line.frame(height:1)
                        HStack {Text(selectedTopics.isEmpty ? "All topics selected" : "\(selectedTopics.count) headings selected").font(.system(size:13));Spacer();Button("Use selection",action:close).buttonStyle(ConsumerButtonStyle()).frame(width:160)}.padding(16)
                    }
                }.foregroundStyle(CortexStyle.ink).background(.white,in:RoundedRectangle(cornerRadius:20))
                    .frame(width:min(860,max(280,geometry.size.width-24)),height:max(320,geometry.size.height-24))
                    .shadow(color:.black.opacity(0.2),radius:20,y:8).accessibilityAddTraits(.isModal)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.onAppear {showingTopics = startsWithTopics}.onExitCommand(perform:close)
    }
    private func row(_ title:String,detail:String,selected:Bool,opens:Bool = false) -> some View {
        HStack(spacing:14) {
            VStack(alignment:.leading,spacing:5) {
                Text(title).font(.custom("AveriaSerifLibre-Regular",size:18)).multilineTextAlignment(.leading)
                if !detail.isEmpty {Text(detail).font(.system(size:13)).foregroundStyle(CortexStyle.muted).multilineTextAlignment(.leading)}
            }
            Spacer(minLength:4)
            Image(systemName:opens ? "chevron.right" : (selected ? "checkmark.square.fill" : "square")).font(.system(size:22))
        }.padding(.horizontal,22).padding(.vertical,16).frame(maxWidth:.infinity,minHeight:64,alignment:.leading)
            .background(selected ? Color(hex:0xE8EFF8).opacity(0.7) : .clear)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
