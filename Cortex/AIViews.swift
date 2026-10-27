import SwiftUI

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasKey = AISettings.key() != nil
    @State private var model = AISettings.model
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Google Gemini") {
                    SecureField(hasKey ? "Enter replacement API key" : "Gemini API key", text: $key)
                        .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Model", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text(hasKey ? "A Gemini key is stored securely on this iPad." : "No Gemini key saved.").font(.caption)
                    Button("Save settings") {
                        do {
                            let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { throw StudyAIError.message("Enter a valid model name.") }
                            if !key.isEmpty { try AISettings.saveKey(key); key = ""; hasKey = true }
                            AISettings.model = name
                            message = "Settings saved."
                        } catch { message = error.localizedDescription }
                    }
                    if hasKey { Button("Remove saved API key", role: .destructive) { AISettings.removeKey(); hasKey = false; key = ""; message = "Key removed." } }
                    Link("Get a Gemini API key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                }
                Section {
                    Text("Your key stays in this device’s Keychain. Only the topic and text you submit with Generate are sent directly to Google. Saved files remain available offline. AI generation requires internet and uses your Gemini quota.")
                        .font(.callout)
                }
                if let message { Text(message).font(.callout) }
            }.navigationTitle("AI settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct CreateStudyView: View {
    @Environment(\.dismiss) private var dismiss
    var note: LibraryNote? = nil
    var initialSource: String = ""
    @State private var kind = "Snapshots"
    @State private var topic = ""
    @State private var source = ""
    @State private var task: Task<Void, Never>?
    @State private var running = false
    @State private var error: String?
    @State private var created: StudyEntry?
    @State private var settings = false
    var body: some View {
        Form {
            Section("Create with AI") {
                Picker("Create", selection: $kind) {
                    ForEach(["Notes", "Snapshots", "Flashcards", "Qbank", "Slides"], id: \.self) { Text($0) }
                }
                TextField("Topic or instructions", text: $topic, axis: .vertical)
                Text("Source text (optional)").font(.caption)
                TextEditor(text: $source).frame(minHeight: 180)
                Text("Generate sends this topic and source text to Google Gemini using your saved API key.").font(.caption)
                Button("AI settings") { settings = true }
                if running {
                    ProgressView("Creating \(kind.lowercased())…")
                    Button("Cancel", role: .cancel) { task?.cancel() }
                } else {
                    Button("Generate and save") { generate() }.buttonStyle(.borderedProminent)
                        .disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            if let created {
                Section("Saved on this device") { NavigationLink("Open " + created.kind) { StudyDetail(entry: created) } }
            }
            Section("Your library") {
                ForEach(["Notes", "Snapshots", "Flashcards", "Qbank", "Slides"], id: \.self) { kind in
                    NavigationLink(kind) { StudyBrowser(kind: kind) }
                }
            }
        }.navigationTitle("Create with AI").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .sheet(isPresented: $settings) { AISettingsView() }
            .onAppear { if source.isEmpty { source = initialSource }; if topic.isEmpty { topic = note?.displayName ?? "" } }
            .onDisappear { task?.cancel() }
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
