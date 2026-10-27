import XCTest
@testable import TranscriptCore

final class WhisperRecognitionTests: XCTestCase {
    // Shapes seen in LTR-66's WhisperKit runs: special tokens in the segment
    // text only, number pieces without a leading space.
    private let segments = [
        WhisperSegment(start: 0, end: 4.22, text: "<|startoftranscript|><|en|><|transcribe|><|0.00|> It costs 1,5 euro.<|4.22|>", words: [
            WhisperWord(text: " It", start: 1.1, end: 1.36),
            WhisperWord(text: " costs", start: 1.36, end: 2.02),
            WhisperWord(text: " 1", start: 2.02, end: 2.2),
            WhisperWord(text: ",5", start: 2.2, end: 2.42),
            WhisperWord(text: " euro.", start: 2.42, end: 3.06),
        ]),
        WhisperSegment(start: 4.22, end: 6, text: "<|4.22|> At nine o'clock.<|6.00|>", words: [
            WhisperWord(text: " At", start: 4.3, end: 4.5),
            WhisperWord(text: " nine", start: 4.5, end: 4.9),
            WhisperWord(text: " o", start: 4.9, end: 5.0),
            WhisperWord(text: "'clock.", start: 5.0, end: 5.6),
        ]),
    ]

    func testNumberPiecesMergeIntoOneTimedWordAndSpecialTokensNeverShow() {
        let (transcriptSegments, recognition) = WhisperRecognition.map(segments)

        XCTAssertEqual(transcriptSegments.map(\.text), ["It costs 1,5 euro.", "At nine o'clock."])
        XCTAssertEqual(transcriptSegments.map(\.startTime), [0, 4.22])
        XCTAssertEqual(recognition.results[0].units, [
            RecognitionUnit(text: " It", kind: .word, start: 1.1, end: 1.36),
            RecognitionUnit(text: " costs", kind: .word, start: 1.36, end: 2.02),
            RecognitionUnit(text: " 1,5", kind: .word, start: 2.02, end: 2.42),
            RecognitionUnit(text: " euro.", kind: .word, start: 2.42, end: 3.06),
        ])
        XCTAssertEqual(recognition.results[1].units.map(\.text), [" At", " nine", " o'clock."])
        XCTAssertEqual(recognition.granularity, .word)
        XCTAssertFalse(recognition.results.flatMap(\.units).contains { $0.text.contains("<|") })
    }

    func testPiecesNeverMergeAcrossSegmentsAndEmptySegmentsAreDropped() {
        let (transcriptSegments, recognition) = WhisperRecognition.map([
            WhisperSegment(start: 0, end: 1, text: "<|0.00|> A<|1.00|>", words: [WhisperWord(text: " A", start: 0, end: 1)]),
            WhisperSegment(start: 1, end: 2, text: "<|1.00|>.5<|2.00|>", words: [WhisperWord(text: ".5", start: 1, end: 2)]),
            WhisperSegment(start: 2, end: 3, text: "<|2.00|><|3.00|>", words: []),
        ])
        XCTAssertEqual(transcriptSegments.map(\.text), ["A", ".5"])
        XCTAssertEqual(recognition.results.count, 2)
    }

    func testSegmentWithoutWordTimingIsSegmentLevelData() {
        let (transcriptSegments, recognition) = WhisperRecognition.map([
            WhisperSegment(start: 2, end: 5, text: "<|2.00|> Hallo wereld.<|5.00|>", words: nil),
        ])
        XCTAssertEqual(transcriptSegments.map(\.text), ["Hallo wereld."])
        XCTAssertEqual(recognition.results, [
            RecognitionResult(start: 2, end: 5, units: [RecognitionUnit(text: " Hallo wereld.", kind: .segment)]),
        ])
        XCTAssertEqual(recognition.granularity, .segment)
    }

    func testFloatTimesKeepTheirShortestDecimalForm() {
        XCTAssertEqual(WhisperRecognition.seconds(0.08), 0.08)
        XCTAssertEqual(WhisperRecognition.seconds(3701.08), 3701.08)
    }

    // Whisper's Markdown is found by the library, and Review trusts its sidecar.
    func testWhisperTranscriptIsReadableWithValidTiming() throws {
        let (transcriptSegments, recognition) = WhisperRecognition.map(segments)
        let transcript = Transcript(
            sourceURL: URL(fileURLWithPath: "/x/Talk.wav"), localeIdentifier: "en-US",
            transcriber: .whisperLargeV3Turbo, duration: 6.5, segments: transcriptSegments, recognition: recognition
        )
        let markdown = TranscriptMarkdownRenderer.render(transcript)
        XCTAssertTrue(markdown.contains("**Engine:** WhisperKit  \n**Transcriber:** openai_whisper-large-v3-v20240930_turbo"))

        var sidecarData: Data?
        let saved = try TranscriptSidecar.saveWithSidecar(
            transcript, markdown: markdown,
            writeMarkdown: { _ in URL(fileURLWithPath: "/x/Talk/Talk.md") },
            writeSidecar: { data, url in sidecarData = data; return url }
        )
        XCTAssertNil(saved.sidecarWarning)
        let sidecar = try TranscriptSidecar.decode(try XCTUnwrap(sidecarData))
        XCTAssertEqual(sidecar.engine, .init(name: "WhisperKit", transcriber: "openai_whisper-large-v3-v20240930_turbo"))
        XCTAssertEqual(sidecar.schemaVersion, 1)

        let parsed = try XCTUnwrap(TranscriptMarkdown.parse(markdown))
        XCTAssertEqual(parsed.header.transcriber, "openai_whisper-large-v3-v20240930_turbo")
        let (state, lines) = TranscriptReview.classify(markdown: Data(markdown.utf8), blocks: parsed.blocks, sidecar: sidecarData)
        XCTAssertEqual(state, .valid)
        XCTAssertEqual(lines.first?.start, 1.1)
    }
}
