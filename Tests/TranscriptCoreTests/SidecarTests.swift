import XCTest
@testable import TranscriptCore

final class SidecarTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    }

    override func tearDown() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }

    private let recognition = TimedRecognition(results: [
        RecognitionResult(start: 0.25, end: 4.5, units: [
            RecognitionUnit(text: "Hello", kind: .word, start: 0.25, end: 0.75),
            RecognitionUnit(text: ",", kind: .punctuation, start: 0.75, end: 0.75),
            RecognitionUnit(text: " wörld", kind: .word, start: 1.0, end: 1.5),
        ]),
        RecognitionResult(start: 4.5, end: 9, units: [
            RecognitionUnit(text: "A segment “quoted” / slash", kind: .segment),
        ]),
    ])

    private func sidecar(
        _ recognition: TimedRecognition? = nil,
        markdown: String = "abc",
        name: String = "Name.md",
        duration: Double? = 9.5
    ) -> TranscriptSidecar {
        TranscriptSidecar(
            recognition: recognition ?? self.recognition,
            transcriber: "SpeechTranscriber",
            locale: "en-US",
            duration: duration,
            markdownFileName: name,
            markdown: Data(markdown.utf8)
        )
    }

    private func transcript(_ recognition: TimedRecognition? = nil) -> Transcript {
        Transcript(
            sourceURL: URL(fileURLWithPath: "/x/Name.m4a"), localeIdentifier: "en-US",
            transcriber: .speechTranscriber, duration: 9.5, segments: [],
            recognition: recognition ?? self.recognition
        )
    }

    // MARK: serialization

    func testEncodedBytesAreExactlyTheDocumentedSchema() throws {
        let json = String(decoding: try sidecar().encoded(), as: UTF8.self)
        XCTAssertEqual(json, """
        {"durationSeconds":9.5,"engine":{"name":"Apple SpeechAnalyzer","transcriber":"SpeechTranscriber"},\
        "locale":"en-US","markdown":{"fileName":"Name.md","sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},\
        "results":[{"endSeconds":4.5,"startSeconds":0.25,"units":[\
        {"endSeconds":0.75,"kind":"word","startSeconds":0.25,"text":"Hello"},\
        {"endSeconds":0.75,"kind":"punctuation","startSeconds":0.75,"text":","},\
        {"endSeconds":1.5,"kind":"word","startSeconds":1,"text":" wörld"}]},\
        {"endSeconds":9,"startSeconds":4.5,"units":[{"kind":"segment","text":"A segment “quoted” / slash"}]}],\
        "schemaVersion":1,"timingGranularity":"word"}

        """)
    }

    func testEncodingIsDeterministic() throws {
        let first = try sidecar().encoded()
        for _ in 0..<10 { XCTAssertEqual(try sidecar().encoded(), first) }
    }

    func testRoundTripPreservesEverythingIncludingOrderAndText() throws {
        let original = sidecar()
        let decoded = try TranscriptSidecar.decode(try original.encoded())
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.recognition, recognition)
        XCTAssertEqual(
            decoded.recognition.results.flatMap(\.units).map(\.text),
            ["Hello", ",", " wörld", "A segment “quoted” / slash"], "text, punctuation and order as emitted")
    }

    func testMarkdownHashIsOfTheExactBytes() {
        // SHA-256("abc") test vector.
        XCTAssertEqual(sidecar(markdown: "abc").markdown.sha256,
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertNotEqual(sidecar(markdown: "abc\n").markdown.sha256, sidecar(markdown: "abc").markdown.sha256)
    }

    func testSidecarCarriesNoPathsOrForbiddenFields() throws {
        let json = String(decoding: try sidecar().encoded(), as: UTF8.self)
        for forbidden in ["confidence", "speaker", "alternatives", "/Users", "/x/", "audio\""] {
            XCTAssertFalse(json.contains(forbidden), forbidden)
        }
    }

    func testNonFiniteTimesAreOmittedAndFlaggedFiniteOddOnesKeptAsEmitted() throws {
        let odd = TimedRecognition(results: [
            RecognitionResult(start: .nan, end: 2, units: [
                RecognitionUnit(text: "nan", kind: .word, start: .nan, end: 1),
                RecognitionUnit(text: "inf", kind: .word, start: 1, end: .infinity),
                RecognitionUnit(text: "neg", kind: .word, start: -2, end: -1),
                RecognitionUnit(text: "rev", kind: .word, start: 5, end: 4),
                RecognitionUnit(text: "none", kind: .word),
            ])
        ])
        let stored = sidecar(odd, duration: .nan)
        let data = try stored.encoded()   // would throw if a non-finite value reached JSON
        let decoded = try TranscriptSidecar.decode(data)
        XCTAssertNil(decoded.durationSeconds)
        XCTAssertEqual(decoded.results[0].timingInvalid, true)
        XCTAssertNil(decoded.results[0].startSeconds)
        XCTAssertEqual(decoded.results[0].endSeconds, 2)
        let units = decoded.results[0].units
        XCTAssertEqual(units.map(\.timingInvalid), [true, true, nil, nil, nil])
        XCTAssertEqual([units[0].startSeconds, units[0].endSeconds].map { $0 ?? -99 }, [-99, 1])
        XCTAssertEqual([units[1].startSeconds, units[1].endSeconds].map { $0 ?? -99 }, [1, -99])
        XCTAssertEqual([units[2].startSeconds, units[2].endSeconds].map { $0 ?? -99 }, [-2, -1], "negative kept as emitted")
        XCTAssertEqual([units[3].startSeconds, units[3].endSeconds].map { $0 ?? -99 }, [5, 4], "reversed kept as emitted")
        XCTAssertNil(units[4].startSeconds)
        XCTAssertNil(units[4].timingInvalid, "missing is not invalid")
        XCTAssertEqual(decoded.timingGranularity, .word)
    }

    func testGranularityIsStored() throws {
        let segmentOnly = TimedRecognition(results: [
            RecognitionResult(start: 0, end: 3, units: [RecognitionUnit(text: "t", kind: .segment)])])
        XCTAssertEqual(sidecar(segmentOnly).timingGranularity, .segment)
        XCTAssertEqual(sidecar(TimedRecognition()).timingGranularity, .none)
        XCTAssertEqual(sidecar().timingGranularity, .word)
    }

    // MARK: schema version

    func testDecodeAcceptsOnlyTheCurrentSchemaVersion() throws {
        XCTAssertEqual(TranscriptSidecar.currentSchemaVersion, 1)
        XCTAssertEqual(try TranscriptSidecar.decode(try sidecar().encoded()).schemaVersion, 1)

        let future = Data(#"{"schemaVersion":2,"somethingNew":[1,2,3]}"#.utf8)
        XCTAssertThrowsError(try TranscriptSidecar.decode(future)) {
            XCTAssertEqual($0 as? SidecarError, .unsupportedSchemaVersion(2))
        }
        let zero = Data(#"{"schemaVersion":0}"#.utf8)
        XCTAssertThrowsError(try TranscriptSidecar.decode(zero)) {
            XCTAssertEqual($0 as? SidecarError, .unsupportedSchemaVersion(0))
        }
        XCTAssertThrowsError(try TranscriptSidecar.decode(Data("not json".utf8)))
        XCTAssertThrowsError(try TranscriptSidecar.decode(Data("{}".utf8)), "a missing version is not accepted")
    }

    // MARK: naming

    func testSidecarNameFollowsTheResolvedMarkdownName() {
        func name(_ markdown: String) -> String {
            SidecarFile.url(besides: folder.appendingPathComponent(markdown)).lastPathComponent
        }
        XCTAssertEqual(name("Name.md"), "Name.timing.json")
        XCTAssertEqual(name("Name 2.md"), "Name 2.timing.json", "collision-resolved name, not the input name")
        XCTAssertEqual(name("Name 3.md"), "Name 3.timing.json")
        XCTAssertEqual(name("a.b.md"), "a.b.timing.json")
        XCTAssertEqual(name("Title [abc123XYZ_-].md"), "Title [abc123XYZ_-].timing.json")
        XCTAssertEqual(name("transcript.md"), "transcript.timing.json")
        XCTAssertEqual(
            SidecarFile.url(besides: folder.appendingPathComponent("Name.md")).deletingLastPathComponent().path,
            folder.path)
    }

    // MARK: writing

    private func markdownFile(_ name: String, _ content: String = "# md\n") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(content.utf8).write(to: url, options: .withoutOverwriting)
        return url
    }

    private func entries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    func testSaveWritesTheSidecarBesideTheMarkdownAndItMatchesTheBytes() throws {
        let markdown = "# Name\n\nHello wörld\n"
        let url = try markdownFile("Name 2.md", markdown)
        XCTAssertNil(TranscriptSidecar.save(transcript(), markdown: Data(markdown.utf8), markdownURL: url))

        XCTAssertEqual(try entries(), ["Name 2.md", "Name 2.timing.json"], "no temporary file is left")
        let stored = try TranscriptSidecar.decode(Data(contentsOf: folder.appendingPathComponent("Name 2.timing.json")))
        XCTAssertEqual(stored.markdown.fileName, "Name 2.md")
        XCTAssertEqual(stored, TranscriptSidecar(
            recognition: recognition, transcriber: "SpeechTranscriber", locale: "en-US", duration: 9.5,
            markdownFileName: "Name 2.md", markdown: Data(markdown.utf8)))
    }

    func testAnUnrelatedFileWithTheSidecarNameIsNeverOverwrittenOrReused() throws {
        let url = try markdownFile("Name.md")
        let occupant = try markdownFile("Name.timing.json", "unrelated content")
        let warning = TranscriptSidecar.save(transcript(), markdown: Data("# md\n".utf8), markdownURL: url)

        XCTAssertNotNil(warning)
        XCTAssertTrue(warning!.contains("Name.timing.json"), warning!)
        XCTAssertTrue(warning!.contains("already exists"), warning!)
        XCTAssertTrue(warning!.contains("transcript itself is saved"), warning!)
        XCTAssertEqual(try String(contentsOf: occupant, encoding: .utf8), "unrelated content")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# md\n", "Markdown untouched")
        XCTAssertEqual(try entries(), ["Name.md", "Name.timing.json"], "no temporary file is left")
    }

    func testWritingTwiceNeverReplacesTheFirstSidecar() throws {
        let url = try markdownFile("Name.md")
        XCTAssertNil(TranscriptSidecar.save(transcript(), markdown: Data("# md\n".utf8), markdownURL: url))
        let first = try Data(contentsOf: folder.appendingPathComponent("Name.timing.json"))
        XCTAssertNotNil(TranscriptSidecar.save(transcript(TimedRecognition()), markdown: Data("# md\n".utf8), markdownURL: url))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Name.timing.json")), first)
    }

    func testAFailedSidecarWriteKeepsTheMarkdownAndLeavesNothingBehind() throws {
        let url = try markdownFile("Name.md", "# keep me\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        let warning = TranscriptSidecar.save(transcript(), markdown: Data("# keep me\n".utf8), markdownURL: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)

        XCTAssertNotNil(warning, "a failure is reported, never presented as success")
        XCTAssertTrue(warning!.hasPrefix("Timing data was not saved"), warning!)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# keep me\n")
        XCTAssertEqual(try entries(), ["Name.md"], "no partial sidecar or temporary file")
    }

    func testAnEncodingOrWriteErrorFromTheInjectedWriterBecomesAWarning() throws {
        struct Boom: LocalizedError { var errorDescription: String? { "disk on fire." } }
        let url = try markdownFile("Name.md")
        let warning = TranscriptSidecar.save(transcript(), markdown: Data(), markdownURL: url) { _, _ in throw Boom() }
        XCTAssertEqual(warning, "Timing data was not saved (Name.timing.json): disk on fire. The transcript itself is saved.")
        XCTAssertEqual(try entries(), ["Name.md"])
    }

    // MARK: Markdown first, sidecar only after it

    private struct MarkdownFailure: LocalizedError { var errorDescription: String? { "no space left" } }

    func testAFailedMarkdownWriteThrowsAndNeverAttemptsASidecar() throws {
        var sidecarAttempts = 0
        XCTAssertThrowsError(try TranscriptSidecar.saveWithSidecar(
            transcript(),
            markdown: "# md\n",
            writeMarkdown: { _ in throw MarkdownFailure() },
            writeSidecar: { _, _ in sidecarAttempts += 1; return self.folder }
        )) { XCTAssertTrue($0 is MarkdownFailure, "the Markdown error reaches the caller, so it is not a success") }
        XCTAssertEqual(sidecarAttempts, 0)
        XCTAssertEqual(try entries(), [])
    }

    func testARealFailedMarkdownWriteLeavesNoSidecarAndNoFilesAtAll() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        XCTAssertThrowsError(try TranscriptSidecar.saveWithSidecar(
            transcript(),
            markdown: "# md\n",
            writeMarkdown: { markdown in
                let url = self.folder.appendingPathComponent("Name.md")
                try Data(markdown.utf8).write(to: url, options: .withoutOverwriting)
                return url
            }
        ))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        XCTAssertEqual(try entries(), [], "neither Markdown, sidecar nor a temporary file")
    }

    func testMarkdownSavedAndSidecarFailedIsStillASavedTranscriptWithAWarning() throws {
        let occupant = try markdownFile("Name.timing.json", "someone else's file")
        let saved = try TranscriptSidecar.saveWithSidecar(
            transcript(),
            markdown: "# md\n",
            writeMarkdown: { markdown in
                // The same collision-free write the app does: never replaces a file.
                let url = self.folder.appendingPathComponent("Name.md")
                try Data(markdown.utf8).write(to: url, options: .withoutOverwriting)
                return url
            }
        )
        XCTAssertEqual(saved.markdownURL.lastPathComponent, "Name.md")
        XCTAssertNotNil(saved.sidecarWarning)
        XCTAssertEqual(try String(contentsOf: saved.markdownURL, encoding: .utf8), "# md\n")
        XCTAssertEqual(try String(contentsOf: occupant, encoding: .utf8), "someone else's file")
        XCTAssertEqual(try entries(), ["Name.md", "Name.timing.json"])
    }

    func testSidecarHashIsOfTheExactMarkdownTheWriterReceived() throws {
        var written = Data()
        let saved = try TranscriptSidecar.saveWithSidecar(
            transcript(),
            markdown: "# Wörld\n\nüber\n",
            writeMarkdown: { markdown in
                written = Data(markdown.utf8)
                let url = self.folder.appendingPathComponent("Name 2.md")
                try written.write(to: url, options: .withoutOverwriting)
                return url
            }
        )
        XCTAssertNil(saved.sidecarWarning)
        let stored = try TranscriptSidecar.decode(Data(contentsOf: SidecarFile.url(besides: saved.markdownURL)))
        XCTAssertEqual(stored.markdown.sha256, TranscriptSidecar(
            recognition: TimedRecognition(), transcriber: "x", locale: "x", duration: nil,
            markdownFileName: "x", markdown: try Data(contentsOf: saved.markdownURL)).markdown.sha256)
        XCTAssertEqual(stored.markdown.fileName, "Name 2.md")
    }

    func testPackageShapedSaveWritesTheSidecarInsideThePackageFolder() throws {
        let package = folder.appendingPathComponent("VIDEOID", isDirectory: true)
        let saved = try TranscriptSidecar.saveWithSidecar(
            transcript(),
            markdown: "# md\n",
            writeMarkdown: { markdown in
                try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
                let url = package.appendingPathComponent("transcript.md")
                try Data(markdown.utf8).write(to: url, options: .withoutOverwriting)
                return url
            }
        )
        XCTAssertNil(saved.sidecarWarning)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: package.path).sorted(),
                       ["transcript.md", "transcript.timing.json"])
        XCTAssertEqual(try entries(), ["VIDEOID"], "nothing outside the package")
    }

    func testMarkdownNameAtTheFilesystemLimitGivesAWarningNotAFailureOrAStrayFile() throws {
        // 255 bytes is the limit; ".timing.json" is 9 bytes longer than ".md".
        let name = String(repeating: "a", count: 252) + ".md"
        let url = try markdownFile(name, "# long\n")
        let saved = try TranscriptSidecar.saveWithSidecar(
            transcript(), markdown: "# long\n", writeMarkdown: { _ in url })
        XCTAssertNotNil(saved.sidecarWarning)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# long\n")
        XCTAssertEqual(try entries(), [name], "no partial sidecar and no temporary file")
    }
}
