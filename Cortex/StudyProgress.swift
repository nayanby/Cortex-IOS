import Foundation
import SwiftUI

struct CardReview: Codable {
    let due: Date
    let interval: Double
    let reviews: Int
}
struct QuizAttempt: Codable { let answers: [Int: Int]; let completed: Bool }
struct QuizResult: Codable, Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let correct: Int
    let total: Int
}
@MainActor
final class StudyProgress: ObservableObject {
    static let shared = StudyProgress()
    @Published private(set) var cards: [String: CardReview] = [:]
    @Published private(set) var quizzes: [QuizResult] = []
    @Published private(set) var recentStudy: [String] = []
    @Published private(set) var attempts: [String: QuizAttempt] = [:]
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "study.attempts"), let saved = try? JSONDecoder().decode([String: QuizAttempt].self, from: data) { attempts = saved }
        recentStudy = defaults.stringArray(forKey: "study.recent") ?? []
        if let data = defaults.data(forKey: "study.cardReviews"), let saved = try? JSONDecoder().decode([String: CardReview].self, from: data) { cards = saved }
        if let data = defaults.data(forKey: "study.quizResults"), let saved = try? JSONDecoder().decode([QuizResult].self, from: data) { quizzes = saved }
    }
    func opened(_ entry: StudyEntry) {
        recentStudy.removeAll { $0 == entry.id }
        recentStudy.insert(entry.id, at: 0)
        recentStudy = Array(recentStudy.prefix(20))
        defaults.set(recentStudy, forKey: "study.recent")
    }
    func review(entry: String, index: Int, grade: Int) {
        let key = entry + "/" + String(index)
        let previous = cards[key]
        let days = Self.nextInterval(current: previous?.interval ?? 0, grade: grade,
            retention: defaults.object(forKey: "study.retention") as? Double ?? 0.92,
            maximum: defaults.object(forKey: "study.maxInterval") as? Double ?? 365)
        let seconds = grade == 0 ? 600 : days * 86_400
        cards[key] = CardReview(due: Date().addingTimeInterval(seconds), interval: days, reviews: (previous?.reviews ?? 0) + 1)
        if let data = try? JSONEncoder().encode(cards) { defaults.set(data, forKey: "study.cardReviews") }
    }
    // Port of aiFlashcardNextIntervalDays from the Android Consumer reader.
    nonisolated static func nextInterval(current: Double, grade: Int, retention: Double = 0.92, maximum: Double = 365) -> Double {
        if grade == 0 { return 0 }
        if current < 1 { return grade == 1 ? 1 : grade == 2 ? 2 : 4 }
        let factor = max(0.70, min(1.10, 0.92 / min(0.99, max(0.80, retention))))
        let multiplier = grade == 1 ? 1.35 : grade == 2 ? 2.25 : 3.2
        var next = max(1, (current * multiplier * factor).rounded())
        if grade == 2 {
            let minimum: Double = current <= 2 ? 4 : current <= 8 ? 10 : current <= 20 ? 30 : current <= 45 ? 60 : current <= 100 ? 180 : 365
            next = max(next, minimum)
        }
        return min(max(1, maximum), next)
    }
    nonisolated static func cardKey(_ entry:StudyEntry,index:Int) -> String {
        guard let deck = entry.content.cards, deck.indices.contains(index) else { return entry.id + "/" + String(index) }
        let card = deck[index]
        return (card.sourceEntryID ?? entry.id) + "/" + String(card.sourceIndex ?? index)
    }
    func dueQueue(_ entry: StudyEntry) -> [Int] {
        guard let deck = entry.content.cards else { return [] }
        let reviewed = deck.indices.filter { index in
            guard let review = cards[Self.cardKey(entry,index:index)] else { return false }
            return review.due <= Date()
        }.sorted { cards[Self.cardKey(entry,index:$0)]!.due < cards[Self.cardKey(entry,index:$1)]!.due }
        let newLimit = defaults.object(forKey: "study.newCards") as? Int ?? 30
        let new = deck.indices.filter { cards[Self.cardKey(entry,index:$0)] == nil }.prefix(max(0, newLimit))
        return Array(reviewed.prefix(9999)) + new
    }
    func saveAttempt(entry: String, answers: [Int: Int], completed: Bool) {
        attempts[entry] = QuizAttempt(answers: answers, completed: completed)
        if let data = try? JSONEncoder().encode(attempts) { defaults.set(data, forKey: "study.attempts") }
    }
    func recordQuiz(title: String, correct: Int, total: Int) {
        quizzes.insert(QuizResult(id: UUID(), title: title, date: Date(), correct: correct, total: total), at: 0)
        quizzes = Array(quizzes.prefix(1000))
        if let data = try? JSONEncoder().encode(quizzes) { defaults.set(data, forKey: "study.quizResults") }
    }
}

struct PerformanceView: View {
    @ObservedObject private var progress = StudyProgress.shared
    var body: some View {
        List {
            Section("Flashcards") {
                LabeledContent("Cards reviewed", value: String(progress.cards.count))
                LabeledContent("Reviews", value: String(progress.cards.values.reduce(0) { $0 + $1.reviews }))
                LabeledContent("Reviewed cards due", value: String(progress.cards.values.filter { $0.due <= Date() }.count))
            }
            Section("Qbank") {
                LabeledContent("Completed quizzes", value: String(progress.quizzes.count))
                let total = progress.quizzes.reduce(0) { $0 + $1.total }
                let correct = progress.quizzes.reduce(0) { $0 + $1.correct }
                LabeledContent("Correct answers", value: "\(correct) / \(total)")
                ForEach(progress.quizzes) { result in
                    VStack(alignment: .leading) {
                        Text(result.title).font(CortexStyle.title(16))
                        Text("\(result.correct) / \(result.total) · " + result.date.formatted()).font(.caption)
                    }
                }
            }
        }.navigationTitle("Performance").toolbar(.visible, for: .navigationBar)
    }
}

struct ReadingRecord: Codable, Identifiable {
    var id: String { path }
    let path: String
    let title: String
}
@MainActor
final class ReadingHistory: ObservableObject {
    static let shared = ReadingHistory()
    @Published private(set) var recent: [ReadingRecord] = []
    init() {
        if let data = UserDefaults.standard.data(forKey: "reading.recent"), let records = try? JSONDecoder().decode([ReadingRecord].self, from: data) { recent = records }
    }
    func opened(_ note: LibraryNote) {
        recent.removeAll { $0.path == note.path }
        recent.insert(ReadingRecord(path: note.path, title: note.displayName), at: 0)
        recent = Array(recent.prefix(10))
        if let data = try? JSONEncoder().encode(recent) { UserDefaults.standard.set(data, forKey: "reading.recent") }
    }
}
