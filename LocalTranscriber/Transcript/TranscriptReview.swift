import CryptoKit
import Foundation

// How a transcript's timing sidecar relates to its Markdown. Timing is trusted
// only for `.valid`; every other state keeps the Markdown fully readable and
// says in one line why precise timestamps are not available.
nonisolated enum SidecarState: Equatable, Sendable {
    // Decodes, belongs to these exact Markdown bytes, has usable times and its
    // text is the Markdown's text.
    case valid
    case missing
    // Present but not readable as a v1 sidecar (corrupt, truncated, unknown unit kind).
    case undecodable
    case unsupportedSchemaVersion(Int)
    // The Markdown is not the file the sidecar was written for (edited since).
    case markdownMismatch
    // Written for this Markdown, but no review line has a usable time.
    case noUsableTiming
    // Written for this Markdown, but its lines do not spell the Markdown's text.
    case textMismatch

    var isValid: Bool { self == .valid }

    // The one-line status shown when precise timestamps are unavailable.
    var notice: String? {
        switch self {
        case .valid:
            nil
        case .missing:
            "No timing data for this transcript. Headings mark minutes, not exact times."
        case .undecodable:
            "The timing file can’t be read. Showing the Markdown without exact timestamps."
        case .unsupportedSchemaVersion(let version):
            "The timing file uses schema version \(version), which this version doesn’t support. Showing the Markdown without exact timestamps."
        case .markdownMismatch:
            "The Markdown changed after it was transcribed, so exact timestamps are not shown."
        case .noUsableTiming:
            "The timing file has no usable times. Showing the Markdown without exact timestamps."
        case .textMismatch:
            "The timing file’s text differs from the Markdown. Showing the Markdown without exact timestamps."
        }
    }
}

// What the Review view shows for one transcript. The Markdown is authoritative:
// the sidecar's lines are shown only when they spell exactly the Markdown's text.
nonisolated struct TranscriptReview: Equatable, Sendable {
    enum Body: Equatable, Sendable {
        // Lines derived from the sidecar (ReviewLines.group); a line without a
        // start has no timestamp.
        case timed([ReviewLine])
        // The Markdown as saved: minute blocks, headings shown as headings.
        case markdown([TranscriptMarkdown.Block])
    }

    var header: TranscriptHeader
    var state: SidecarState
    var body: Body

    // `markdown` and `sidecar` are the file contents as read; `sidecar` is nil
    // when there is no file. A Markdown file that no longer parses as a
    // transcript is still shown, whole, under the header the library saw.
    static func make(item: LibraryTranscript, markdown: Data, sidecar: Data?) -> TranscriptReview {
        let text = String(decoding: markdown, as: UTF8.self)
        let parsed = TranscriptMarkdown.parse(text)
        let header = parsed?.header ?? item.header
        let blocks = parsed?.blocks ?? [TranscriptMarkdown.Block(heading: nil, text: text)]

        let (state, lines) = classify(markdown: markdown, blocks: blocks, sidecar: sidecar)
        return TranscriptReview(
            header: header,
            state: state,
            body: state.isValid ? .timed(lines) : .markdown(blocks)
        )
    }

    // Reads the files and builds the review. Throws only when the Markdown itself
    // cannot be read; a sidecar problem is a state, never an error.
    static func load(_ item: LibraryTranscript) throws -> TranscriptReview {
        let markdown = try Data(contentsOf: item.markdownURL)
        var sidecar: Data?
        if FileManager.default.fileExists(atPath: item.sidecarURL.path) {
            // Present but unreadable counts as undecodable, not as missing.
            sidecar = (try? Data(contentsOf: item.sidecarURL)) ?? Data()
        }
        return make(item: item, markdown: markdown, sidecar: sidecar)
    }

    static func classify(
        markdown: Data,
        blocks: [TranscriptMarkdown.Block],
        sidecar: Data?
    ) -> (SidecarState, [ReviewLine]) {
        guard let sidecar else { return (.missing, []) }

        let decoded: TranscriptSidecar
        do {
            decoded = try TranscriptSidecar.decode(sidecar)
        } catch SidecarError.unsupportedSchemaVersion(let version) {
            return (.unsupportedSchemaVersion(version), [])
        } catch {
            return (.undecodable, [])
        }

        guard decoded.markdown.sha256 == sha256(markdown) else { return (.markdownMismatch, []) }

        let lines = ReviewLines.group(decoded.recognition, duration: decoded.durationSeconds)
        guard lines.contains(where: { $0.start != nil }) else { return (.noUsableTiming, []) }

        // Same words in the same order, whatever the whitespace.
        let reviewText = lines.map(\.text).joined().filter { !$0.isWhitespace }
        let markdownText = blocks.map(\.text).joined().filter { !$0.isWhitespace }
        guard reviewText == markdownText else { return (.textMismatch, []) }

        return (.valid, lines)
    }

    // Lowercase hex, as the sidecar stores it.
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated enum TimestampFormat {
    // Shown instead of a time that cannot be one (not a number, or too large to
    // count in whole seconds), so no plausible but invented time appears.
    static let unavailable = "--:--"

    // "m:ss", or "h:mm:ss" from one hour; whole seconds, rounded down like the
    // Markdown headings. A negative time is the start (0:00).
    static func string(_ seconds: Double) -> String {
        // Int(exactly:) is nil for NaN, infinity and anything beyond Int; a plain
        // Int(_:) would trap on those.
        guard let whole = Int(exactly: seconds.rounded(.down)) else { return unavailable }
        let total = max(0, whole)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, total % 60)
            : String(format: "%d:%02d", minutes, total % 60)
    }
}
