import Foundation

// What the header of a Markdown file written by TranscriptMarkdownRenderer says.
// This is how the library tells a Local Transcriber transcript from any other
// Markdown file: the `**Engine:** Apple SpeechAnalyzer` line plus a `## Transcript`
// section. Nothing here writes or rewrites a file.
nonisolated struct TranscriptHeader: Equatable, Sendable {
    var title: String
    // The Source line without its backticks: a file name for flat transcripts,
    // the video link for source packages.
    var source: String
    var channel: String?
    var published: String?
    var duration: TimeInterval?
    var language: String?
    var transcriber: String?
}

nonisolated enum TranscriptMarkdown {
    static let engineName = "Apple SpeechAnalyzer"
    static let transcriptHeading = "## Transcript"

    // One minute block of the Markdown body. Legacy transcripts only have these
    // (a `### 00:01:00` heading and its text), never sentence-level times.
    struct Block: Equatable, Sendable {
        var heading: String?
        var text: String
    }

    struct Parsed: Equatable, Sendable {
        var header: TranscriptHeader
        var blocks: [Block]
    }

    // Nil unless the text is a Local Transcriber transcript. A leading YAML block
    // (`---` … `---`) is skipped, so front matter added later does not hide a
    // transcript. Works on a prefix of a file too; the blocks are then partial.
    static func parse(_ text: String) -> Parsed? {
        // isNewline also splits "\r\n", which Swift treats as one Character.
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)[...]

        if lines.first == "---" {
            guard let close = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) else { return nil }
            lines = lines[(close + 1)...]
        }
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines = lines.dropFirst() }

        guard let first = lines.first, first.hasPrefix("# ") else { return nil }
        let title = first.dropFirst(2).trimmingCharacters(in: .whitespaces)
        lines = lines.dropFirst()

        var fields: [String: String] = [:]
        var foundTranscript = false
        while let line = lines.first {
            lines = lines.dropFirst()
            if line == transcriptHeading { foundTranscript = true; break }
            if line.hasPrefix("#") { return nil }
            if let (key, value) = field(line) { fields[key] = value }
        }

        guard foundTranscript, fields["Engine"] == engineName, let source = fields["Source"] else { return nil }

        let header = TranscriptHeader(
            title: title,
            source: stripBackticks(source),
            channel: fields["Channel"],
            published: fields["Published"],
            duration: fields["Duration"].flatMap(clock),
            language: fields["Language"],
            transcriber: fields["Transcriber"]
        )
        return Parsed(header: header, blocks: blocks(in: lines))
    }

    // What Copy puts on the clipboard (LTR-37): the text after a leading YAML
    // block and the blank lines after it, by the same rule as `parse`. Text
    // without one (or with an unclosed one) is returned unchanged.
    static func withoutFrontmatter(_ text: String) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard lines.first == "---",
              var body = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }).map({ $0 + 1 })
        else { return text }
        while body < lines.count, lines[body].trimmingCharacters(in: .whitespaces).isEmpty { body += 1 }
        return body < lines.count ? String(text[lines[body].startIndex...]) : ""
    }

    // `**Key:** value`, with the two trailing spaces of a Markdown line break.
    private static func field(_ line: String) -> (String, String)? {
        guard line.hasPrefix("**"), let close = line.range(of: ":**") else { return nil }
        let key = String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound])
        let value = line[close.upperBound...].trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : (key, value)
    }

    private static func stripBackticks(_ value: String) -> String {
        value.count >= 2 && value.hasPrefix("`") && value.hasSuffix("`") ? String(value.dropFirst().dropLast()) : value
    }

    // "01:02:06" -> seconds. Nil for anything that is not a non-negative
    // duration an Int can hold: the text is untrusted, so the arithmetic must
    // not trap (a hand-edited "9223372036854775807:00:00" would).
    private static func clock(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":").map { Int($0) }
        guard parts.count == 3, let h = parts[0], let m = parts[1], let s = parts[2],
              h >= 0, m >= 0, s >= 0 else { return nil }
        let (hours, o1) = h.multipliedReportingOverflow(by: 3600)
        let (minutes, o2) = m.multipliedReportingOverflow(by: 60)
        let (partial, o3) = hours.addingReportingOverflow(minutes)
        let (total, o4) = partial.addingReportingOverflow(s)
        return o1 || o2 || o3 || o4 ? nil : TimeInterval(total)
    }

    private static func blocks(in lines: ArraySlice<String>) -> [Block] {
        var blocks: [Block] = []
        var heading: String?
        var text: [String] = []

        func flush() {
            let body = text.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if heading != nil || !body.isEmpty { blocks.append(Block(heading: heading, text: body)) }
            text = []
        }

        for line in lines {
            if line.hasPrefix("### ") {
                flush()
                heading = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
            } else {
                text.append(line)
            }
        }
        flush()
        return blocks
    }
}
