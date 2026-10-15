import XCTest
@testable import TranscriptCore

final class TranscriptMarkdownTests: XCTestCase {
    private func render(_ segments: [(Double, String)], source: SourceMetadata? = nil) -> String {
        TranscriptMarkdownRenderer.render(
            Transcript(sourceURL: URL(fileURLWithPath: "/x/Talk.m4a"), localeIdentifier: "en-US",
                       transcriber: .speechTranscriber, duration: 120,
                       segments: segments.map { TranscriptSegment(startTime: $0.0, endTime: $0.0 + 1, text: $0.1) }),
            source: source)
    }

    func testParsesWhatTheRendererWrites() throws {
        let parsed = try XCTUnwrap(TranscriptMarkdown.parse(render([(0, "One."), (30, "Two."), (61, "Three.")])))
        XCTAssertEqual(parsed.header.title, "Talk")
        XCTAssertEqual(parsed.header.source, "Talk.m4a")
        XCTAssertEqual(parsed.header.duration, 120)
        XCTAssertEqual(parsed.blocks, [
            .init(heading: "00:00:00", text: "One. Two."),
            .init(heading: "00:01:01", text: "Three."),
        ])
    }

    func testATranscriptWithoutSegmentsStillParses() throws {
        let parsed = try XCTUnwrap(TranscriptMarkdown.parse(render([])))
        XCTAssertEqual(parsed.blocks, [])
    }

    func testOnlyTheHeaderAndTranscriptSectionMakeATranscript() {
        XCTAssertNil(TranscriptMarkdown.parse(""))
        XCTAssertNil(TranscriptMarkdown.parse("# Notes\n\nhello\n"))
        XCTAssertNil(TranscriptMarkdown.parse("**Engine:** Apple SpeechAnalyzer\n\n## Transcript\n"), "needs a title")
        XCTAssertNil(TranscriptMarkdown.parse("# T\n\n**Source:** `x`  \n**Engine:** Other\n\n## Transcript\n"))
        XCTAssertNil(TranscriptMarkdown.parse("# T\n\n**Engine:** Apple SpeechAnalyzer\n\n## Transcript\n"), "needs a Source line")
        XCTAssertNil(TranscriptMarkdown.parse("# T\n\n**Source:** `x`  \n**Engine:** Apple SpeechAnalyzer\n\n## Other\n\n## Transcript\n"),
                     "another section before the transcript")
    }

    private func parsedDuration(_ value: String) throws -> TimeInterval? {
        let text = "# T\n\n**Source:** `x`  \n**Duration:** \(value)  \n**Engine:** Apple SpeechAnalyzer\n\n## Transcript\n"
        return try XCTUnwrap(TranscriptMarkdown.parse(text), "the transcript is still recognized").header.duration
    }

    func testDurationParsesNormalValues() throws {
        XCTAssertEqual(try parsedDuration("00:00:00"), 0)
        XCTAssertEqual(try parsedDuration("00:01:30"), 90)
        XCTAssertEqual(try parsedDuration("01:02:06"), 3726)
        XCTAssertEqual(try parsedDuration("100:00:00"), 360_000)
    }

    func testAnUnrepresentableDurationIsDroppedNotTrapped() throws {
        // The first is the input the independent review crashed on (h * 3600 overflows Int).
        for value in ["9223372036854775807:00:00", "9223372036854775807:59:59", "2562047788015216:00:00",
                      "00:9223372036854775807:00", "99999999999999999999:00:00"] {
            XCTAssertNil(try parsedDuration(value), value)
        }
        // The largest value that fits is still taken as it is.
        XCTAssertEqual(try parsedDuration("2562047788015215:00:00"), 2562047788015215.0 * 3600)
    }

    func testMalformedDurationComponentsAreDropped() throws {
        for value in ["-1:00:00", "00:-5:00", "00:00:-1", "1:2", "1:2:3:4", "aa:bb:cc", "", "00:00:1.5"] {
            XCTAssertNil(try parsedDuration(value), value)
        }
    }

