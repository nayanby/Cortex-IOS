import SwiftUI
import AVFoundation

@MainActor
final class AudiobookController: NSObject, ObservableObject, @preconcurrency AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var paused = false
    @Published private(set) var index = 0
    @Published private(set) var paragraphs: [String] = []
    @Published var speed: Double = 1
    @Published var error: String?
    private let synthesizer = AVSpeechSynthesizer()
    private let progressKey: String
    private var shouldContinue = false
    private var interruption: NSObjectProtocol?
    private var routeChange: NSObjectProtocol?
    init(documentID: UUID) {
        progressKey = "audio." + documentID.uuidString
        super.init()
        synthesizer.delegate = self
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        }
        routeChange = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.pause() }
            }
        }
    }
    deinit {
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        if let routeChange { NotificationCenter.default.removeObserver(routeChange) }
    }
    func prepare(_ text: String) {
        guard paragraphs.isEmpty else { return }
        paragraphs = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        index = min(max(0, UserDefaults.standard.integer(forKey: progressKey)), max(0, paragraphs.count - 1))
    }
    func play() {
        if paused && synthesizer.isPaused { synthesizer.continueSpeaking(); paused = false; isSpeaking = true; shouldContinue = true; return }
        guard !isSpeaking, paragraphs.indices.contains(index) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            shouldContinue = true; paused = false; isSpeaking = true
            speakCurrent()
        } catch { self.error = "Audio playback could not start. " + error.localizedDescription }
    }
    func pause() {
        shouldContinue = false
        if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .word) }
        paused = true; isSpeaking = false
    }
    func stop() {
        shouldContinue = false; synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false; paused = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
    func move(_ offset: Int) {
        let playing = isSpeaking
        stop(); index = min(max(0, index + offset), max(0, paragraphs.count - 1))
        UserDefaults.standard.set(index, forKey: progressKey)
        if playing { play() }
    }
    private func speakCurrent() {
        guard paragraphs.indices.contains(index) else { stop(); return }
        let utterance = AVSpeechUtterance(string: paragraphs[index])
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = Float(AVSpeechUtteranceDefaultSpeechRate * Float(speed))
        synthesizer.speak(utterance)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard shouldContinue else { return }
        if index + 1 < paragraphs.count {
            index += 1; UserDefaults.standard.set(index, forKey: progressKey); speakCurrent()
        } else { index = 0; UserDefaults.standard.set(0, forKey: progressKey); stop() }
    }
}

struct AudiobookView: View {
    @ObservedObject var controller: AudiobookController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Read aloud").font(CortexStyle.title(24))
                Text("Uses the iPad’s built-in voice. No AI key is required.").font(.caption)
                if controller.paragraphs.indices.contains(controller.index) {
                    ScrollView { Text(controller.paragraphs[controller.index]).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 240)
                    Text("Paragraph \(controller.index + 1) of \(controller.paragraphs.count)").font(.caption)
                }
                HStack(spacing: 24) {
                    Button { controller.move(-1) } label: { Label("Previous", systemImage: "backward.end.fill") }
                    Button { if controller.isSpeaking { controller.pause() } else { controller.play() } } label: { Label(controller.isSpeaking ? "Pause" : "Play", systemImage: controller.isSpeaking ? "pause.fill" : "play.fill") }
                    Button { controller.move(1) } label: { Label("Next", systemImage: "forward.end.fill") }
                }.labelStyle(.iconOnly).font(.title)
                Slider(value: $controller.speed, in: 0.6...1.6, step: 0.1)
                Text("Speed: \(controller.speed, specifier: "%.1f")× · applies to the next paragraph").font(.caption)
                Button("Stop") { controller.stop() }
                if let error = controller.error { Text(error).foregroundStyle(.red) }
            }.padding(24).navigationTitle("Audio").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }
    }
}
