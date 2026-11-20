import Foundation

/// Interim text is display-only. Only an endpoint with finalized text may submit a turn.
struct DeepgramTurn {
    enum Failure: Error { case rejected }
    struct Update { let text: String; let complete: Bool }
    private var finalized = ""
    private var interim = ""
    var hasFinalizedTurn: Bool { !finalized.isEmpty && interim.isEmpty }

    mutating func consume(_ data: Data) throws -> Update? {
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        if header.type == "Error" { throw Failure.rejected }
        if header.type == "UtteranceEnd" {
            guard header.last_word_end != -1, !finalized.isEmpty, interim.isEmpty else { return nil }
            return Update(text: finalized, complete: true)
        }
        guard header.type == "Results" else { return nil }
        let event = try decoder.decode(Event.self, from: data)
        if event.type == "Results", let text = event.channel?.alternatives.first?.transcript {
            if event.is_final == true {
                finalized = [finalized, text].filter { !$0.isEmpty }.joined(separator: " ")
                interim = ""
            } else { interim = text }
            return Update(text: [finalized, interim].filter { !$0.isEmpty }.joined(separator: " "),
                          complete: event.speech_final == true && event.is_final == true && !finalized.isEmpty)
        }
        return nil
    }

    private struct Header: Decodable {
        let type: String
        let last_word_end: Double?
    }

    private struct Event: Decodable {
        struct Channel: Decodable {
            struct Alternative: Decodable { let transcript: String }
            let alternatives: [Alternative]
        }
        let type: String
        let is_final: Bool?
        let speech_final: Bool?
        let channel: Channel?
    }
}
