import SwiftUI
import PencilKit

enum CortexInkMode: String, CaseIterable, Hashable { case pen, highlighter, underliner, eraser }
@MainActor
final class CortexInkSettings: ObservableObject {
    @Published private(set) var mode: CortexInkMode = .pen
    @Published private(set) var colorIndex = 0
    @Published private(set) var sizeIndex = 2
    @Published var drawing = false { didSet { onChange?() } }
    @Published var visible = true { didSet { onChange?() } }
    @Published var stylusOnly = false { didSet { onChange?() } }
    var onChange: (() -> Void)?
    private var lastMarking: CortexInkMode = .pen
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        colorIndex = min(2,max(0,defaults.integer(forKey: "ink.pen.color")))
        sizeIndex = min(4,max(0,defaults.object(forKey: "ink.pen.size") as? Int ?? 2))
    }
    var family: CortexInkMode { mode == .eraser ? lastMarking : mode }
    var hexColors: [UInt] {
        switch family {
        case .pen: return [0x28467C,0x6F3D5D,0xAF3E3E]
        case .highlighter: return [0xFFEAEA,0xFFF9BD,0xCCFBFA]
        case .underliner: return [0xE89090,0xD4C04A,0xB1E5E6]
        case .eraser: return []
        }
    }
    var colors: [UIColor] { hexColors.map { value in UIColor(red: CGFloat((value >> 16)&255)/255, green: CGFloat((value >> 8)&255)/255, blue: CGFloat(value&255)/255, alpha: 1) } }
    var sizes: [CGFloat] { family == .highlighter ? [8,11,14,18,22] : [1,1.5,2,3,4] }
    var tool: PKTool {
        if mode == .eraser { return PKEraserTool(.vector) }
        return PKInkingTool(mode == .highlighter ? .marker : .monoline, color: colors[colorIndex], width: sizes[sizeIndex])
    }
    func select(_ value: CortexInkMode) {
        mode = value
        if value != .eraser { lastMarking = value }
        colorIndex = min(2,max(0,defaults.integer(forKey: "ink." + family.rawValue + ".color")))
        sizeIndex = min(4,max(0,defaults.object(forKey: "ink." + family.rawValue + ".size") as? Int ?? 2))
        drawing = true; onChange?()
    }
    func color(_ index: Int) {
        guard colors.indices.contains(index) else { return }
        if mode == .eraser { mode = lastMarking }
        colorIndex = index; defaults.set(index, forKey: "ink." + family.rawValue + ".color")
        drawing = true; onChange?()
    }
    func size(_ index: Int) {
        guard sizes.indices.contains(index) else { return }
        sizeIndex = index; defaults.set(index, forKey: "ink." + family.rawValue + ".size"); onChange?()
    }
}

