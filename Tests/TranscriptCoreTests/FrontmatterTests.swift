import XCTest
@testable import TranscriptCore

// LTR-37: the optional YAML block before the Markdown, and Copy without it.
final class FrontmatterTests: TreeTestCase {
    private func transcript(
        _ path: String = "/x/Talk.m4a", duration: Double? = 89.6, locale: String = "en-US"
    ) -> Transcript {
        Transcript(sourceURL: URL(fileURLWithPath: path), localeIdentifier: locale, transcriber: .speechTranscriber,
                   duration: duration, segments: [TranscriptSegment(startTime: 0, endTime: 1, text: "Hello there.")])
    }

    // The string value of `key:`, decoded as the JSON string literal it is written as.
    private func value(_ key: String, in block: String) throws -> String? {
        guard let line = block.split(separator: "\n").first(where: { $0.hasPrefix(key + ": ") }) else { return nil }
        return try JSONDecoder().decode(String.self, from: Data(line.dropFirst(key.count + 2).utf8))
    }

    func testAFileGetsItsKnownFieldsOnly() {
        XCTAssertEqual(TranscriptMarkdownRenderer.frontmatter(for: transcript()), """
            ---
            source: "Talk.m4a"
            language: "en-US"
            transcriber: "SpeechTranscriber"
            duration: 90
            ---


            """)
    }

    func testARecordingAddsWhenItWasRecordedInLocalTime() {
        let block = TranscriptMarkdownRenderer.frontmatter(
            for: transcript(duration: nil), recorded: Date(timeIntervalSince1970: 1_793_000_000),
            timeZone: TimeZone(identifier: "Europe/Amsterdam")!)
        XCTAssertEqual(block, """
            ---
            source: "Talk.m4a"
            language: "en-US"
            transcriber: "SpeechTranscriber"
            recorded: 2026-10-26T08:33:20
            ---


            """)
    }

    func testAVideoNamesItsLinkAndPublicationDateButNeverItsTitle() throws {
        let block = TranscriptMarkdownRenderer.frontmatter(for: transcript(), video: video(title: "Never: \"here\""))
        XCTAssertEqual(try value("source", in: block), "https://www.youtube.com/watch?v=abc123")
        XCTAssertTrue(block.contains("\npublished: 2026-01-02\n"))
        XCTAssertFalse(block.contains("title"))
        XCTAssertFalse(block.contains("Never"))
        XCTAssertFalse(block.contains("recorded"))

        let unknown = TranscriptMarkdownRenderer.frontmatter(for: transcript(duration: nil), video: video(published: nil))
        XCTAssertFalse(unknown.contains("published"))
        XCTAssertFalse(unknown.contains("duration"))
    }

    func testAnUnrepresentableDurationIsOmitted() {
        for duration in [Double.nan, .infinity, -1, 1e300] {
            XCTAssertFalse(TranscriptMarkdownRenderer.frontmatter(for: transcript(duration: duration)).contains("duration"))
        }
    }

    func testAwkwardValuesAreEscapedNotGuessed() throws {
        let name = "Talk: \"one\" # two \\ ünï 日本 'x'\u{1}.m4a"
        let block = TranscriptMarkdownRenderer.frontmatter(for: transcript("/x/" + name, locale: "zh-Hant: #"))
        XCTAssertEqual(try value("source", in: block), name)
        XCTAssertEqual(try value("language", in: block), "zh-Hant: #")
        XCTAssertEqual(block.split(separator: "\n").count, 6, "a value never spans lines")
    }

    func testTheBodyAfterTheBlockIsTheMarkdownWrittenWithoutIt() throws {
        let body = markdown()
        let text = TranscriptMarkdownRenderer.frontmatter(for: transcript()) + body
        XCTAssertTrue(text.hasSuffix(body))
        XCTAssertEqual(TranscriptMarkdown.withoutFrontmatter(text), body)
        XCTAssertEqual(TranscriptMarkdown.parse(text), TranscriptMarkdown.parse(body))
    }

    func testCopyLeavesTextWithoutALeadingBlockUntouched() throws {
        let goldens = try XCTUnwrap(Bundle.module.urls(forResourcesWithExtension: "md", subdirectory: "Fixtures/golden"))
        XCTAssertEqual(goldens.count, 8)
        for url in goldens {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(Data(TranscriptMarkdown.withoutFrontmatter(text).utf8), try Data(contentsOf: url))
        }
        for text in ["", "---", "---\nnot closed\n# T\n", " ---\na: 1\n---\n", "--- \na: 1\n---\n", "# T\n---\na\n---\n"] {
            XCTAssertEqual(TranscriptMarkdown.withoutFrontmatter(text), text)
        }
    }

    func testCopyDropsALeadingBlockByTheParsersRule() {
        XCTAssertEqual(TranscriptMarkdown.withoutFrontmatter("---\ntags: [a]\n...\n  \n\n# T\n"), "# T\n")
        XCTAssertEqual(TranscriptMarkdown.withoutFrontmatter("---\r\na: 1\r\n---\r\n\r\n# T\r\nx"), "# T\r\nx")
        XCTAssertEqual(TranscriptMarkdown.withoutFrontmatter("---\na: 1\n---\n"), "")
    }

    func testTheSidecarOfATranscriptWithABlockIsValid() throws {
        let text = TranscriptMarkdownRenderer.frontmatter(for: transcript()) + markdown()
        try writePair("Talk", markdown: text)
        let item = try XCTUnwrap(try LibraryScanner.scan(folder: folder).first)
        let review = try TranscriptReview.load(item)
        XCTAssertEqual(review.state, .valid)
        XCTAssertEqual(review.body, .timed([
            ReviewLine(text: "Hello there.", start: 0, end: 1),
            ReviewLine(text: "Second minute.", start: 65, end: 66),
        ]))
    }
}