    func testBodyTextIsKeptVerbatim() throws {
        let text = "# T\n\n**Source:** `x`  \n**Engine:** Apple SpeechAnalyzer\n\n## Transcript\n\n### 00:00:00\n\nLine one\nline two — “quoted” & <b>\n"
        let parsed = try XCTUnwrap(TranscriptMarkdown.parse(text))
        XCTAssertEqual(parsed.blocks.map(\.text), ["Line one\nline two — “quoted” & <b>"])
    }
}

final class TimestampFormatTests: XCTestCase {
    func testFormatsWholeSecondsRoundedDown() {
        XCTAssertEqual(TimestampFormat.string(0), "0:00")
        XCTAssertEqual(TimestampFormat.string(59.99), "0:59")
        XCTAssertEqual(TimestampFormat.string(61), "1:01")
        XCTAssertEqual(TimestampFormat.string(599), "9:59")
        XCTAssertEqual(TimestampFormat.string(3600), "1:00:00")
        XCTAssertEqual(TimestampFormat.string(3725.4), "1:02:05")
        XCTAssertEqual(TimestampFormat.string(-4), "0:00")
    }

    // Times come from files: they may be anything, and must never trap.
    func testATimeThatIsNotATimeIsNotInventedAndNeverTraps() {
        for value in [Double.nan, .infinity, -.infinity, 1e30, -1e30, 9.3e18, Double.greatestFiniteMagnitude] {
            XCTAssertEqual(TimestampFormat.string(value), TimestampFormat.unavailable, "\(value)")
        }
        XCTAssertNotEqual(TimestampFormat.unavailable, TimestampFormat.string(0))
    }

    func testLargeButRepresentableTimesStillFormat() {
        XCTAssertEqual(TimestampFormat.string(360_000), "100:00:00")
        XCTAssertEqual(TimestampFormat.string(86_399.9), "23:59:59")
    }
}

final class TranscriptReviewTests: TreeTestCase {
    // MARK: building a Markdown + sidecar pair

    private func item(_ name: String = "Talk") throws -> LibraryTranscript {
        try XCTUnwrap(try LibraryScanner.scan(folder: folder).first { $0.markdownURL.lastPathComponent == "\(name).md" })
    }

    private let two = TimedRecognition(results: [
        RecognitionResult(start: 0, end: 1, units: [
            RecognitionUnit(text: "Hello", kind: .word, start: 0, end: 0.5),
            RecognitionUnit(text: " there.", kind: .word, start: 0.5, end: 1),
        ]),
        RecognitionResult(start: 65, end: 66, units: [RecognitionUnit(text: "Second minute.", kind: .word, start: 65, end: 66)]),
    ])
    private var twoMarkdown: String { markdown(seconds: [(0, "Hello there."), (65, "Second minute.")]) }

    private func sidecar(_ recognition: TimedRecognition, for markdown: String, duration: Double? = 90) throws -> Data {
        try TranscriptSidecar(recognition: recognition, transcriber: "SpeechTranscriber", locale: "en-US", duration: duration,
                              markdownFileName: "Talk.md", markdown: Data(markdown.utf8)).encoded()
    }

    private func review(markdown text: String, sidecar data: Data?) throws -> TranscriptReview {
        try write(text, "Talk.md")
        if let data { try writeData(data, "Talk.timing.json") }
        return try TranscriptReview.load(try item())
    }

    // MARK: classification

    func testValidSidecarGivesTimedLines() throws {
        let result = try review(markdown: twoMarkdown, sidecar: try sidecar(two, for: twoMarkdown))
        XCTAssertEqual(result.state, .valid)
        XCTAssertNil(result.state.notice)
        XCTAssertEqual(result.body, .timed([
            ReviewLine(text: "Hello there.", start: 0, end: 1),
            ReviewLine(text: "Second minute.", start: 65, end: 66),
        ]))
    }

