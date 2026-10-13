import XCTest
@testable import TranscriptCore

final class ReviewLinesTests: XCTestCase {
    private func word(_ text: String, _ start: Double?, _ end: Double?) -> RecognitionUnit {
        RecognitionUnit(text: text, kind: .word, start: start, end: end)
    }

    private func mark(_ text: String, at time: Double?) -> RecognitionUnit {
        RecognitionUnit(text: text, kind: .punctuation, start: time, end: time)
    }

    private func recognition(_ units: [RecognitionUnit], start: Double? = nil, end: Double? = nil) -> TimedRecognition {
        TimedRecognition(results: [RecognitionResult(start: start, end: end, units: units)])
    }

    // MARK: classification and validity

    func testClassifyDistinguishesWordsFromMarks() {
        XCTAssertEqual(RecognitionUnit.classify("Hello"), .word)
        XCTAssertEqual(RecognitionUnit.classify("9"), .word)
        XCTAssertEqual(RecognitionUnit.classify("Привет"), .word)
        XCTAssertEqual(RecognitionUnit.classify("."), .punctuation)
        XCTAssertEqual(RecognitionUnit.classify("…"), .punctuation)
        XCTAssertEqual(RecognitionUnit.classify(" "), .punctuation)
        XCTAssertEqual(RecognitionUnit.classify(""), .punctuation)
    }

    func testUsableRangeRules() {
        XCTAssertEqual(TimingValidity.usableRange(start: 1, end: 2, duration: 10), 1...2)
        XCTAssertEqual(TimingValidity.usableRange(start: 3, end: 3, duration: nil), 3...3, "zero-width is valid")
        XCTAssertNil(TimingValidity.usableRange(start: nil, end: 2, duration: nil), "missing")
        XCTAssertNil(TimingValidity.usableRange(start: 1, end: nil, duration: nil), "missing")
        XCTAssertNil(TimingValidity.usableRange(start: .nan, end: 2, duration: nil), "NaN")
        XCTAssertNil(TimingValidity.usableRange(start: 1, end: .infinity, duration: nil), "infinite")
        XCTAssertNil(TimingValidity.usableRange(start: -0.5, end: 2, duration: nil), "negative start")
        XCTAssertNil(TimingValidity.usableRange(start: 5, end: 4, duration: nil), "reversed")
        XCTAssertNil(TimingValidity.usableRange(start: 11, end: 12, duration: 10), "starts after the end of the media")
        XCTAssertEqual(TimingValidity.usableRange(start: 9, end: 12, duration: 10), 9...12, "end past duration is kept as emitted")
    }

    func testGranularityFollowsTheActualData() {
        XCTAssertEqual(recognition([word("a", 0, 1)]).granularity, .word)
        XCTAssertEqual(
            recognition([RecognitionUnit(text: "a b", kind: .segment)], start: 0, end: 4).granularity, .segment)
        XCTAssertEqual(recognition([RecognitionUnit(text: "a b", kind: .segment)]).granularity, .none)
        XCTAssertEqual(recognition([word("a", .nan, .nan)], start: .infinity, end: 2).granularity, .none)
        XCTAssertEqual(TimedRecognition().granularity, .none)
    }

    // MARK: grouping

    func testGroupsAtSentenceEndsAndKeepsPunctuationAttached() {
        let lines = ReviewLines.group(recognition([
            word("Hello", 0.0, 0.4), word("world", 0.5, 0.9), mark(".", at: 0.9),
            word("How", 1.0, 1.2), word("are", 1.3, 1.5), word("you", 1.6, 1.9), mark("?", at: 1.9),
        ]))
        XCTAssertEqual(lines, [
            ReviewLine(text: "Hello world.", start: 0.0, end: 0.9),
            ReviewLine(text: "How are you?", start: 1.0, end: 1.9),
        ])
    }

