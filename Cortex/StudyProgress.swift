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
        let days: Double
        switch grade {
        case 0: days = 10.0 / 1440
        case 1: days = max(1, (previous?.interval ?? 1) * 1.2)
        case 2: days = max(1, (previous?.interval ?? 0) * 2.5)
        default: days = max(4, (previous?.interval ?? 1) * 3)
        }
        cards[key] = CardReview(due: Date().addingTimeInterval(days * 86_400), interval: days, reviews: (previous?.reviews ?? 0) + 1)
        if let data = try? JSONEncoder().encode(cards) { defaults.set(data, forKey: "study.cardReviews") }
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