    func testMissingSidecarShowsTheMarkdownWithItsMinuteHeadings() throws {
        let result = try review(markdown: twoMarkdown, sidecar: nil)
        XCTAssertEqual(result.state, .missing)
        XCTAssertNotNil(result.state.notice)
        XCTAssertEqual(result.body, .markdown([
            .init(heading: "00:00:00", text: "Hello there."),
            .init(heading: "00:01:05", text: "Second minute."),
        ]))
    }

    func testUndecodableSidecarsFallBackToTheMarkdown() throws {
        let valid = String(decoding: try sidecar(two, for: twoMarkdown), as: UTF8.self)
        let unknownKind = valid.replacingOccurrences(of: "\"kind\":\"word\"", with: "\"kind\":\"emoji\"")
        XCTAssertNotEqual(unknownKind, valid)
        for (name, bad) in [
            ("garbage", Data("{not json".utf8)), ("empty", Data()),
            ("truncated", Data(valid.prefix(valid.count / 2).utf8)),
            ("unknown unit kind", Data(unknownKind.utf8)),
            ("no version", Data("{}".utf8)),
        ] {
            let result = try review(markdown: twoMarkdown, sidecar: bad)
            XCTAssertEqual(result.state, .undecodable, name)
            guard case .markdown(let blocks) = result.body else { return XCTFail(name) }
            XCTAssertEqual(blocks.count, 2, name)
        }
    }

    func testAnUnreadableSidecarFileIsUndecodableNotMissing() throws {
        try write(twoMarkdown, "Talk.md")
        let url = try writeData(try sidecar(two, for: twoMarkdown), "Talk.timing.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        XCTAssertEqual(try TranscriptReview.load(try item()).state, .undecodable)
    }

    func testAnotherSchemaVersionIsReportedWithItsNumber() throws {
        let future = String(decoding: try sidecar(two, for: twoMarkdown), as: UTF8.self)
            .replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":7")
        let result = try review(markdown: twoMarkdown, sidecar: Data(future.utf8))
        XCTAssertEqual(result.state, .unsupportedSchemaVersion(7))
        XCTAssertTrue(try XCTUnwrap(result.state.notice).contains("7"))
        guard case .markdown = result.body else { return XCTFail("the Markdown stays readable") }
    }

    func testAnEditedMarkdownNoLongerMatchesItsSidecar() throws {
        let data = try sidecar(two, for: twoMarkdown)
        for edit in [twoMarkdown + "\n", twoMarkdown.replacingOccurrences(of: "Hello", with: "Hullo"),
                     twoMarkdown.replacingOccurrences(of: "\n", with: "\r\n")] {
            let result = try review(markdown: edit, sidecar: data)
            XCTAssertEqual(result.state, .markdownMismatch)
            guard case .markdown(let blocks) = result.body else { return XCTFail("falls back to the Markdown") }
            XCTAssertFalse(blocks.isEmpty)
        }
    }

    func testASidecarWithoutAnyUsableTimeIsNotTrusted() throws {
        let untimed = TimedRecognition(results: [
            RecognitionResult(start: nil, end: nil, units: [RecognitionUnit(text: "Hello there.", kind: .word)]),
            RecognitionResult(start: .nan, end: -3, units: [RecognitionUnit(text: "Second minute.", kind: .word, start: 9, end: 2)]),
        ])
        let result = try review(markdown: twoMarkdown, sidecar: try sidecar(untimed, for: twoMarkdown))
        XCTAssertEqual(result.state, .noUsableTiming)
        guard case .markdown = result.body else { return XCTFail() }
    }