    func testPauseStartsANewLineAndTheThresholdIsAnOption() {
        let units = [word("one", 0, 1), word("two", 3, 4)]
        let split = ReviewLines.group(recognition(units))
        XCTAssertEqual(split.map(\.text), ["one", "two"])
        XCTAssertEqual(split[1].start, 3)

        var patient = ReviewLineOptions()
        patient.maxPause = 5
        XCTAssertEqual(ReviewLines.group(recognition(units), options: patient).map(\.text), ["one two"],
                       "the same raw units regroup under other rules without retranscribing")
    }

    func testLongLinesAreCutAtMaxLineDuration() {
        var options = ReviewLineOptions()
        options.maxPause = 100
        options.maxLineDuration = 5
        let units = (0..<8).map { word("w\($0)", Double($0), Double($0) + 0.5) }
        let lines = ReviewLines.group(recognition(units), options: options)
        XCTAssertEqual(lines.map(\.text), ["w0 w1 w2 w3 w4", "w5 w6 w7"])
    }

    func testGroupingIsDeterministic() {
        let input = recognition([word("a", 0, 1), mark(",", at: 1), word("b", 1.1, 2), mark(".", at: 2), word("c", 9, 10)])
        let first = ReviewLines.group(input)
        for _ in 0..<20 { XCTAssertEqual(ReviewLines.group(input), first) }
        XCTAssertEqual(ReviewLines.algorithmVersion, 1)
    }

    func testZeroWidthPunctuationDoesNotMoveLineTimesOutsideTheWords() {
        let lines = ReviewLines.group(recognition([word("end", 2, 3), mark(".", at: 3)]))
        XCTAssertEqual(lines, [ReviewLine(text: "end.", start: 2, end: 3)])
    }

    func testPunctuationAtTheStartOfTheNextResultAttachesToThePreviousLine() {
        // DictationTranscriber starts a result with the previous sentence's mark.
        let input = TimedRecognition(results: [
            RecognitionResult(start: 0, end: 2, units: [word("Eerste", 0, 1), word("zin", 1, 2)]),
            RecognitionResult(start: 2, end: 4, units: [mark(".", at: 2), word("Tweede", 2.1, 3), word("zin", 3, 4)]),
        ])
        XCTAssertEqual(ReviewLines.group(input).map(\.text), ["Eerste zin.", "Tweede zin"])
    }

    func testMarkWithEmittedLeadingWhitespaceIsKeptSeparate() {
        let lines = ReviewLines.group(recognition([word("word", 0, 1), RecognitionUnit(text: " —", kind: .punctuation)]))
        XCTAssertEqual(lines.map(\.text), ["word —"])
    }

    func testRecognitionOrderIsKeptEvenWhenTimesAreOutOfOrderOrOverlap() {
        let lines = ReviewLines.group(recognition([
            word("late", 10, 11), word("early", 2, 3), word("overlap", 2.5, 3.5),
        ]))
        XCTAssertEqual(lines.map(\.text), ["late early overlap"], "negative gaps never split and nothing is re-sorted")
        XCTAssertEqual(lines[0].start, 10)
        XCTAssertEqual(lines[0].end, 11)
    }

    func testInvalidMissingAndEmptyUnitsKeepTheirTextAndNeverInventTimes() {
        let lines = ReviewLines.group(recognition([
            word("none", nil, nil), word("nan", .nan, 1), word("neg", -1, 1), word("rev", 4, 3),
            word("   ", 5, 6), word("", nil, nil),
        ]))
        XCTAssertEqual(lines, [ReviewLine(text: "none nan neg rev", start: nil, end: nil)])
    }

    func testBeyondDurationStartIsIgnoredForTime() {
        let lines = ReviewLines.group(recognition([word("in", 1, 2), word("out", 50, 51)]), duration: 10)
        XCTAssertEqual(lines.map(\.text), ["in out"])
        XCTAssertEqual(lines[0].start, 1)
        XCTAssertEqual(lines[0].end, 2)
    }

