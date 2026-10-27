import Foundation

// A Whisper segment as WhisperKit reports it, without WhisperKit types, so the
// mapping below is compiled and tested by `swift test`. Times are seconds from
// the start of the file (full-file transcription).
nonisolated struct WhisperSegment: Sendable, Equatable {
    var start: Float
    var end: Float
    // Includes Whisper's special tokens, e.g. "<|0.00|> Hello.<|1.06|>".
    var text: String
    // nil when the engine gave no word timing.
    var words: [WhisperWord]?
}

nonisolated struct WhisperWord: Sendable, Equatable {
    // With the leading space Whisper puts before a new word (" Hello").
    var text: String
    var start: Float
    var end: Float
}

// Maps Whisper output to the engine-independent shapes the Markdown and the
// timing sidecar are written from. Segments stay as Whisper made them; no
// time is repaired. Each segment's Markdown text is spelled from its units, so
// Review's text parity check holds by construction.
nonisolated enum WhisperRecognition {
    // "<|startoftranscript|>", "<|nl|>", "<|1.06|>", …
    static func removingSpecialTokens(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\|[^|>]*\|>"#, with: "", options: .regularExpression)
    }

    // A piece without leading whitespace continues the previous word of the
    // same segment: " 1" + ",5" -> " 1,5", " o" + "'clock" -> " o'clock".
    // ponytail: languages written without spaces would merge into one unit per segment; fine for nl/en.
    static func mergedWords(_ words: [WhisperWord]) -> [WhisperWord] {
        words.reduce(into: []) { merged, word in
            let text = removingSpecialTokens(word.text)
            guard !text.isEmpty else { return }
            if let last = merged.indices.last, text.first?.isWhitespace == false {
                merged[last].text += text
                merged[last].end = word.end
            } else {
                merged.append(WhisperWord(text: text, start: word.start, end: word.end))
            }
        }
    }

    static func map(_ segments: [WhisperSegment]) -> (segments: [TranscriptSegment], recognition: TimedRecognition) {
        var transcriptSegments: [TranscriptSegment] = []
        var recognition = TimedRecognition()
        for segment in segments {
            let units: [RecognitionUnit]
            if let words = segment.words, !words.isEmpty {
                units = mergedWords(words).map {
                    RecognitionUnit(text: $0.text, kind: RecognitionUnit.classify($0.text),
                                    start: seconds($0.start), end: seconds($0.end))
                }
            } else {
                let text = removingSpecialTokens(segment.text)
                units = text.allSatisfy(\.isWhitespace) ? [] : [RecognitionUnit(text: text, kind: .segment)]
            }
            let text = units.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = seconds(segment.start), end = seconds(segment.end)
            transcriptSegments.append(TranscriptSegment(startTime: start, endTime: end, text: text))
            recognition.results.append(RecognitionResult(start: start, end: end, units: units))
        }
        return (transcriptSegments, recognition)
    }

    // The Float's shortest decimal form (0.08, not 0.07999999821186066).
    static func seconds(_ value: Float) -> Double {
        Double("\(value)") ?? Double(value)
    }
}
