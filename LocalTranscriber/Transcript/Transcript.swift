import Foundation

enum TranscriptTranscriber: String, Sendable {
    case speechTranscriber = "SpeechTranscriber"
    case dictationTranscriber = "DictationTranscriber"
    // The WhisperKit Core ML model (LTR-76 phase 1). The recorded names are
    // provisional until the owner decides them (doc-3 Addendum 7 F).
    case whisperLargeV3Turbo = "openai_whisper-large-v3-v20240930_turbo"

    // The Engine written in the Markdown header and the timing sidecar.
    var engineName: String {
        self == .whisperLargeV3Turbo ? "WhisperKit" : "Apple SpeechAnalyzer"
    }
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
