import SwiftUI

// Dimensions, colours and field anatomy from Consumer res/layout and res/values.
struct ConsumerButtonStyle: ButtonStyle {
    var outlined = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size:14,weight:.medium))
            .foregroundStyle(outlined ? CortexStyle.ink : .white)
            .frame(maxWidth:.infinity,minHeight:48)
            .background(outlined ? Color.white : CortexStyle.ink,in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(outlined ? CortexStyle.line : .clear,lineWidth:1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
struct ConsumerCallout: View {
    let text:String
    var body: some View {
        Text(text).font(.system(size:12)).foregroundStyle(Color(hex:0x28467C))
            .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,11).padding(.vertical,9)
            .background(Color(hex:0xE8EFF8),in:RoundedRectangle(cornerRadius:8))
    }
}
struct ConsumerField: View {
    let title:String
    let value:String
    let action:()->Void
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(CortexStyle.title(14))
            Button(action:action) {
                HStack(spacing:8) {
                    Text(value).font(.custom("AveriaSerifLibre-Regular",size:16)).multilineTextAlignment(.leading)
                    Spacer(minLength:4)
                    Image("consumer_expand").resizable().scaledToFit().frame(width:22,height:22)
                }.padding(.horizontal,12).padding(.vertical,10).frame(minHeight:46)
                    .background(CortexStyle.background,in:RoundedRectangle(cornerRadius:9))
                    .overlay(RoundedRectangle(cornerRadius:9).stroke(CortexStyle.line,lineWidth:1))
            }.buttonStyle(.plain).accessibilityLabel(title + ": " + value)
        }.foregroundStyle(CortexStyle.ink)
    }
}
struct ConsumerChoice: Identifiable {
    let id:String
    let title:String
    var detail:String = ""
    var depth:Int = 0
}
struct ConsumerPicker: View {
    let title:String
    let choices:[ConsumerChoice]
    @Binding var selected:Set<String>
    var multiple = false
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text(title).font(CortexStyle.title(18));Spacer()
                Button("Done") { dismiss() }.font(CortexStyle.title(16)).frame(minWidth:64,minHeight:48)
            }.padding(.leading,22).padding(.trailing,10).padding(.top,10)
            Rectangle().fill(CortexStyle.line).frame(height:1)
            if choices.count > 12 {
                TextField("Search",text:$query).font(.system(size:14)).padding(12)
                    .background(CortexStyle.background,in:RoundedRectangle(cornerRadius:9)).padding(.horizontal,16).padding(.vertical,8)
            }
            ScrollView {
                LazyVStack(spacing:0) {
                    ForEach(choices.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query) }) { row in
                        Button {
                            if multiple {
                                if selected.contains(row.id) { selected.remove(row.id) } else { selected.insert(row.id) }
                            } else { selected = [row.id]; dismiss() }
                        } label: {
                            HStack(spacing:12) {
                                VStack(alignment:.leading,spacing:4) {
                                    Text(row.title).font(.custom("AveriaSerifLibre-Regular",size:16)).multilineTextAlignment(.leading)
                                    if !row.detail.isEmpty { Text(row.detail).font(.system(size:12)).foregroundStyle(CortexStyle.muted).multilineTextAlignment(.leading) }
                                }
                                Spacer(minLength:4)
                                Image(systemName:selected.contains(row.id) ? "checkmark" : (multiple ? "square" : "circle")).font(.system(size:18,weight:.semibold)).frame(width:24)
                            }.padding(.leading,22+CGFloat(row.depth)*16).padding(.trailing,22).padding(.vertical,14).frame(minHeight:54)
                                .background(selected.contains(row.id) ? Color(hex:0xE8EFF8).opacity(0.65) : .clear)
                        }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(row.id) ? .isSelected : [])
                    }
                }
            }
        }.foregroundStyle(CortexStyle.ink).background(.white)
            .presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
    }
}
private struct ConsumerPageModifier: ViewModifier {
    let title:String
    var query:Binding<String>?
    var onBack:(()->Void)? = nil
    @State private var searching = false
    @Environment(\.dismiss) private var dismiss
    func body(content:Content) -> some View {
        content.background(CortexStyle.background).toolbar(.hidden,for:.navigationBar)
            .safeAreaInset(edge:.top,spacing:0) {
                VStack(spacing:0) {
                    HStack(spacing:12) {
                        Button {if let onBack {onBack()} else {dismiss()}} label: { CortexArtwork(name:"back",size:28).frame(width:40,height:48) }.accessibilityLabel("Back")
                        Text(title).font(CortexStyle.title(20)).lineLimit(1);Spacer(minLength:4)
                        if query != nil {
                            Button { searching.toggle() } label: { CortexArtwork(name:"search",size:28).frame(width:44,height:48) }.accessibilityLabel("Search")
                        }
                    }.padding(.horizontal,12).frame(height:56)
                    if searching,let query {
                        TextField("Search",text:query).font(.system(size:14)).padding(12)
                            .background(CortexStyle.background,in:RoundedRectangle(cornerRadius:9)).padding(12)
                    }
                    Rectangle().fill(CortexStyle.line).frame(height:1)
                }.foregroundStyle(CortexStyle.ink).background(.white)
            }
    }
}
extension View {
    func cortexPage(_ title:String,search:Binding<String>? = nil,onBack:(()->Void)? = nil) -> some View {modifier(ConsumerPageModifier(title:title,query:search,onBack:onBack))}
    func consumerPanel() -> some View {
        self.padding(.horizontal,18).padding(.top,16).padding(.bottom,20).frame(maxWidth:.infinity,alignment:.topLeading)
            .background(.white,in:RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).stroke(CortexStyle.line,lineWidth:1))
    }
}
struct ConsumerToolbar<Actions:View>: View {
    let title:String
    @ViewBuilder let actions:()->Actions
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack(spacing:8) {
            Button {dismiss()} label: {CortexArtwork(name:"back",size:28).frame(width:40,height:48)}.accessibilityLabel("Back")
            Text(title).font(CortexStyle.title(20)).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
            actions().font(CortexStyle.title(16)).buttonStyle(.plain).labelStyle(.iconOnly)
        }.padding(.horizontal,12).frame(height:56).foregroundStyle(CortexStyle.ink).background(.white)
            .overlay(alignment:.bottom) {CortexStyle.line.frame(height:1)}
    }
}
extension View {
    func cortexToolbar<Actions:View>(_ title:String,@ViewBuilder actions:@escaping ()->Actions) -> some View {
        self.toolbar(.hidden,for:.navigationBar).safeAreaInset(edge:.top,spacing:0) {ConsumerToolbar(title:title,actions:actions)}
    }
}
struct ConsumerTypeSettings: View {
    @Binding var delta:Double
    @Binding var line:Double
    @Binding var paragraph:Double
    var defaultLine = 1.4375
    @Environment(\.dismiss) private var dismiss
    private let paragraphs = [0.08,0.11313708498984761,0.16,0.22627416997969524,0.32]
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {Text("Font settings").font(CortexStyle.title(18));Spacer();Button("Done") {dismiss()}.font(CortexStyle.title(16)).frame(minHeight:44)}
            step("Font size",value:String(format:"%.2f pt",12.25+delta),minus:{delta = max(-1,delta-1)},plus:{delta = min(12,delta+1)})
            step("Line spacing",value:String(format:"%.2f",line),minus:{line = max(1,line-0.0625)},plus:{line = min(2,line+0.0625)})
            step("Paragraph spacing",value:String(format:"%.2f",paragraph),minus:{changeParagraph(-1)},plus:{changeParagraph(1)})
            Button("Reset to default") {delta = 0;line = defaultLine;paragraph = 0.16}.buttonStyle(ConsumerButtonStyle(outlined:true))
        }.padding(22).foregroundStyle(CortexStyle.ink).presentationDetents([.medium]).presentationDragIndicator(.visible)
    }
    private func changeParagraph(_ offset:Int) {
        let index = paragraphs.indices.min {abs(paragraphs[$0]-paragraph) < abs(paragraphs[$1]-paragraph)} ?? 2
        paragraph = paragraphs[min(max(0,index+offset),paragraphs.count-1)]
    }
    private func step(_ title:String,value:String,minus:@escaping ()->Void,plus:@escaping ()->Void) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(CortexStyle.title(14))
            HStack(spacing:0) {
                Button(action:minus) {Text("−").font(.system(size:20)).frame(width:52,height:46)}.accessibilityLabel("Decrease " + title)
                Text(value).font(.custom("AveriaSerifLibre-Regular",size:16)).frame(maxWidth:.infinity)
                Button(action:plus) {Text("+").font(.system(size:20)).frame(width:52,height:46)}.accessibilityLabel("Increase " + title)
            }.buttonStyle(.plain).background(CortexStyle.background,in:RoundedRectangle(cornerRadius:9))
                .overlay(RoundedRectangle(cornerRadius:9).stroke(CortexStyle.line,lineWidth:1))
        }
    }
}
private struct ConsumerTabActionKey:EnvironmentKey {
    static let defaultValue:((String)->Void)? = nil
}
extension EnvironmentValues {
    var consumerTabAction:((String)->Void)? {
        get {self[ConsumerTabActionKey.self]}
        set {self[ConsumerTabActionKey.self] = newValue}
    }
}
private struct ConsumerTabsModifier:ViewModifier {
    let selected:String
    let visible:Bool
    @Environment(\.consumerTabAction) private var action
    func body(content:Content) -> some View {
        content.safeAreaInset(edge:.bottom,spacing:0) {
            if visible,let action {
                CortexBottomNavigation(selected:selected,action:action).padding(.top,8).background(CortexStyle.background.opacity(0.96))
            }
        }
    }
}
extension View {
    func consumerTabs(_ selected:String,visible:Bool = true) -> some View {modifier(ConsumerTabsModifier(selected:selected,visible:visible))}
}
