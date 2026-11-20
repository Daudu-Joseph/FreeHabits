import Foundation
import AVFoundation

/// Plays PCM chunks as they arrive; never waits for or stores a complete audio file.
@MainActor
final class DeepgramSpeaker {
    static let defaultVoice = "aura-2-thalia-en"
    static let voices = [
        "aura-2-thalia-en", "aura-2-andromeda-en", "aura-2-helena-en",
        "aura-2-apollo-en", "aura-2-arcas-en", "aura-2-aries-en",
        "aura-2-draco-en", "aura-2-pandora-en", "aura-2-luna-en", "aura-2-zeus-en"
    ]
    static func label(_ voice: String) -> String {
        let name = voice.replacingOccurrences(of: "aura-2-", with: "").replacingOccurrences(of: "-en", with: "").capitalized
        return name + (["aura-2-draco-en", "aura-2-pandora-en"].contains(voice) ? " · British" : " · American")
    }

    private let session = URLSession(configuration: .ephemeral)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var completion: CheckedContinuation<Void, Error>?
    private var generation = UUID()
    private var pendingBuffers = 0
    private var flushed = false
    private var receivedAudio = false
    private var remainder = Data()
    private var firstAudio: (@MainActor () -> Void)?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func say(_ text: String, voice: String, firstAudio: @escaping @MainActor () -> Void = {}) async throws {
        stop()
        try Task.checkCancellation()
        guard UserDefaults.standard.bool(forKey: "assistantDeepgramEnabled"),
              let key = AssistantKeychain.read(service: "Deepgram") else {
            throw AssistantError.message("Add your Deepgram key in Voice settings to hear replies.")
        }
        guard Self.voices.contains(voice) else { throw AssistantError.message("Choose a Deepgram voice in Voice settings.") }
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try audioSession.setActive(true)
        try engine.start()
        self.firstAudio = firstAudio
        var url = URLComponents(string: "wss://api.deepgram.com/v1/speak")!
        url.queryItems = [.init(name: "model", value: voice), .init(name: "encoding", value: "linear16"),
                          .init(name: "sample_rate", value: "24000")]
        var request = URLRequest(url: url.url!)
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request)
        self.socket = socket
        let generation = UUID()
        self.generation = generation
        socket.resume()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.completion = continuation
                receiver = Task { [weak self] in
                    do {
                        let payload = try JSONSerialization.data(withJSONObject: ["type": "Speak", "text": text])
                        try await socket.send(.string(String(decoding: payload, as: UTF8.self)))
                        try await socket.send(.string("{\"type\":\"Flush\"}"))
                        while !Task.isCancelled {
                            let message = try await socket.receive()
                            guard let self, self.generation == generation else { return }
                            switch message {
                            case .data(let data): try self.enqueue(data, generation: generation)
                            case .string(let value):
                                let event = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]
                                if event?["type"] as? String == "Error" {
                                    throw AssistantError.message("Deepgram couldn't generate speech. Check the key, quota and voice access.")
                                }
                                if event?["type"] as? String == "Flushed" {
                                    guard self.remainder.isEmpty, self.receivedAudio else {
                                        throw AssistantError.message("Deepgram returned no usable speech audio.")
                                    }
                                    self.flushed = true
                                    self.finishIfDrained()
                                    return
                                }
                            @unknown default: continue
                            }
                        }
                    } catch {
                        guard let self, self.generation == generation, !Task.isCancelled else { return }
                        let message = (error as? AssistantError)?.localizedDescription ??
                            "Deepgram speech couldn't connect. Check the key and your connection in Voice settings."
                        self.finish(.failure(AssistantError.message(message)))
                    }
                }
                deadline = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(90))
                    guard !Task.isCancelled, let self, self.generation == generation else { return }
                    self.finish(.failure(AssistantError.message("Speech playback timed out. Please try again.")))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.stop()
            }
        }
    }

    func stop() { finish(.failure(CancellationError())) }

    private func enqueue(_ data: Data, generation: UUID) throws {
        remainder.append(data)
        let length = remainder.count - remainder.count % 2
        guard length > 0 else { return }
        guard pendingBuffers < 512,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length / 2)),
              let samples = buffer.floatChannelData?[0] else {
            throw AssistantError.message("The speech audio buffer is full. Please try a shorter reply.")
        }
        buffer.frameLength = buffer.frameCapacity
        remainder.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for index in 0..<(length / 2) {
                let value = UInt16(bytes[index * 2]) | UInt16(bytes[index * 2 + 1]) << 8
                samples[index] = Float(Int16(bitPattern: value)) / 32768
            }
        }
        remainder.removeFirst(length)
        pendingBuffers += 1
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.pendingBuffers -= 1
                self.finishIfDrained()
            }
        }
        if !receivedAudio {
            receivedAudio = true
            firstAudio?(); firstAudio = nil
            player.play()
        }
    }

    private func finishIfDrained() {
        if flushed && pendingBuffers == 0 { finish(.success(())) }
    }

    private func finish(_ result: Result<Void, Error>) {
        generation = UUID()
        let continuation = completion
        completion = nil
        receiver?.cancel(); receiver = nil
        deadline?.cancel(); deadline = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        player.stop(); engine.stop()
        pendingBuffers = 0; flushed = false; receivedAudio = false
        remainder = Data(); firstAudio = nil
        continuation?.resume(with: result)
    }
}