    func testASidecarWhoseTextIsNotTheMarkdownsTextIsNotShown() throws {
        let other = TimedRecognition(results: [
            RecognitionResult(start: 0, end: 1, units: [RecognitionUnit(text: "Something else entirely.", kind: .word, start: 0, end: 1)]),
        ])
        // The hash is right (it is of this Markdown); only the words differ.
        let result = try review(markdown: twoMarkdown, sidecar: try sidecar(other, for: twoMarkdown))
        XCTAssertEqual(result.state, .textMismatch)
        guard case .markdown(let blocks) = result.body else { return XCTFail() }
        XCTAssertEqual(blocks.map(\.text), ["Hello there.", "Second minute."])
    }

    func testRecognitionOutOfTimeOrderFallsBackBecauseTheMarkdownIsSortedByTime() throws {
        let swapped = TimedRecognition(results: Array(two.results.reversed()))
        let result = try review(markdown: twoMarkdown, sidecar: try sidecar(swapped, for: twoMarkdown))
        XCTAssertEqual(result.state, .textMismatch)
    }

    func testAMarkdownThatIsNoLongerATranscriptIsStillShownWhole() throws {
        let edited = "Just my own notes now.\n\nSecond paragraph.\n"
        try write(twoMarkdown, "Talk.md")
        let listed = try item()
        try write(edited, "Talk.md")
        let result = try TranscriptReview.load(listed)
        XCTAssertEqual(result.header, listed.header)
        XCTAssertEqual(result.body, .markdown([.init(heading: nil, text: edited)]), "verbatim, nothing trimmed or rewritten")
    }

    func testMarkdownThatCannotBeReadIsTheOnlyThingThatThrows() throws {
        try write(twoMarkdown, "Talk.md")
        let listed = try item()
        try FileManager.default.removeItem(at: listed.markdownURL)
        XCTAssertThrowsError(try TranscriptReview.load(listed))
    }

    // MARK: lines

    func testLinesWithoutATimeCarryNoTimestamp() throws {
        let md = markdown(seconds: [(0, "Untimed words."), (65, "Second minute.")])
        let recognition = TimedRecognition(results: [
            RecognitionResult(start: nil, end: nil, units: [RecognitionUnit(text: "Untimed words.", kind: .word)]),
            two.results[1],
        ])
        let result = try review(markdown: md, sidecar: try sidecar(recognition, for: md))
        XCTAssertEqual(result.state, .valid)
        XCTAssertEqual(result.body, .timed([
            ReviewLine(text: "Untimed words.", start: nil, end: nil),
            ReviewLine(text: "Second minute.", start: 65, end: 66),
        ]))
    }

    func testSparseRecognitionIsShownAsItIsWithNoFillerOrInventedTimes() throws {
        let md = markdown(seconds: [(2, "Ja"), (600, "dank")], duration: 700)
        let recognition = TimedRecognition(results: [
            RecognitionResult(start: 2, end: 2.4, units: [RecognitionUnit(text: "Ja", kind: .word, start: 2, end: 2.4)]),
            RecognitionResult(start: 600, end: 600.5, units: [RecognitionUnit(text: "dank", kind: .word, start: 600, end: 600.5)]),
        ])
        let result = try review(markdown: md, sidecar: try sidecar(recognition, for: md, duration: 700))
        XCTAssertEqual(result.body, .timed([
            ReviewLine(text: "Ja", start: 2, end: 2.4),
            ReviewLine(text: "dank", start: 600, end: 600.5),
        ]))
    }

    func testNothingRecognizedIsAnEmptyTranscriptNotAFailure() throws {
        let md = markdown(seconds: [])
        let result = try review(markdown: md, sidecar: try sidecar(TimedRecognition(), for: md))
        XCTAssertEqual(result.state, .noUsableTiming)
        XCTAssertEqual(result.body, .markdown([]))
    }

    // MARK: the committed real recognizer output

