import Foundation

// Which audio belongs to a transcript, and where in it a transcript line is.
// Pure logic only; AVFoundation and the file system stay in the app target.

nonisolated enum AudioResolution {
    // Source packages always hold the audio as `audio.m4a` (SourcePackageManifest.audioFilename).
    static let packageAudioName = "audio.m4a"
    // The media types the app accepts as input; a recording is an m4a.
    static let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "mp4", "mov"]
    // Provisional: the Markdown rounds its Duration to whole seconds, and the audio
    // and the analyzed audio can differ slightly. Not a product guarantee.
    static let durationTolerance: Double = 1.0

    // The one place the transcript's audio could be: nothing else is ever played.
    // - Source package: audio.m4a inside the package folder.
    // - Entry: the same, else audio.m4a in the entry folder (source package entries).
    // - Flat transcript: the file named by the Markdown's Source line, in the same
    //   folder. The name comes from the Source line, never from the Markdown's own
    //   name ("Meeting 2.md" belongs to "Meeting.m4a").
    // Nil when the transcript does not name a local file (a YouTube link, a path,
    // an unsupported or hidden name): there is nothing to look for.
    static func candidateURL(for item: LibraryTranscript) -> URL? {
        switch item.kind {
        case .package:
            return item.markdownURL.deletingLastPathComponent().appendingPathComponent(packageAudioName)
        case .flat:
            return namedAudioURL(for: item)
        case .entry:
            // The audio the Source line names, else the `audio.m4a` that a source
            // package entry keeps (its Source line is the video link).
            return namedAudioURL(for: item)
                ?? item.entryFolderURL.appendingPathComponent(packageAudioName)
        }
    }

    private static func namedAudioURL(for item: LibraryTranscript) -> URL? {
        let name = item.header.source
        guard isPlainFileName(name),
              supportedExtensions.contains((name as NSString).pathExtension.lowercased()) else { return nil }
        return item.markdownURL.deletingLastPathComponent().appendingPathComponent(name)
    }

    // A file name only: no separators, no parent references, not hidden, not a link.
    static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.hasPrefix(".")
            && !name.contains("/") && !name.contains(":") && !name.contains("\0")
    }

    // The audio found must be as long as the transcript says; otherwise it is some
    // other recording that happens to carry the name. A transcript without a known
    // duration cannot be confirmed, so it gets no playback.
    static func durationsAgree(audio: Double, transcript: Double?) -> Bool {
        guard let transcript, audio.isFinite, transcript.isFinite, audio > 0 else { return false }
        return abs(audio - transcript) <= durationTolerance
    }
}

// What the player may be asked to do, and why not.
nonisolated enum AudioAvailability: Equatable, Sendable {
    case available(URL)
    // The transcript does not name a local audio file.
    case notKept
    // The named file is not there (moved, deleted, never kept).
    case missing(String)
    // A file with that name exists but is not the recording this transcript describes.
    case mismatch(String)
    // The file exists but cannot be opened or played.
    case unreadable(String)

    // The plain statement shown instead of a player.
    var statement: String? {
        switch self {
        case .available: nil
        case .notKept: "This transcript has no audio file to play."
        case .missing(let name): "The audio “\(name)” isn’t in the output folder, so it can’t be played."
        case .mismatch(let name): "“\(name)” is not the recording this transcript was made from, so it isn’t played."
        case .unreadable(let name): "The audio “\(name)” can’t be played."
        }
    }
}

// Where the playhead is, relative to the transcript's timed lines.
nonisolated struct LineTimeline: Equatable, Sendable {
    struct Span: Equatable, Sendable {
        var line: Int      // index in the review's line list
        var start: Double
        var end: Double
    }

    // How long a line stays active after its own end (recognizers end a line at its
    // last word, but the voice trails off), unless another line starts first.
    static let hold: Double = 1.0

    // Timed lines only, ordered by start (ties by line order). Lines without a
    // usable start are never active and never seekable.
    private(set) var spans: [Span]

    init(lines: [ReviewLine]) {
        spans = lines.enumerated().compactMap { index, line in
            guard let start = line.start, start.isFinite, start >= 0 else { return nil }
            let end = (line.end?.isFinite == true ? line.end! : start)
            return Span(line: index, start: start, end: max(start, end))
        }.sorted { ($0.start, $0.line) < ($1.start, $1.line) }
    }

    // The line being spoken at `time`: the last line that has started, while its
    // end (plus `hold`) has not passed. Before the first line, in a long silence
    // and after the last line there is no active line. Never matches by text.
    func activeLine(at time: Double) -> Int? {
        guard time.isFinite, time >= 0, !spans.isEmpty else { return nil }
        var low = 0, high = spans.count        // first span with start > time
        while low < high {
            let mid = (low + high) / 2
            if spans[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return nil }
        let span = spans[low - 1]
        return time <= span.end + Self.hold ? span.line : nil
    }

    // Where a click on a line seeks to, or nil: the line has no usable time or it
    // lies outside the audio. A click never targets an invalid or out-of-range time.
    static func seekTarget(for line: ReviewLine, audioDuration: Double) -> Double? {
        guard let start = line.start, start.isFinite, start >= 0,
              audioDuration.isFinite, audioDuration > 0, start < audioDuration else { return nil }
        return start
    }
}
