import CryptoKit
import Foundation

// The timing sidecar written beside a new Markdown transcript:
// `<markdown name without .md>.timing.json`. Schema version 1, documented in
// doc-1. It holds the raw recognition (TimedRecognition) and nothing derived:
// review lines are computed from it by `ReviewLines`, so the grouping rules can
// change without retranscribing. No audio, confidence, speakers or absolute paths.
//
// {
//   "schemaVersion": 1,
//   "markdown": { "fileName": "Name.md", "sha256": "<hex of the exact saved bytes>" },
//   "engine": { "name": "Apple SpeechAnalyzer", "transcriber": "SpeechTranscriber" },
//   "locale": "en-US",
//   "durationSeconds": 13.14,                     (omitted when unknown)
//   "timingGranularity": "word" | "segment" | "none",
//   "results": [                                  (recognizer order, as emitted)
//     { "startSeconds": 0.2, "endSeconds": 4.1,   (the result's own range, if any)
//       "units": [ { "text": "Hello", "kind": "word" | "punctuation" | "segment",
//                    "startSeconds": 0.2, "endSeconds": 0.5 } ] }
//   ]
// }
//
// A time the engine did not give is omitted. A non-finite time cannot be stored
// in JSON: it is omitted and the unit or result carries "timingInvalid": true.
// Finite times are stored as emitted, even negative or reversed ones.
nonisolated struct TranscriptSidecar: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let fileExtension = "timing.json"
    static let engineName = "Apple SpeechAnalyzer"

    struct Markdown: Codable, Equatable, Sendable {
        var fileName: String
        var sha256: String
    }

    struct Engine: Codable, Equatable, Sendable {
        var name: String
        var transcriber: String
    }

    struct Unit: Codable, Equatable, Sendable {
        var text: String
        var kind: RecognitionUnit.Kind
        var startSeconds: Double?
        var endSeconds: Double?
        var timingInvalid: Bool?
    }

    struct Result: Codable, Equatable, Sendable {
        var startSeconds: Double?
        var endSeconds: Double?
        var timingInvalid: Bool?
        var units: [Unit]
    }

    var schemaVersion: Int
    var markdown: Markdown
    var engine: Engine
    var locale: String
    var durationSeconds: Double?
    var timingGranularity: TimingGranularity
    var results: [Result]

    init(
        recognition: TimedRecognition,
        transcriber: String,
        locale: String,
        duration: Double?,
        markdownFileName: String,
        markdown: Data
    ) {
        func finite(_ value: Double?) -> Double? { value.flatMap { $0.isFinite ? $0 : nil } }
        func invalid(_ values: Double?...) -> Bool? {
            values.contains { $0.map { !$0.isFinite } ?? false } ? true : nil
        }

        schemaVersion = Self.currentSchemaVersion
        self.markdown = Markdown(
            fileName: markdownFileName,
            sha256: SHA256.hash(data: markdown).map { String(format: "%02x", $0) }.joined()
        )
        engine = Engine(name: Self.engineName, transcriber: transcriber)
        self.locale = locale
        durationSeconds = finite(duration)
        timingGranularity = recognition.granularity
        results = recognition.results.map { result in
            Result(
                startSeconds: finite(result.start),
                endSeconds: finite(result.end),
                timingInvalid: invalid(result.start, result.end),
                units: result.units.map {
                    Unit(
                        text: $0.text,
                        kind: $0.kind,
                        startSeconds: finite($0.start),
                        endSeconds: finite($0.end),
                        timingInvalid: invalid($0.start, $0.end)
                    )
                }
            )
        }
    }

    // The raw recognition back from the stored form (non-finite times stay absent).
    var recognition: TimedRecognition {
        TimedRecognition(results: results.map { result in
            RecognitionResult(
                start: result.startSeconds,
                end: result.endSeconds,
                units: result.units.map {
                    RecognitionUnit(text: $0.text, kind: $0.kind, start: $0.startSeconds, end: $0.endSeconds)
                }
            )
        })
    }

    // Deterministic: sorted keys, compact, trailing newline.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    // Reads the version first, so a file from a newer app reports an
    // unsupported version instead of a confusing decoding error.
    static func decode(_ data: Data) throws -> TranscriptSidecar {
        struct Probe: Decodable { var schemaVersion: Int }
        let version = try JSONDecoder().decode(Probe.self, from: data).schemaVersion
        guard version == currentSchemaVersion else { throw SidecarError.unsupportedSchemaVersion(version) }
        return try JSONDecoder().decode(TranscriptSidecar.self, from: data)
    }
}

nonisolated enum SidecarError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case nameTaken(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Timing file schema version \(version) is not supported."
        case .nameTaken(let name):
            "A file named “\(name)” already exists."
        }
    }
}

// Naming and the no-overwrite write. Foundation only, so it is tested as is.
nonisolated enum SidecarFile {
    // `Name 2.md` -> `Name 2.timing.json`: always the Markdown file that was
    // actually written, never the input name.
    static func url(besides markdownURL: URL) -> URL {
        markdownURL.deletingPathExtension().appendingPathExtension(TranscriptSidecar.fileExtension)
    }

    // Never replaces a file. The data goes to a hidden temporary file first and
    // is then moved into place, which fails if the name is taken; so a failed
    // write leaves no partial sidecar, and an unrelated file with that name is
    // left as it is. (Not `.withoutOverwriting` + `.atomic`: Foundation traps.)
    static func write(_ data: Data, besides markdownURL: URL) throws -> URL {
        let destination = url(besides: markdownURL)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".LocalTranscriber-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }

        try data.write(to: temporary, options: .withoutOverwriting)
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            throw SidecarError.nameTaken(destination.lastPathComponent)
        }
        return destination
    }
}

extension TranscriptSidecar {
    // Called after the Markdown was saved. Never throws, so it cannot fail the
    // job or touch the Markdown: a failure comes back as a warning to show.
    static func save(
        _ transcript: Transcript,
        markdown: Data,
        markdownURL: URL,
        using write: (Data, URL) throws -> URL = SidecarFile.write
    ) -> String? {
        do {
            let sidecar = TranscriptSidecar(
                recognition: transcript.recognition,
                transcriber: transcript.transcriber.rawValue,
                locale: transcript.localeIdentifier,
                duration: transcript.duration,
                markdownFileName: markdownURL.lastPathComponent,
                markdown: markdown
            )
            _ = try write(try sidecar.encoded(), markdownURL)
            return nil
        } catch {
            let name = SidecarFile.url(besides: markdownURL).lastPathComponent
            return "Timing data was not saved (\(name)): \(error.localizedDescription) The transcript itself is saved."
        }
    }
}

// The order that matters: the Markdown is written first and the sidecar only
// when that succeeded. A failed Markdown write throws before anything else
// happens, so no sidecar can exist for a transcript that was not saved.
nonisolated struct SavedTranscript {
    // The Markdown file that was written (inside the package for a package).
    var markdownURL: URL
    // Set when only the sidecar failed; the transcript itself is saved.
    var sidecarWarning: String?
}

extension TranscriptSidecar {
    static func saveWithSidecar(
        _ transcript: Transcript,
        markdown: String,
        writeMarkdown: (String) throws -> URL,
        writeSidecar: (Data, URL) throws -> URL = SidecarFile.write
    ) throws -> SavedTranscript {
        let markdownURL = try writeMarkdown(markdown)
        return SavedTranscript(
            markdownURL: markdownURL,
            sidecarWarning: save(
                transcript, markdown: Data(markdown.utf8), markdownURL: markdownURL, using: writeSidecar)
        )
    }
}