    // The committed real fixtures hold only the sidecars. The Markdown is rendered
    // from their result texts the way the app does (segments, trimmed, minute
    // headings), and a sidecar for exactly those bytes is built from the real
    // recognition. The review text must then equal the Markdown text.
    private func realPair(_ name: String) throws -> (markdown: String, sidecar: Data, recognition: TimedRecognition) {
        let url = Bundle.module.url(forResource: "Fixtures/real/\(name).timing", withExtension: "json")!
        let real = try TranscriptSidecar.decode(Data(contentsOf: url))
        let segments = real.results.map {
            TranscriptSegment(
                startTime: $0.startSeconds ?? 0, endTime: $0.endSeconds ?? 0,
                text: $0.units.map(\.text).joined())
        }
        let md = TranscriptMarkdownRenderer.render(Transcript(
            sourceURL: URL(fileURLWithPath: "/x/\(name).m4a"), localeIdentifier: real.locale,
            transcriber: real.engine.transcriber == "SpeechTranscriber" ? .speechTranscriber : .dictationTranscriber,
            duration: real.durationSeconds, segments: segments))
        let data = try TranscriptSidecar(
            recognition: real.recognition, transcriber: real.engine.transcriber, locale: real.locale,
            duration: real.durationSeconds, markdownFileName: "Talk.md", markdown: Data(md.utf8)).encoded()
        return (md, data, real.recognition)
    }

    func testEnglishRealOutputReviewsAsTimedLinesWithTheMarkdownsText() throws {
        let pair = try realPair("en-short")
        let result = try review(markdown: pair.markdown, sidecar: pair.sidecar)
        XCTAssertEqual(result.state, .valid)
        guard case .timed(let lines) = result.body else { return XCTFail() }
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines.first?.text, "The weather today is clear and mild.")
        XCTAssertEqual(lines.map { $0.start.map(TimestampFormat.string) }, ["0:00", "0:01", "0:07", "0:09"])
        XCTAssertEqual(lines.map(\.text).joined().filter { !$0.isWhitespace },
                       TranscriptMarkdown.parse(pair.markdown)!.blocks.map(\.text).joined().filter { !$0.isWhitespace })
    }

    func testDutchDictationOutputReviewsWithTheMarkdownsText() throws {
        let pair = try realPair("nl-short")
        let result = try review(markdown: pair.markdown, sidecar: pair.sidecar)
        XCTAssertEqual(result.state, .valid)
        guard case .timed(let lines) = result.body else { return XCTFail() }
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines.first?.text, "De temperatuur is vandaag mild en het is droog.")
        XCTAssertTrue(lines.allSatisfy { !$0.text.contains(" .") })
    }

    func testTheRealFixturesFallBackWhenTheirMarkdownWasChanged() throws {
        for name in ["en-short", "nl-short"] {
            let pair = try realPair(name)
            let result = try review(markdown: pair.markdown + "A line added by hand.\n", sidecar: pair.sidecar)
            XCTAssertEqual(result.state, .markdownMismatch, name)
        }
    }
}

final class AudioReviewTests: TreeTestCase {
    private func flat(source: String, md: String = "Meeting.md") throws -> LibraryTranscript {
        try write(markdown(name: source), md)
        return try XCTUnwrap(try LibraryScanner.scan(folder: folder).first { $0.markdownURL.lastPathComponent == md })
    }

    // MARK: audio resolution

    func testARecordingIsFoundBySourceLineNotByTheMarkdownName() throws {
        // The Markdown was written as "Meeting 2.md" because "Meeting.md" existed; the recording is "Meeting.m4a".
        try write(markdown(name: "Meeting.m4a"), "Meeting.md")
        let item = try flat(source: "Meeting.m4a", md: "Meeting 2.md")
        XCTAssertEqual(item.markdownURL.lastPathComponent, "Meeting 2.md")
        XCTAssertEqual(AudioResolution.candidateURL(for: item)?.lastPathComponent, "Meeting.m4a")
        XCTAssertEqual(AudioResolution.candidateURL(for: item)?.deletingLastPathComponent().path, folder.path)
    }

