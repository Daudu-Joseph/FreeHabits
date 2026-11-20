import Foundation
import AVFoundation

/// One WebSocket per utterance. No audio is retained on disk or logged.
@MainActor
final class DeepgramTranscriber {
    private var socket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .ephemeral)
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var endpointFallback: Task<Void, Never>?
    private var continuation: AsyncStream<Data>.Continuation?
    private var generation = UUID()
    private var turn = DeepgramTurn()

    func start(key: String, sampleRate: Double,
               update: @escaping @MainActor (String) -> Void,
               finish: @escaping @MainActor (String?) -> Void) -> AsyncStream<Data>.Continuation {
        stop()
        let generation = UUID()
        self.generation = generation
        turn = DeepgramTurn()
        var url = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        url.queryItems = [
            .init(name: "model", value: "nova-3"),
            .init(name: "language", value: "en"),
            .init(name: "encoding", value: "linear16"),
            .init(name: "sample_rate", value: String(Int(sampleRate))),
            .init(name: "channels", value: "1"),
            .init(name: "interim_results", value: "true"),
            .init(name: "smart_format", value: "true"),
            .init(name: "endpointing", value: "800"),
            .init(name: "utterance_end_ms", value: "1000")
        ]
        var request = URLRequest(url: url.url!)
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request)
        self.socket = socket
        let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(24))
        self.continuation = continuation
        socket.resume()
        sender = Task { [weak self] in
            do {
                for await data in stream {
                    try Task.checkCancellation()
                    try await socket.send(.data(data))
                }
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.stop()
                finish("Deepgram audio upload failed. Check your connection and key in Voice settings.")
            }
        }
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let self, self.generation == generation else { return }
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let value): data = value
                    @unknown default: continue
                    }
                    if let result = try self.turn.consume(data) {
                        self.endpointFallback?.cancel()
                        update(result.text)
                        if result.complete {
                            self.stop()
                            finish(nil)
                            return
                        }
                        if self.turn.hasFinalizedTurn {
                            self.endpointFallback = Task { [weak self] in
                                try? await Task.sleep(for: .milliseconds(1600))
                                guard !Task.isCancelled, let self, self.generation == generation,
                                      self.turn.hasFinalizedTurn else { return }
                                self.stop()
                                finish(nil)
                            }
                        }
                    }
                }
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.stop()
                finish("Deepgram couldn't connect. Check your key and internet connection in Voice settings.")
            }
        }
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            self.stop()
            finish("No completed turn received in 45 seconds. Tap the orb to try again.")
        }
        return continuation
    }

    func stop() {
        endpointFallback?.cancel(); endpointFallback = nil
        generation = UUID()
        continuation?.finish(); continuation = nil
        sender?.cancel(); sender = nil
        receiver?.cancel(); receiver = nil
        deadline?.cancel(); deadline = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
    }

    /// Convert native Float32 microphone input to little-endian mono PCM16.
    nonisolated static func pcm(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channels = buffer.floatChannelData else { return nil }
        let frames = Int(buffer.frameLength), count = Int(buffer.format.channelCount)
        guard count > 0 else { return nil }
        var samples = [Int16](repeating: 0, count: frames)
        for frame in 0..<frames {
            var value: Float = 0
            for channel in 0..<count { value += channels[channel][frame] }
            value /= Float(count)
            samples[frame] = value.isFinite ? Int16(max(-1, min(1, value)) * 32767).littleEndian : 0
        }
        return samples.withUnsafeBytes { Data($0) }
    }

}
