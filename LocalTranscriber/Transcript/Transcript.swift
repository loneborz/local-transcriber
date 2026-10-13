import Foundation

enum TranscriptTranscriber: String, Sendable {
    case speechTranscriber = "SpeechTranscriber"
    case dictationTranscriber = "DictationTranscriber"
}

struct Transcript: Sendable {
    let sourceURL: URL
    let localeIdentifier: String
    let transcriber: TranscriptTranscriber
    let duration: TimeInterval?
    let segments: [TranscriptSegment]
    // The recognizer's raw timed output, kept for the timing sidecar. The
    // Markdown is rendered from `segments` only.
    var recognition = TimedRecognition()

    var characterCount: Int {
        segments.reduce(0) { $0 + $1.text.count }
    }
}

struct TranscriptSegment: Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}
