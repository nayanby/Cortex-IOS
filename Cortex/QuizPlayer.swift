import SwiftUI

struct QuizPlayer: View {
    let entry: StudyEntry
    @ObservedObject private var progress = StudyProgress.shared
    @State private var index = 0
    @State private var selected: Int?
    @State private var answers: [Int:Int] = [:]
    @State private var finished = false
    @State private var recorded = false
    @State private var initialized = false
    private var questions: [StudyQuestion] { entry.content.questions ?? [] }
    private var score: Int { answers.filter { questions.indices.contains($0.key) && questions[$0.key].correctIndex == $0.value }.count }
    private var scoredCount: Int { questions.filter { $0.options.indices.contains($0.correctIndex) }.count }
    var body: some View {
        Group {
            if questions.isEmpty { ContentUnavailableView("No questions",systemImage:"questionmark.circle") }
            else if finished {
                VStack(spacing:20) {
                    Text("Quiz complete").font(CortexStyle.title(28))
                    Text("\(score) / \(scoredCount)").font(.system(size:36,weight:.bold))
                    if scoredCount < questions.count { Text("Questions without an answer key were excluded from scoring.").font(.caption) }
                    Button("Try again") { index = 0; selected = nil; answers = [:]; finished = false; recorded = false; save() }.buttonStyle(ConsumerButtonStyle())
                }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                questionScreen
            }
        }.background(CortexStyle.background).foregroundStyle(CortexStyle.ink)
            .cortexPage("Qbank")
            .onAppear {
                guard !initialized else { return }; initialized = true;progress.opened(entry)
                if let attempt = progress.attempts[entry.id] {
                    answers = attempt.answers.filter { questions.indices.contains($0.key) && questions[$0.key].options.indices.contains($0.value) }
                    finished = attempt.completed; recorded = attempt.completed
                    index = min(max(0,attempt.currentIndex ?? questions.indices.first(where:{answers[$0] == nil}) ?? 0),max(0,questions.count-1))
                    selected = answers[index]
                }
            }
    }
    private var questionScreen: some View {
        let question = questions[index]
        let valid = question.options.indices.contains(question.correctIndex)
        return VStack(spacing:0) {
            HStack { Text("Question \(index+1) of \(questions.count)").font(.caption); Spacer(); Text("\(answers.count) answered").font(.caption) }.padding(14)
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text(question.question).font(CortexStyle.title(19)).textSelection(.enabled)
                    ForEach(question.options.indices,id:\.self) { option in
                        Button { selected = option } label: {
                            HStack(alignment:.top,spacing:10) {
                                Text(String(UnicodeScalar(65+option)!) + ".").font(.system(size:15,weight:.semibold))
                                Text(.init(question.options[option])).font(.system(size:15)).multilineTextAlignment(.leading)
                                Spacer(minLength:0)
                            }.padding(14).frame(maxWidth:.infinity,minHeight:54,alignment:.leading)
                                .background(optionColor(option,question:question),in:RoundedRectangle(cornerRadius:12))
                                .overlay(RoundedRectangle(cornerRadius:12).stroke(CortexStyle.line,lineWidth:1))
                        }.buttonStyle(.plain).disabled(answers[index] != nil || !valid)
                    }
                    if !valid { Text("No answer key saved · not scored").font(.caption).foregroundStyle(CortexStyle.muted) }
                    if answers[index] != nil || !valid {
                        if let answer = answers[index] {
                            Text(answer == question.correctIndex ? "Correct" : "Incorrect").font(.headline)
                            if valid { Text("Answer: " + question.options[question.correctIndex]).font(.headline) }
                        }
                        Text(.init(question.explanation)).font(.system(size:14)).foregroundStyle(CortexStyle.muted).textSelection(.enabled)
                    }
                }.padding(18)
            }
            HStack(spacing:12) {
                Button("Previous") { move(-1) }.disabled(index == 0)
                Spacer()
                if answers[index] == nil && valid {
                    Button("Check answer") { if let selected { answers[index] = selected; save() } }.buttonStyle(ConsumerButtonStyle()).disabled(selected == nil)
                } else {
                    Button(index+1 == questions.count ? "Finish" : "Next") {
                        if index+1 < questions.count { move(1) }
                        else {
                            finished = true
                            if !recorded && scoredCount > 0 { progress.recordQuiz(title:entry.title,correct:score,total:scoredCount); recorded = true }
                            save()
                        }
                    }.buttonStyle(ConsumerButtonStyle())
                }
            }.padding(14).background(.white)
        }
    }
    private func optionColor(_ option:Int,question:StudyQuestion) -> Color {
        if let answer = answers[index] {
            if option == question.correctIndex { return Color(hex:0xA9D3B3).opacity(0.3) }
            if option == answer { return Color(hex:0xE9A8A3).opacity(0.25) }
        }
        return selected == option ? Color(hex:0xDFEAFB) : .white
    }
    private func move(_ offset:Int) { index = min(max(0,index+offset),max(0,questions.count-1)); selected = answers[index]; save() }
    private func save() { progress.saveAttempt(entry:entry.id,answers:answers,completed:finished,currentIndex:index) }
}
