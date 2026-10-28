import SwiftUI

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasKey = AISettings.key() != nil
    @State private var model = AISettings.model
    @State private var message: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    ConsumerCallout(text:"Use your Google Gemini API key for Create with AI.")
                    Text("Gemini API key").font(CortexStyle.title(14))
                    SecureField(hasKey ? "Enter replacement API key" : "Gemini API key",text:$key)
                        .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(12).background(CortexStyle.background,in:RoundedRectangle(cornerRadius:9))
                        .overlay(RoundedRectangle(cornerRadius:9).stroke(CortexStyle.line,lineWidth:1))
                    Text("Model").font(CortexStyle.title(14))
                    TextField("Model",text:$model).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(12).background(CortexStyle.background,in:RoundedRectangle(cornerRadius:9))
                        .overlay(RoundedRectangle(cornerRadius:9).stroke(CortexStyle.line,lineWidth:1))
                    Text(hasKey ? "A Gemini key is stored securely on this iPad." : "No Gemini key saved.").font(.system(size:12)).foregroundStyle(CortexStyle.muted)
                    Button("Save settings") {
                        do {
                            let name = model.trimmingCharacters(in:.whitespacesAndNewlines)
                            guard name.range(of:"^[A-Za-z0-9._-]+$",options:.regularExpression) != nil else {throw StudyAIError.message("Enter a valid model name.")}
                            if !key.isEmpty {try AISettings.saveKey(key);key = "";hasKey = true}
                            AISettings.model = name;message = "Settings saved."
                        } catch {message = error.localizedDescription}
                    }.buttonStyle(ConsumerButtonStyle())
                    if hasKey {Button("Remove saved API key",role:.destructive) {AISettings.removeKey();hasKey = false;key = "";message = "Key removed."}.buttonStyle(ConsumerButtonStyle(outlined:true))}
                    Link("Get a Gemini API key",destination:URL(string:"https://aistudio.google.com/apikey")!).font(.system(size:14))
                    Text("Your key stays in this device’s Keychain. Only the topic and text you submit with Generate are sent directly to Google. Saved files remain available offline. AI generation requires internet and uses your Gemini quota.").font(.system(size:12)).foregroundStyle(CortexStyle.muted)
                    if let message {ConsumerCallout(text:message)}
                }.consumerPanel().padding(12)
            }.foregroundStyle(CortexStyle.ink).cortexPage("AI settings")
        }
    }
}

struct CreateStudyView: View {
    @Environment(\.dismiss) private var dismiss
    var note: LibraryNote? = nil
    var initialSource: String = ""
    var initialKind: String = "Notes"
    @State private var kind = "Notes"
    @State private var topic = ""
    @State private var source = ""
    @State private var task: Task<Void, Never>?
    @State private var running = false
    @State private var error: String?
    @State private var created: StudyEntry?
    @State private var settings = false
    @State private var initialized = false
    @State private var advanced = false
    @State private var pickingKind = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                VStack(alignment:.leading,spacing:14) {
                    ConsumerCallout(text:kind == "Notes" ? "Describe a topic to generate a note." : "Describe a topic to generate " + kind.lowercased() + ".")
                    VStack(alignment:.leading,spacing:5) {
                        Text(kind == "Notes" ? "Note topic" : "Topic").font(CortexStyle.title(14))
                        TextField("e.g. Approach to acute kidney injury",text:$topic,axis:.vertical)
                            .font(.custom("AveriaSerifLibre-Regular",size:16)).lineLimit(3...6).padding(12)
                            .background(CortexStyle.background,in:RoundedRectangle(cornerRadius:9))
                            .overlay(RoundedRectangle(cornerRadius:9).stroke(CortexStyle.line,lineWidth:1))
                    }
                    if running {
                        ProgressView("Creating \(kind.lowercased())…")
                        Button("Cancel") {task?.cancel()}.buttonStyle(ConsumerButtonStyle(outlined:true))
                    } else {
                        Button(kind == "Notes" ? "Generate note" : "Generate " + kind.lowercased()) {generate()}
                            .buttonStyle(ConsumerButtonStyle()).disabled(topic.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    }
                    DisclosureGroup("More options",isExpanded:$advanced) {
                        VStack(alignment:.leading,spacing:14) {
                            ConsumerField(title:"Create",value:kind) {pickingKind = true}
                            Text("Source text (optional)").font(CortexStyle.title(14))
                            TextEditor(text:$source).font(.system(size:14)).frame(minHeight:160)
                                .overlay(RoundedRectangle(cornerRadius:9).stroke(CortexStyle.line,lineWidth:1))
                            Button("AI settings") {settings = true}.font(CortexStyle.title(14))
                            Text("Generate sends this topic and source text to Google Gemini using your saved API key.").font(.system(size:12)).foregroundStyle(CortexStyle.muted)
                        }.padding(.top,14)
                    }.font(.system(size:13)).foregroundStyle(CortexStyle.muted)
                    if let error {Text(error).font(.system(size:13)).foregroundStyle(.red)}
                }.consumerPanel()
                if let created {
                    Text("Recently created").font(.system(size:13,weight:.bold)).foregroundStyle(CortexStyle.muted)
                    NavigationLink {StudyDetail(entry:created)} label: {LibraryCard(title:created.title,subtitle:created.kind,symbol:"doc.text")}.buttonStyle(.plain)
                }
            }.padding(.horizontal,12).padding(.top,6).padding(.bottom,12)
        }.foregroundStyle(CortexStyle.ink).cortexPage("Create with AI").consumerTabs("create",visible:note == nil)
            .sheet(isPresented:$settings) {AISettingsView()}
            .sheet(isPresented:$pickingKind) {
                ConsumerPicker(title:"Create",choices:["Notes","Snapshots","Flashcards","Qbank","Slides"].map {ConsumerChoice(id:$0,title:$0)},selected:Binding(get:{[kind]},set:{kind = $0.first ?? "Notes"}))
            }
            .onAppear {if !initialized {kind = initialKind;source = initialSource;topic = note?.displayName ?? "";initialized = true}}
            .onDisappear {task?.cancel()}
    }

    private func generate() {
        running = true; error = nil; created = nil
        let selectedKind = kind, selectedTopic = topic, selectedSource = source
        task = Task { @MainActor in
            defer { running = false }
            do {
                let entry = try await StudyAI.generate(kind: selectedKind, topic: selectedTopic, source: selectedSource,
                    folder: note?.subject ?? "Created", document: note?.displayName ?? "")
                try Task.checkCancellation()
                try StudyLibrary.shared.save(entry)
                created = entry
            } catch is CancellationError { }
            catch let failure as URLError where failure.code == .cancelled { }
            catch { self.error = error.localizedDescription }
        }
    }
}
