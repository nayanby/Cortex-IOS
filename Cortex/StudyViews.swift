import SwiftUI

struct StudyBrowser: View {
    let kind: String
    var note: LibraryNote? = nil
    @ObservedObject private var library = StudyLibrary.shared
    @State private var query = ""
    var body: some View {
        List {
            if let error = library.loadError { Text(error).foregroundStyle(.red) }
            let entries = library.matching(kind: kind, note: note).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.document.localizedCaseInsensitiveContains(query) }
            if entries.isEmpty {
                ContentUnavailableView("No saved \(kind.lowercased())", systemImage: "books.vertical", description: Text("No matching saved content is included in this local catalog."))
            }
            ForEach(entries) { entry in
                NavigationLink { StudyDetail(entry: entry) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.title).font(CortexStyle.title(17))
                        Text(entry.folder + " · " + entry.document).font(.caption).foregroundStyle(CortexStyle.muted)
                    }
                }
            }
        }.searchable(text: $query).navigationTitle(kind).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}

struct StudyDetail: View {
    let entry: StudyEntry
    @State private var cardIndex = 0
    @State private var revealed = false
    @State private var answers: [Int: Int] = [:]
    @ObservedObject private var progress = StudyProgress.shared
    @State private var recordedQuiz = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(entry.content.title ?? entry.title).font(CortexStyle.title(24))
                if let cards = entry.content.cards, !cards.isEmpty {
                    Text("Card \(cardIndex + 1) of \(cards.count)").font(.caption)
                    Text(.init(cards[cardIndex].front)).font(.title3).frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                    Button(revealed ? "Hide answer" : "Show answer") { revealed.toggle() }.buttonStyle(.borderedProminent)
                    if revealed {
                        Text(.init(cards[cardIndex].back)).padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        HStack {
                            ForEach(Array(["Again", "Hard", "Good", "Easy"].enumerated()), id: \.offset) { grade, title in
                                Button(title) {
                                    progress.review(entry: entry.id, index: cardIndex, grade: grade)
                                    if cardIndex + 1 < cards.count { cardIndex += 1 }
                                    revealed = false
                                }.buttonStyle(.bordered)
                            }
                        }
                    }
                    if let review = progress.cards[entry.id + "/" + String(cardIndex)] {
                        Text("Next review: " + review.due.formatted()).font(.caption)
                    }
                    HStack {
                        Button("Previous") { cardIndex -= 1; revealed = false }.disabled(cardIndex == 0)
                        Spacer()
                        Button("Next") { cardIndex += 1; revealed = false }.disabled(cardIndex + 1 >= cards.count)
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
                                    if answers.count == questions.count && !recordedQuiz {
                                        progress.recordQuiz(title: entry.title, correct: answers.filter { questions[$0.key].correctIndex == $0.value }.count, total: questions.count)
                                        recordedQuiz = true
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: answers[index] == option ? "checkmark.circle.fill" : "circle")
                                        Text(.init(question.options[option])).multilineTextAlignment(.leading)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                        .background(answerColor(index, option, question.correctIndex), in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).disabled(answers[index] != nil)
                            }
                            if let selected = answers[index] {
                                Text(selected == question.correctIndex ? "Correct" : "Incorrect").font(.headline)
                                if question.options.indices.contains(question.correctIndex) { Text("Answer: " + question.options[question.correctIndex]) }
                                Text(.init(question.explanation))
                            }
                        }.padding().background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if !questions.isEmpty {
                        Text("Score: \(answers.filter { questions[$0.key].correctIndex == $0.value }.count) / \(questions.count)")
                        Button("Try again") { answers = [:]; recordedQuiz = false }
                    }
                }
                if let sections = entry.content.sections {
                    ForEach(sections.indices, id: \.self) { index in
                        SnapshotSectionView(section: sections[index])
                    }
                }
            }.padding(18)
        }.background(CortexStyle.background).foregroundStyle(CortexStyle.ink)
            .onAppear { progress.opened(entry) }
            .navigationTitle(entry.kind).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
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