    func testASimilarlyNamedFileIsNeverChosenWhenTheSourceLineNamesAnother() throws {
        try write("x", "Meeting 2.m4a")                       // resembles the Markdown name
        let item = try flat(source: "Talk.m4a", md: "Meeting 2.md")
        XCTAssertEqual(AudioResolution.candidateURL(for: item)?.lastPathComponent, "Talk.m4a")
    }

    func testASourcePackageUsesItsAudioFile() throws {
        try write(markdown(source: video()), "abc123/transcript.md")
        let item = try XCTUnwrap(try LibraryScanner.scan(folder: folder).first)
        XCTAssertEqual(AudioResolution.candidateURL(for: item), folder.appendingPathComponent("abc123/audio.m4a"))
    }

    func testSourcesThatAreNotALocalFileResolveToNothing() throws {
        // A YouTube link, paths, hidden names, unsupported types.
        for source in ["https://www.youtube.com/watch?v=abc", "../Elsewhere/Meeting.m4a", "sub/Meeting.m4a", "/etc/passwd.m4a",
                       ".hidden.m4a", "Meeting.txt", "Meeting", "a:b.m4a", ".."] {
            let text = markdown(name: "x.m4a").replacingOccurrences(of: "**Source:** `x.m4a`", with: "**Source:** `\(source)`")
            try write(text, "T.md")
            let item = try XCTUnwrap(try LibraryScanner.scan(folder: folder).first)
            XCTAssertNil(AudioResolution.candidateURL(for: item), source)
        }
    }

    func testAKnownMediaSourceFromAnyEngineCaseIsAccepted() throws {
        for name in ["a.M4A", "a.mp3", "a.wav", "a.mp4", "a.MOV"] {
            XCTAssertNotNil(AudioResolution.candidateURL(for: try flat(source: name, md: "x.md")), name)
        }
    }

    func testDurationAgreementDecidesWhetherAFileIsTheRecording() {
        XCTAssertTrue(AudioResolution.durationsAgree(audio: 90.4, transcript: 90))
        XCTAssertTrue(AudioResolution.durationsAgree(audio: 89.2, transcript: 90))
        XCTAssertFalse(AudioResolution.durationsAgree(audio: 95, transcript: 90), "another recording with the same name")
        XCTAssertFalse(AudioResolution.durationsAgree(audio: 90, transcript: nil), "unknown duration cannot be confirmed")
        XCTAssertFalse(AudioResolution.durationsAgree(audio: 0, transcript: 0))
        XCTAssertFalse(AudioResolution.durationsAgree(audio: .nan, transcript: 90))
    }

    func testEveryUnavailableStateHasAPlainStatementAndAvailableHasNone() {
        XCTAssertNil(AudioAvailability.available(URL(fileURLWithPath: "/x/a.m4a")).statement)
        for state in [AudioAvailability.notKept, .missing("a.m4a"), .mismatch("a.m4a"), .unreadable("a.m4a")] {
            XCTAssertFalse(try XCTUnwrap(state.statement).isEmpty)
        }
        XCTAssertTrue(try XCTUnwrap(AudioAvailability.missing("Meeting.m4a").statement).contains("Meeting.m4a"))
    }

    // MARK: timeline

    private func line(_ start: Double?, _ end: Double? = nil) -> ReviewLine { ReviewLine(text: "t", start: start, end: end) }

    func testNoLineIsActiveBeforeTheFirstTimedLine() {
        let timeline = LineTimeline(lines: [line(5, 8), line(9, 12)])
        XCTAssertNil(timeline.activeLine(at: 0))
        XCTAssertNil(timeline.activeLine(at: 4.99))
        XCTAssertEqual(timeline.activeLine(at: 5), 0, "a line is active from its start")
    }

