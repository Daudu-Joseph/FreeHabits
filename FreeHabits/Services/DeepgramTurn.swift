import Foundation

/// Interim text is display-only. Only an endpoint with finalized text may submit a turn.
struct DeepgramTurn {
    enum Failure: Error { case rejected }
    struct Update { let text: String; let complete: Bool }
    private var finalized = ""
    private var interim = ""

    mutating func consume(_ data: Data) throws -> Update? {
        let event = try JSONDecoder().decode(Event.self, from: data)
        if event.type == "Error" { throw Failure.rejected }
        if event.type == "Results", let text = event.channel?.alternatives.first?.transcript {
            if event.is_final == true {
                finalized = [finalized, text].filter { !$0.isEmpty }.joined(separator: " ")
                interim = ""
            } else { interim = text }
            return Update(text: [finalized, interim].filter { !$0.isEmpty }.joined(separator: " "),
                          complete: event.speech_final == true && event.is_final == true && !finalized.isEmpty)
        }
        if event.type == "UtteranceEnd", !finalized.isEmpty, interim.isEmpty {
            return Update(text: finalized, complete: true)
        }
        return nil
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
