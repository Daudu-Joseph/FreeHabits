import SwiftUI
import Combine
import Speech
import AVFoundation

@MainActor
final class AssistantSpeech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static var microphoneInUse = false
    static var voicePlaybackInUse = false
    @Published var transcript = ""
    @Published var listening = false
    @Published var requesting = false
    @Published var speaking = false
    @Published var completedUtterance = UUID()
    var onCompletedUtterance: (@MainActor () -> Void)?
    @Published var speechStartDelay: Double?
    @Published var error: String?
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private let deepgram = DeepgramTranscriber()
    private let speaker = DeepgramSpeaker()
    private var playbackTask: Task<Void, Never>?
    private var playbackID = UUID()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var hasTap = false
    private var limitTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    private var captureID = UUID()
    private var lastVoiceAt = Date()
    private var lastTranscriptAt = Date()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func start() async {
        guard !requesting else { return }
        NotificationManager.shared.stopSpeaking()
        requesting = true
        defer { requesting = false }
        stop()
        silence()
        error = nil
        let attempt = UUID()
        captureID = attempt
        let useDeepgram = UserDefaults.standard.string(forKey: "assistantTranscriber") != "Apple"
        if !useDeepgram {
            let permission = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard !Task.isCancelled, captureID == attempt else { return }
            guard permission == .authorized else {
                error = "Allow speech recognition in iPhone Settings to use the voice orb."
                return
            }
        }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard !Task.isCancelled, captureID == attempt else { return }
        guard microphone else { error = "Allow microphone access in iPhone Settings."; return }
        if useDeepgram {
            startDeepgram()
            return
        }
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
            let captureID = UUID()
            self.captureID = captureID
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                let failed = failure != nil
                Task { @MainActor [weak self] in
                    guard let self, self.listening, self.captureID == captureID else { return }
                    if let text, text != self.transcript {
                        self.transcript = text
                        self.pauseTask?.cancel()
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.pauseTask = Task { [weak self] in
                                try? await Task.sleep(for: .milliseconds(1400))
                                guard !Task.isCancelled, let self, self.captureID == captureID else { return }
                                self.finishUtterance()
                            }
                        }
                    }
                    if final || failed {
                        if failed {
                            self.error = "Speech recognition stopped. Tap the orb to try again."
                            self.stop()
                        } else { self.finishUtterance() }
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
            Self.microphoneInUse = true
            limitTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(55))
                guard !Task.isCancelled else { return }
                self?.error = "Listening timed out. Tap the orb to continue."
                self?.stop()
            }
        } catch {
            stop()
            self.error = "Couldn't start the microphone. Please try again."
        }
    }

    func stop() {
        deepgram.stop()
        captureID = UUID()
        pauseTask?.cancel()
        pauseTask = nil
        listening = false
        Self.microphoneInUse = false
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
        NotificationManager.shared.stopSpeaking()
        error = nil
        stop()
        synthesizer.stopSpeaking(at: .immediate)
        playbackTask?.cancel()
        speaker.stop()
        let playbackID = UUID()
        self.playbackID = playbackID
        if UserDefaults.standard.string(forKey: "assistantVoiceEngine") != "Apple" {
            let started = Date()
            speechStartDelay = nil
            speaking = true
            Self.voicePlaybackInUse = true
            playbackTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.speaker.say(text, voice: UserDefaults.standard.string(forKey: "assistantDeepgramVoice") ?? DeepgramSpeaker.defaultVoice) { [weak self] in
                        self?.speechStartDelay = Date().timeIntervalSince(started)
                    }
                } catch is CancellationError { return }
                catch {
                    guard self.playbackID == playbackID else { return }
                    self.error = error.localizedDescription
                }
                guard self.playbackID == playbackID else { return }
                self.speaking = false
                Self.voicePlaybackInUse = false
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            speaking = true
            Self.voicePlaybackInUse = true
            synthesizer.speak(utterance)
        } catch { self.error = "The reply is ready, but spoken playback couldn't start." }
    }

    func silence() {
        playbackID = UUID()
        playbackTask?.cancel(); playbackTask = nil
        speaker.stop()
        synthesizer.stopSpeaking(at: .immediate)
        speaking = false
        Self.voicePlaybackInUse = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.releasePlayback() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.releasePlayback() }
    }
    private func releasePlayback() {
        guard UserDefaults.standard.string(forKey: "assistantVoiceEngine") == "Apple" else { return }
        guard !synthesizer.isSpeaking else { return }
        speaking = false
        Self.voicePlaybackInUse = false
        if !listening { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    private func startDeepgram() {
        guard UserDefaults.standard.bool(forKey: "assistantDeepgramEnabled"),
              let key = AssistantKeychain.read(service: "Deepgram") else {
            error = "Add your Deepgram key in Voice settings, or select iPhone transcription."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0, !format.isInterleaved else {
                throw AssistantError.message("No supported microphone input.")
            }
            transcript = ""
            let captureID = UUID()
            self.captureID = captureID
            let stream = deepgram.start(key: key, sampleRate: format.sampleRate, update: { [weak self] text in
                guard let self, self.captureID == captureID else { return }
                if text != self.transcript { self.lastTranscriptAt = Date() }
                self.transcript = text
            }, finish: { [weak self] message in
                guard let self, self.captureID == captureID else { return }
                if let message { self.error = message; self.stop() }
                else { self.finishUtterance() }
            })
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                    var energy: Float = 0
                    for index in 0..<Int(buffer.frameLength) { energy += samples[index] * samples[index] }
                    if sqrt(energy / Float(buffer.frameLength)) > 0.015 {
                        Task { @MainActor [weak self] in
                            guard let self, self.captureID == captureID else { return }
                            self.lastVoiceAt = Date()
                        }
                    }
                }
                guard let data = DeepgramTranscriber.pcm(buffer) else { return }
                if case .dropped = stream.yield(data) {
                    Task { @MainActor [weak self] in
                        guard let self, self.captureID == captureID else { return }
                        self.error = "The audio connection is too slow. Please try again."
                        self.stop()
                    }
                }
            }
            hasTap = true
            engine.prepare()
            try engine.start()
            listening = true
            Self.microphoneInUse = true
            lastVoiceAt = Date()
            lastTranscriptAt = Date()
            pauseTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled, let self, self.captureID == captureID, self.listening else { return }
                    if !self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       Date().timeIntervalSince(self.lastVoiceAt) >= 2,
                       Date().timeIntervalSince(self.lastTranscriptAt) >= 1.2 {
                        self.finishUtterance()
                        return
                    }
                }
            }
        } catch {
            stop()
            self.error = "Couldn't start the microphone. Please try again."
        }
    }

    private func finishUtterance() {
        stop()
        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completedUtterance = UUID()
            onCompletedUtterance?()
        }
    }
}
