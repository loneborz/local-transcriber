import Foundation

enum TranscriptMarkdownRenderer {
    // `source` is given for source packages, where the transcript describes
    // the video itself (title, link, channel, date) instead of the local file
    // the audio happened to be downloaded into.
    static func render(_ transcript: Transcript, source: SourceMetadata? = nil) -> String {
        var metadata: [String]
        var title: String
        if let source {
            title = source.title.split(whereSeparator: \.isNewline).joined(separator: " ")
            metadata = ["**Source:** \(source.url.absoluteString)"]
            if let channel = source.channel { metadata.append("**Channel:** \(channel)") }
            if let published = source.uploadDate { metadata.append("**Published:** \(published)") }
        } else {
            title = transcript.sourceURL.deletingPathExtension().lastPathComponent
            metadata = ["**Source:** `\(transcript.sourceURL.lastPathComponent)`"]
        }

        if let duration = transcript.duration {
            metadata.append("**Duration:** \(timestamp(duration.rounded()))")
        }

        metadata.append("**Language:** \(transcript.localeIdentifier)")
        metadata.append("**Engine:** Apple SpeechAnalyzer")
        metadata.append("**Transcriber:** \(transcript.transcriber.rawValue)")

        var markdown = "# \(title)\n\n"
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

    // The optional YAML block put before `render`'s output (LTR-37), for
    // Obsidian Properties. Known values only, never a title. `video` is a
    // YouTube job's metadata (flat or package), `recorded` a recording's start,
    // written as local date-time like Obsidian's own. Strings are JSON string
    // literals, which are valid YAML double-quoted scalars.
    static func frontmatter(
        for transcript: Transcript, video: SourceMetadata? = nil, recorded: Date? = nil, timeZone: TimeZone = .current
    ) -> String {
        var lines = [
            "source: " + quoted(video?.url.absoluteString ?? transcript.sourceURL.lastPathComponent),
            "language: " + quoted(transcript.localeIdentifier),
            "transcriber: " + quoted(transcript.transcriber.rawValue),
        ]
        if let duration = transcript.duration, duration >= 0, let seconds = Int(exactly: duration.rounded()) {
            lines.append("duration: \(seconds)")
        }
        if let recorded {
            let style = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().time(includingFractionalSeconds: false)
            lines.append("recorded: " + recorded.formatted(style))
        }
        // Already yyyy-MM-dd (YouTubeAcquirer), so it stays a YAML date.
        if let published = video?.uploadDate { lines.append("published: \(published)") }
        return "---\n" + lines.joined(separator: "\n") + "\n---\n\n"
    }

    private static func quoted(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        // Encoding a String cannot fail.
        return String(decoding: try! encoder.encode(value), as: UTF8.self)
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
