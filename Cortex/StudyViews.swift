import SwiftUI

struct StudyBrowser: View {
    let kind: String
    var note: LibraryNote? = nil
    @ObservedObject private var library = StudyLibrary.shared
    @State private var query = ""
    @State private var showingReviewSettings = false
    @ObservedObject private var progress = StudyProgress.shared
    var body: some View {
        if kind == "Snapshots" { SnapshotLibraryView(note:note) }
        else { browserBody }
    }
    private var browserBody: some View {
        List {
            if let error = library.loadError { Text(error).foregroundStyle(.red) }
            let entries = library.matching(kind: kind, note: note).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.document.localizedCaseInsensitiveContains(query) || $0.folder.localizedCaseInsensitiveContains(query) }
            if entries.isEmpty {
                ContentUnavailableView("No saved \(kind.lowercased())", systemImage: "books.vertical", description: Text("No matching saved content is included in this local catalog."))
            }
            ForEach(entries) { entry in
                NavigationLink { StudyDetail(entry: entry) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.title).font(CortexStyle.title(17))
                        Text(entry.folder + " · " + entry.document).font(.caption).foregroundStyle(CortexStyle.muted)
                        if let cards = entry.content.cards { Text("\(cards.count) cards · \(progress.dueQueue(entry).count) ready to review").font(.caption2) }
                        if let questions = entry.content.questions { Text("\(questions.count) questions").font(.caption2) }
                    }
                }
            }
        }.searchable(text: $query).navigationTitle(kind).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                if kind == "Flashcards" { Button { showingReviewSettings = true } label: { Label("Review settings", systemImage: "gearshape") } }
            }
            .sheet(isPresented: $showingReviewSettings) { ReviewSettingsView() }
    }
}

struct StudyDetail: View {
    let entry: StudyEntry
    @State private var cardIndex = 0
    @State private var revealed = false
    @State private var reviewQueue: [Int] = []
    @State private var reviewReady = false
    @State private var reviewFinished = false
    @State private var answers: [Int: Int] = [:]
    @ObservedObject private var progress = StudyProgress.shared
    @State private var recordedQuiz = false
    @State private var showingFonts = false
    @AppStorage("snapshot.fontSize") private var fontSize = 16.0
    @AppStorage("snapshot.lineSpacing") private var lineSpacing = 6.0
    var body: some View {
        if entry.kind == "Snapshots" { SnapshotReader(entry:entry) }
        else if entry.kind == "Slides" { SlideDeckView(entry: entry) }
        else { contentBody }
    }
    private var contentBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(entry.content.title ?? entry.title).font(CortexStyle.title(24))
                if let cards = entry.content.cards, !cards.isEmpty {
                    if reviewFinished {
                        ContentUnavailableView("No more cards in this session", systemImage: "checkmark.circle", description: Text("Your review ratings have been saved."))
                        Button("Review all cards") { reviewQueue = Array(cards.indices); cardIndex = 0; reviewFinished = false }
                    } else {
                    Text("Card \(cardIndex + 1) of \(cards.count)").font(.caption)
                    Text(.init(cards[cardIndex].front)).font(.title3).frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                    Button(revealed ? "Hide answer" : "Show answer") { revealed.toggle() }.buttonStyle(.borderedProminent)
                    if revealed {
                        Text(.init(cards[cardIndex].back)).padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        HStack {
                            ForEach(Array(["Again", "Hard", "Good", "Easy"].enumerated()), id: \.offset) { grade, title in
                                Button(title) {
                                    progress.review(entry: entry.id, index: cardIndex, grade: grade)
                                    reviewQueue.removeAll { $0 == cardIndex }
                                    if grade == 0 { reviewQueue.append(cardIndex) }
                                    if let next = reviewQueue.first { cardIndex = next }
                                    else { reviewFinished = true }
                                    revealed = false
                                }.buttonStyle(.bordered)
                            }
                        }
                    }
                    if let review = progress.cards[entry.id + "/" + String(cardIndex)] {
                        Text("Next review: " + review.due.formatted()).font(.caption)
                    }
                    Text("\(reviewQueue.count) cards left in this session").font(.caption)
                    }
                }
                if let questions = entry.content.questions {
                    ForEach(questions.indices, id: \.self) { index in
                        let question = questions[index]
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(index + 1). " + question.question).font(.headline)
                            ForEach(question.options.indices, id: \.self) { option in
                                Button {
                                    answers[index] = option
                                    if answers.count == questions.filter({ $0.options.indices.contains($0.correctIndex) }).count && !recordedQuiz {
                                        progress.recordQuiz(title: entry.title, correct: answers.filter { questions[$0.key].correctIndex == $0.value }.count, total: questions.filter { $0.options.indices.contains($0.correctIndex) }.count)
                                        recordedQuiz = true
                                    }
                                    progress.saveAttempt(entry: entry.id, answers: answers, completed: recordedQuiz)
                                } label: {
                                    HStack {
                                        Image(systemName: answers[index] == option ? "checkmark.circle.fill" : "circle")
                                        Text(.init(question.options[option])).multilineTextAlignment(.leading)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                        .background(answerColor(index, option, question.correctIndex), in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).disabled(answers[index] != nil || !question.options.indices.contains(question.correctIndex))
                            }
                            if !question.options.indices.contains(question.correctIndex) {
                                Text("No answer key saved · excluded from scoring").font(.caption).foregroundStyle(CortexStyle.muted)
                                if !question.explanation.isEmpty { Text(.init(question.explanation)) }
                            }
                            if let selected = answers[index] {
                                Text(selected == question.correctIndex ? "Correct" : "Incorrect").font(.headline)
                                if question.options.indices.contains(question.correctIndex) { Text("Answer: " + question.options[question.correctIndex]) }
                                Text(.init(question.explanation))
                            }
                        }.padding().background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if !questions.isEmpty {
                        Text("Score: \(answers.filter { questions[$0.key].correctIndex == $0.value }.count) / \(questions.filter { $0.options.indices.contains($0.correctIndex) }.count)")
                        Button("Try again") { answers = [:]; recordedQuiz = false; progress.saveAttempt(entry: entry.id, answers: [:], completed: false) }
                    }
                }
                if let sections = entry.content.sections {
                    ForEach(sections.indices, id: \.self) { index in
                        SnapshotSectionView(section: sections[index])
                    }
                }
            }.font(.system(size: fontSize)).lineSpacing(lineSpacing).padding(18)
        }.background(CortexStyle.background).foregroundStyle(CortexStyle.ink)
            .onAppear {
                progress.opened(entry)
                if !reviewReady, entry.content.cards != nil {
                    reviewQueue = progress.dueQueue(entry)
                    cardIndex = reviewQueue.first ?? 0
                    reviewFinished = reviewQueue.isEmpty
                    reviewReady = true
                }
                if let attempt = progress.attempts[entry.id], let questions = entry.content.questions {
                    answers = attempt.answers.filter { questions.indices.contains($0.key) && questions[$0.key].options.indices.contains($0.value) }
                    recordedQuiz = attempt.completed
                }
            }
            .navigationTitle(entry.kind).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                Button { showingFonts = true } label: { Label("Font settings", systemImage: "textformat.size") }
            }
            .sheet(isPresented: $showingFonts) {
                NavigationStack {
                    Form {
                        Stepper("Font size: \(fontSize, specifier: "%.0f")", value: $fontSize, in: 12...28)
                        Stepper("Line spacing: \(lineSpacing, specifier: "%.0f")", value: $lineSpacing, in: 0...16)
                        Button("Reset to default") { fontSize = 16; lineSpacing = 6 }
                    }.navigationTitle("Font settings").toolbar { Button("Done") { showingFonts = false } }
                }.presentationDetents([.medium])
            }
    }
    private func answerColor(_ question: Int, _ option: Int, _ correct: Int) -> Color {
        guard let selected = answers[question] else { return Color.gray.opacity(0.07) }
        if option == correct { return Color.green.opacity(0.18) }
        return selected == option ? Color.red.opacity(0.15) : Color.gray.opacity(0.07)
    }
}

