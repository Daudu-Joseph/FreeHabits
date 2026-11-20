import Foundation

func result(_ text: String, final: Bool = false, endpoint: Bool = false) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["type": "Results", "is_final": final,
        "speech_final": endpoint, "channel": ["alternatives": [["transcript": text]]]])
}
func event(_ type: String) -> Data { Data("{\"type\":\"\(type)\"}".utf8) }

var turn = DeepgramTurn()
let partial = try turn.consume(result("I drank"))!
precondition(partial.text == "I drank" && !partial.complete)
let revised = try turn.consume(result("I drank two"))!
precondition(revised.text == "I drank two" && !revised.complete)
let firstFinal = try turn.consume(result("I drank", final: true))!
precondition(firstFinal.text == "I drank" && !firstFinal.complete)
let trailing = try turn.consume(result("two glasses"))!
precondition(trailing.text == "I drank two glasses" && !trailing.complete)
// A gap after earlier finalized words must not discard a newer interim amount.
let prematureGap = try turn.consume(event("UtteranceEnd"))
precondition(prematureGap == nil)
let endpoint = try turn.consume(result("two glasses", final: true, endpoint: true))!
precondition(endpoint.text == "I drank two glasses" && endpoint.complete)

var empty = DeepgramTurn()
let emptyGap = try empty.consume(event("UtteranceEnd"))
precondition(emptyGap == nil)
let emptyFinal = try empty.consume(result("", final: true, endpoint: true))!
precondition(!emptyFinal.complete)
let metadata = try empty.consume(event("Metadata"))
precondition(metadata == nil)

var gap = DeepgramTurn()
_ = try gap.consume(result("Gym is done", final: true))
// Real UtteranceEnd uses an array for channel; Results uses an object.
let staleGap = try gap.consume(Data("{\"type\":\"UtteranceEnd\",\"channel\":[0,1],\"last_word_end\":-1}".utf8))
precondition(staleGap == nil)
let gapEnd = try gap.consume(Data("{\"type\":\"UtteranceEnd\",\"channel\":[0,1],\"last_word_end\":2.395}".utf8))!
precondition(gapEnd.text == "Gym is done" && gapEnd.complete)
let speechStarted = try gap.consume(Data("{\"type\":\"SpeechStarted\",\"channel\":[0,1],\"timestamp\":0.5}".utf8))
precondition(speechStarted == nil)
do {
    _ = try gap.consume(event("Error"))
    fatalError("Provider error must never submit a turn")
} catch DeepgramTurn.Failure.rejected { }
do {
    _ = try gap.consume(Data("not JSON".utf8))
    fatalError("Malformed provider events must fail")
} catch { }
print("Deepgram turn checks passed: interim replacement, segment accumulation, endpoint, trailing interim, empty turn, metadata, provider error, invalid JSON.")
