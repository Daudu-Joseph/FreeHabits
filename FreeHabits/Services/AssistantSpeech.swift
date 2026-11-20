import SwiftUI
import Combine
import Speech
import AVFoundation

@MainActor
final class AssistantSpeech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var transcript = ""
    @Published var listening = false
    @Published var requesting = false
    @Published var speaking = false
    @Published var error: String?
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var hasTap = false
    private var limitTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func start() async {
        guard !requesting else { return }
        requesting = true
        defer { requesting = false }
        stop()
        synthesizer.stopSpeaking(at: .immediate)
        speaking = false
        error = nil
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard !Task.isCancelled else { return }
        guard permission == .authorized else {
            error = "Allow speech recognition in iPhone Settings to use the voice orb."
            return
        }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard !Task.isCancelled else { return }
        guard microphone else { error = "Allow microphone access in iPhone Settings."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            error = "Speech recognition is unavailable for this language right now."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request
            transcript = ""
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                let failed = failure != nil
                Task { @MainActor [weak self] in
                    guard let self, self.listening else { return }
                    if let text { self.transcript = text }
                    if final || failed {
                        self.stop()
                        if failed && self.transcript.isEmpty { self.error = "I couldn't hear that. Tap the orb to try again." }
                    }
                }
            }
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw AssistantError.message("No microphone input is available.")
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            hasTap = true
            engine.prepare()
            try engine.start()
            listening = true
            limitTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(55))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            stop()
            self.error = "Couldn't start the microphone. Please try again."
        }
    }

    func stop() {
        listening = false
        limitTask?.cancel()
        limitTask = nil
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        request = nil
        if !speaking { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    func say(_ text: String) {
        stop()
        synthesizer.stopSpeaking(at: .immediate)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            speaking = true
            synthesizer.speak(utterance)
        } catch { self.error = "The reply is ready, but spoken playback couldn't start." }
    }

    func silence() {
        synthesizer.stopSpeaking(at: .immediate)
        speaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.releasePlayback() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.releasePlayback() }
    }
    private func releasePlayback() {
        guard !synthesizer.isSpeaking else { return }
        speaking = false
        if !listening { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}