private struct SnapshotPointsView: View {
    let points: [SnapshotPoint]
    let numbered: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(points.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    Text(.init("• " + points[index].text))
                    ForEach(Array((points[index].subpoints ?? []).enumerated()), id: \.offset) { _, text in
                        Text(.init("– " + text)).padding(.leading, 16)
                    }
                }
            }
            ForEach(numbered.indices, id: \.self) { index in Text(.init("\(index + 1). " + numbered[index])) }
        }
    }
}
private struct SnapshotSectionView: View {
    let section: SnapshotSection
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let heading = section.heading { Text(heading).font(CortexStyle.title(21)) }
            SnapshotPointsView(points: section.points ?? [], numbered: section.numbered ?? [])
            if let groups = section.groups {
                ForEach(groups.indices, id: \.self) { index in
                    if let heading = groups[index].heading { Text(heading).font(CortexStyle.title(18)) }
                    SnapshotPointsView(points: groups[index].points ?? [], numbered: groups[index].numbered ?? [])
                }
            }
            if let tables = section.tables {
                ForEach(tables.indices, id: \.self) { index in
                    if let title = tables[index].title { Text(title).font(.headline) }
                    ScrollView(.horizontal) {
                        Grid(alignment: .topLeading, horizontalSpacing: 1, verticalSpacing: 1) {
                            GridRow {
                                ForEach(Array((tables[index].headers ?? []).enumerated()), id: \.offset) { _, cell in
                                    Text(.init(cell)).bold().frame(width: 180, alignment: .leading).padding(8).background(Color.blue.opacity(0.1))
                                }
                            }
                            ForEach(Array((tables[index].rows ?? []).enumerated()), id: \.offset) { _, row in
                                GridRow {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                        Text(.init(cell)).frame(width: 180, alignment: .leading).padding(8).background(Color.gray.opacity(0.06))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ReviewSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("study.retention") private var retention = 0.92
    @AppStorage("study.maxInterval") private var maximum = 365.0
    @AppStorage("study.newCards") private var newCards = 30
    var body: some View {
        NavigationStack {
            Form {
                Stepper("New cards per session: \(newCards)", value: $newCards, in: 1...500)
                Stepper("Desired retention: \(retention * 100, specifier: "%.0f")%", value: $retention, in: 0.8...0.99, step: 0.01)
                Stepper("Maximum interval: \(maximum, specifier: "%.0f") days", value: $maximum, in: 1...3650)
                Text("Again returns the card to the session and schedules a 10-minute relearning interval. Other ratings follow the Consumer app’s interval progression.").font(.caption)
                Button("Reset defaults") { newCards = 30; retention = 0.92; maximum = 365 }
            }.navigationTitle("Review settings").toolbar { Button("Done") { dismiss() } }
        }
    }
}
