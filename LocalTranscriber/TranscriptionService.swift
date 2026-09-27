import AVFoundation
import Speech

enum TranscriptionService {
    static func transcribe(
        url: URL,
        locale: Locale = Locale(identifier: "en-US")
    ) async throws -> Transcript {
        let file = try AVAudioFile(forReading: url)

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let segments: [TranscriptSegment] = try transcriber.results.reduce(into: []) {
            partialResult,
            result in

            let range = result.range
            partialResult.append(
                TranscriptSegment(
                    startTime: CMTimeGetSeconds(range.start),
                    endTime: CMTimeGetSeconds(CMTimeRangeGetEnd(range)),
                    text: String(result.text.characters)
                )
            )
        }

        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let sampleRate = file.processingFormat.sampleRate
        let duration = sampleRate.isFinite && sampleRate > 0
            ? Double(file.length) / sampleRate
            : nil

        return Transcript(
            sourceURL: url,
            localeIdentifier: locale.identifier,
            duration: duration,
            segments: try await segments
        )
    }
}

struct Transcript: Sendable {
    let sourceURL: URL
    let localeIdentifier: String
    let duration: TimeInterval?
    let segments: [TranscriptSegment]

    var characterCount: Int {
        segments.reduce(0) { $0 + $1.text.count }
    }
}

struct TranscriptSegment: Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

enum TranscriptMarkdownRenderer {
    static func render(_ transcript: Transcript) -> String {
        let sourceName = transcript.sourceURL.lastPathComponent
        var metadata = ["**Source:** `\(sourceName)`"]

        if let duration = transcript.duration {
            metadata.append("**Duration:** \(timestamp(duration.rounded()))")
        }

        metadata.append("**Language:** \(transcript.localeIdentifier)")
        metadata.append("**Engine:** Apple SpeechAnalyzer")

        var markdown = "# \(transcript.sourceURL.deletingPathExtension().lastPathComponent)\n\n"
        markdown += metadata.joined(separator: "  \n")
        markdown += "\n\n## Transcript"

        var blocks: [(minute: Int, startTime: TimeInterval, text: String)] = []
        let segments = transcript.segments.enumerated().sorted {
            $0.element.startTime == $1.element.startTime
                ? $0.offset < $1.offset
                : $0.element.startTime < $1.element.startTime
        }

        for (_, segment) in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let minute = Int(max(0, segment.startTime) / 60)
            if blocks.last?.minute == minute {
                blocks[blocks.count - 1].text += " " + text
            } else {
                blocks.append((minute, segment.startTime, text))
            }
        }

        for block in blocks {
            markdown += "\n\n### \(timestamp(block.startTime))\n\n\(block.text)"
        }

        return markdown + "\n"
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        return String(
            format: "%02d:%02d:%02d",
            totalSeconds / 3600,
            (totalSeconds % 3600) / 60,
            totalSeconds % 60
        )
    }
}
