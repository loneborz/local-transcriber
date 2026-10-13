import XCTest
@testable import TranscriptCore

// The goldens in Fixtures/golden were produced by the renderer at HEAD 094d0dd
// (before the timing sidecar work) from Fixtures/render-fixtures.json.
final class MarkdownRegressionTests: XCTestCase {
    private struct Case: Decodable {
        struct Segment: Decodable { let start, end: Double; let text: String }
        struct Source: Decodable {
            let sourceType, url, videoID, title: String
            let channel, uploadDate: String?
            let duration: Double?
            let audioFilename: String
        }
        let name, sourcePath, locale, transcriber: String
        let duration: Double?
        let source: Source?
        let segments: [Segment]

        var transcript: Transcript {
            Transcript(
                sourceURL: URL(fileURLWithPath: sourcePath),
                localeIdentifier: locale,
                transcriber: TranscriptTranscriber(rawValue: transcriber)!,
                duration: duration,
                segments: segments.map { TranscriptSegment(startTime: $0.start, endTime: $0.end, text: $0.text) }
            )
        }

        var metadata: SourceMetadata? {
            source.map {
                SourceMetadata(
                    sourceType: $0.sourceType, url: URL(string: $0.url)!, videoID: $0.videoID,
                    title: $0.title, channel: $0.channel, uploadDate: $0.uploadDate, duration: $0.duration,
                    acquiredAt: Date(timeIntervalSince1970: 0), audioFilename: $0.audioFilename
                )
            }
        }
    }

    private func fixtures() throws -> [Case] {
        let url = Bundle.module.url(forResource: "Fixtures/render-fixtures", withExtension: "json")!
        return try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
    }

    func testRenderedMarkdownIsByteIdenticalToTheHEADGoldens() throws {
        let cases = try fixtures()
        XCTAssertEqual(cases.count, 8)
        for fixture in cases {
            let golden = try Data(contentsOf: Bundle.module.url(
                forResource: "Fixtures/golden/\(fixture.name)", withExtension: "md")!)
            let rendered = Data(TranscriptMarkdownRenderer.render(fixture.transcript, source: fixture.metadata).utf8)
            XCTAssertEqual(rendered, golden, "\(fixture.name) differs from the HEAD 094d0dd golden")
        }
    }

    func testRecognitionDataNeverChangesTheMarkdown() throws {
        for fixture in try fixtures() {
            var transcript = fixture.transcript
            let before = TranscriptMarkdownRenderer.render(transcript, source: fixture.metadata)
            transcript.recognition = TimedRecognition(results: [
                RecognitionResult(start: 0, end: 1, units: [
                    RecognitionUnit(text: "Other", kind: .word, start: 0, end: 1),
                    RecognitionUnit(text: "text", kind: .word, start: .nan, end: nil),
                ])
            ])
            XCTAssertEqual(TranscriptMarkdownRenderer.render(transcript, source: fixture.metadata), before, fixture.name)
        }
    }
}