    func testSegmentOnlyResultsUseTheirOwnRangeAndNothingFiner() {
        let input = TimedRecognition(results: [
            RecognitionResult(start: 0, end: 30, units: [RecognitionUnit(text: "A whole segment of text", kind: .segment)]),
            RecognitionResult(start: 30, end: 45, units: [RecognitionUnit(text: "Another one", kind: .segment)]),
        ])
        XCTAssertEqual(ReviewLines.group(input), [
            ReviewLine(text: "A whole segment of text", start: 0, end: 30),
            ReviewLine(text: "Another one", start: 30, end: 45),
        ])
    }

    func testFullyUntimedRecognitionGivesLinesWithoutTimes() {
        let input = recognition([RecognitionUnit(text: "Just text.", kind: .segment)])
        XCTAssertEqual(ReviewLines.group(input), [ReviewLine(text: "Just text.", start: nil, end: nil)])
        XCTAssertEqual(ReviewLines.group(TimedRecognition()), [])
    }

    func testTimedUnitsAreNotGivenTheResultRangeWhenOneUnitIsUntimed() {
        let lines = ReviewLines.group(recognition([word("a", 5, 6), word("b", nil, nil)], start: 0, end: 60))
        XCTAssertEqual(lines, [ReviewLine(text: "a b", start: 5, end: 6)])
    }
}

// Real recognizer output (synthetic speech, no personal data), written by the app
// on 2026-10-14: SpeechTranscriber attaches marks to the word run (" mild.");
// DictationTranscriber reports them as separate zero-width runs (". ") and puts
// a trailing space on every run.
final class RealRecognitionFixtureTests: XCTestCase {
    private func load(_ name: String) throws -> TranscriptSidecar {
        let url = Bundle.module.url(forResource: "Fixtures/real/\(name).timing", withExtension: "json")!
        return try TranscriptSidecar.decode(Data(contentsOf: url))
    }

    func testSpeechTranscriberOutputGroupsIntoSentences() throws {
        let sidecar = try load("en-short")
        XCTAssertEqual(sidecar.engine.transcriber, "SpeechTranscriber")
        let lines = ReviewLines.group(sidecar.recognition, duration: sidecar.durationSeconds)
        XCTAssertEqual(lines.map(\.text), [
            "The weather today is clear and mild.",
            "We will meet at the station at 9 o'clock, and then walk to the museum together, after lunch.",
            "The group will discuss the schedule for next week.",
            "Please bring your notebook, a pen and a bottle of water.",
        ])
        XCTAssertEqual(lines[0].start, 0)
        XCTAssertEqual(lines[0].end, 1.86)
        XCTAssertEqual(lines[3].start, 9.96)
        XCTAssertEqual(lines[3].end, 12.9)
    }

    func testDictationTranscriberOutputKeepsMarksAttachedAndGroupsIntoSentences() throws {
        let sidecar = try load("nl-short")
        XCTAssertEqual(sidecar.engine.transcriber, "DictationTranscriber")
        XCTAssertEqual(sidecar.results.flatMap(\.units).filter { $0.kind == .punctuation }.count, 4)
        let lines = ReviewLines.group(sidecar.recognition, duration: sidecar.durationSeconds)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0].text, "De temperatuur is vandaag mild en het is droog.")
        XCTAssertEqual(lines[0].start, 0)
        XCTAssertEqual(lines[0].end, 2.49, "the zero-width mark ends the line where it was emitted")
        XCTAssertTrue(lines.allSatisfy { $0.text.hasSuffix(".") && !$0.text.contains(" .") })
    }

    func testRegroupingRealDataUnderOtherRulesNeedsNoRetranscription() throws {
        let sidecar = try load("en-short")
        var options = ReviewLineOptions()
        options.sentenceEnders = []
        options.maxPause = 1000
        options.maxLineDuration = 1000
        XCTAssertEqual(ReviewLines.group(sidecar.recognition, options: options).count, 1)
    }
}