    func testTheNextLineTakesOverExactlyAtItsStartAndGapsHoldThenGoQuiet() {
        let timeline = LineTimeline(lines: [line(5, 8), line(20, 24)])
        XCTAssertEqual(timeline.activeLine(at: 7.9), 0)
        XCTAssertEqual(timeline.activeLine(at: 8.9), 0, "holds for a second after its end")
        XCTAssertNil(timeline.activeLine(at: 9.5), "a long pause has no active line")
        XCTAssertNil(timeline.activeLine(at: 19.99))
        XCTAssertEqual(timeline.activeLine(at: 20), 1)
        let touching = LineTimeline(lines: [line(5, 8), line(8, 12)])
        XCTAssertEqual(touching.activeLine(at: 8), 1, "a line that starts at the previous end wins")
    }

    func testAfterTheLastLineThereIsNoActiveLine() {
        let timeline = LineTimeline(lines: [line(5, 8)])
        XCTAssertEqual(timeline.activeLine(at: 9), 0)
        XCTAssertNil(timeline.activeLine(at: 9.01))
        XCTAssertNil(timeline.activeLine(at: 10_000))
    }

    func testUntimedAndInvalidLinesAreNeverActiveAndKeepTheirIndexes() {
        let lines = [line(nil), line(2, 4), line(.nan, 3), line(-1, 2), line(6, 7)]
        let timeline = LineTimeline(lines: lines)
        XCTAssertEqual(timeline.spans.map(\.line), [1, 4])
        XCTAssertEqual(timeline.activeLine(at: 3), 1, "the index is the position in the review's list")
        XCTAssertEqual(timeline.activeLine(at: 6.5), 4)
    }

    func testSeekingBackwardAndForwardGivesTheRightLineEachTime() {
        let timeline = LineTimeline(lines: [line(1, 2), line(10, 12), line(30, 33)])
        XCTAssertEqual(timeline.activeLine(at: 31), 2)
        XCTAssertEqual(timeline.activeLine(at: 10), 1, "backward")
        XCTAssertEqual(timeline.activeLine(at: 1.5), 0)
        XCTAssertEqual(timeline.activeLine(at: 32), 2, "forward again")
    }

    func testRecognizerOrderIsNotAssumedToBeTimeOrder() {
        // Overlapping and out-of-order ranges: lookup works on start times.
        let timeline = LineTimeline(lines: [line(20, 25), line(5, 22), line(12, 13)])
        XCTAssertEqual(timeline.activeLine(at: 6), 1)
        XCTAssertEqual(timeline.activeLine(at: 12.5), 2)
        XCTAssertEqual(timeline.activeLine(at: 21), 0, "the latest started line is the active one")
    }

    func testBadTimesNeverMatchAndAnEmptyTimelineHasNoLine() {
        XCTAssertNil(LineTimeline(lines: []).activeLine(at: 1))
        let timeline = LineTimeline(lines: [line(1, 2)])
        for time in [Double.nan, -1, .infinity] { XCTAssertNil(timeline.activeLine(at: time)) }
    }

    func testAClickSeeksOnlyToAValidTimeInsideTheAudio() {
        XCTAssertEqual(LineTimeline.seekTarget(for: line(12.5, 14), audioDuration: 90), 12.5)
        XCTAssertEqual(LineTimeline.seekTarget(for: line(0, 1), audioDuration: 90), 0)
        XCTAssertNil(LineTimeline.seekTarget(for: line(nil), audioDuration: 90), "untimed line")
        XCTAssertNil(LineTimeline.seekTarget(for: line(.nan, 1), audioDuration: 90))
        XCTAssertNil(LineTimeline.seekTarget(for: line(-3, 1), audioDuration: 90))
        XCTAssertNil(LineTimeline.seekTarget(for: line(90, 91), audioDuration: 90), "at or past the end")
        XCTAssertNil(LineTimeline.seekTarget(for: line(500, 510), audioDuration: 90), "beyond the audio")
        XCTAssertNil(LineTimeline.seekTarget(for: line(5, 6), audioDuration: 0))
        XCTAssertNil(LineTimeline.seekTarget(for: line(5, 6), audioDuration: .nan))
    }
}