struct CortexInkToolbar: View {
    @ObservedObject var settings: CortexInkSettings
    let undo: () -> Void
    let redo: () -> Void
    let clear: () -> Void
    @State private var confirmClear = false
    @State private var options = false
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach([CortexInkMode.pen,.highlighter,.underliner,.eraser], id: \.self) { mode in
                    Button { if settings.drawing && settings.mode == mode {options = true} else {settings.select(mode)} } label: {
                        Image("consumer_tool_" + mode.rawValue).resizable().scaledToFit().frame(width:20,height:20)
                            .foregroundStyle(CortexStyle.ink).frame(width: 36,height: 38)
                            .background(settings.drawing && settings.mode == mode ? Color(hex:0xE4EBFA) : .clear,in:RoundedRectangle(cornerRadius:8))
                    }.accessibilityLabel(mode.rawValue.capitalized)
                }
                Button { settings.drawing = false } label: { Image("consumer_tool_cursor").resizable().scaledToFit().frame(width:20,height:20).frame(width:32,height:38) }.accessibilityLabel("Cursor and scroll")
                if settings.drawing {
                    ForEach(settings.colors.indices, id: \.self) { index in
                        Button { settings.color(index) } label: {
                            Circle().fill(Color(uiColor:settings.colors[index])).frame(width:24,height:24)
                                .overlay(Circle().stroke(settings.colorIndex == index ? CortexStyle.ink : Color.gray.opacity(0.4),lineWidth:settings.colorIndex == index ? 3 : 1))
                        }.accessibilityLabel(String(format:"Color #%06X",settings.hexColors[index]))
                    }
                    Menu {
                        ForEach(settings.sizes.indices,id: \.self) { index in Button("\(settings.sizes[index].formatted()) pt") { settings.size(index) } }
                        Toggle("Stylus only",isOn:$settings.stylusOnly)
                        Toggle("Show ink",isOn:$settings.visible)
                        Button("Delete ink",role:.destructive) { confirmClear = true }
                    } label: { Image(systemName:"slider.horizontal.3").frame(width:32,height:38) }
                }
                Button {options = true} label: {Image(systemName:"slider.horizontal.3").frame(width:32,height:38)}.accessibilityLabel("Pen settings")
                Button(action:undo) { Image("consumer_tool_undo").resizable().scaledToFit().frame(width:20,height:20).frame(width:32,height:38) }.accessibilityLabel("Undo")
                Button(action:redo) { Image("consumer_tool_redo").resizable().scaledToFit().frame(width:20,height:20).frame(width:32,height:38) }.accessibilityLabel("Redo")
            }.buttonStyle(.plain).foregroundStyle(CortexStyle.ink).padding(.horizontal,12).padding(.vertical,4)
        }.frame(height:48).background(.white).overlay(alignment:.top) { CortexStyle.line.frame(height:1) }
            .sheet(isPresented:$options) {ConsumerInkOptions(settings:settings,clear:{confirmClear = true})}
            .confirmationDialog("Delete all ink on this page?",isPresented:$confirmClear,titleVisibility:.visible) {
                Button("Delete ink",role:.destructive,action:clear)
            }
    }
    private func symbol(_ mode: CortexInkMode) -> String {
        switch mode { case .pen:return "pencil.tip";case .highlighter:return "highlighter";case .underliner:return "underline";case .eraser:return "eraser" }
    }
}
struct ConsumerInkOptions:View {
    @ObservedObject var settings:CortexInkSettings
    let clear:()->Void
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text("Pen settings").font(CortexStyle.title(18));Spacer();Button("Done") {dismiss()}.font(CortexStyle.title(16)).frame(minHeight:44)}
            toolRow("Pens",mode:.pen,hex:[0x28467C,0x6F3D5D,0xAF3E3E],sizes:[1,1.5,2,3,4])
            toolRow("Highlighters",mode:.highlighter,hex:[0xFFEAEA,0xFFF9BD,0xCCFBFA],sizes:[8,11,14,18,22])
            toolRow("Underliners",mode:.underliner,hex:[0xE89090,0xD4C04A,0xB1E5E6],sizes:[1,1.5,2,3,4])
            Toggle("Stylus only",isOn:$settings.stylusOnly)
            Toggle("Show ink",isOn:$settings.visible)
            Button("Delete ink",role:.destructive) {dismiss();clear()}.font(CortexStyle.title(14)).padding(.vertical,8)
        }.font(.system(size:13)).tint(CortexStyle.ink).foregroundStyle(CortexStyle.ink).padding(.horizontal,16).padding(.vertical,12).presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
    }
    private func toolRow(_ title:String,mode:CortexInkMode,hex:[UInt],sizes:[CGFloat]) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(CortexStyle.title(14))
            HStack(spacing:12) {
                ForEach(hex.indices,id:\.self) {index in
                    Button {settings.select(mode);settings.color(index)} label: {
                        Circle().fill(Color(hex:hex[index])).frame(width:30,height:30)
                            .overlay(Circle().stroke(settings.family == mode && settings.colorIndex == index ? CortexStyle.ink : CortexStyle.line,lineWidth:settings.family == mode && settings.colorIndex == index ? 2 : 1))
                    }.accessibilityLabel(title + String(format:" #%06X",hex[index]))
                }
                Spacer(minLength:4)
                Button {settings.select(mode);settings.size(max(0,settings.sizeIndex-1))} label: {Text("−").frame(width:32,height:36)}.accessibilityLabel("Decrease " + title + " width")
                Text(settings.family == mode ? sizes[settings.sizeIndex].formatted() : "—").font(.custom("AveriaSerifLibre-Regular",size:13)).frame(width:28)
                Button {settings.select(mode);settings.size(min(4,settings.sizeIndex+1))} label: {Text("+").frame(width:32,height:36)}.accessibilityLabel("Increase " + title + " width")
            }.buttonStyle(.plain)
        }
    }
}
