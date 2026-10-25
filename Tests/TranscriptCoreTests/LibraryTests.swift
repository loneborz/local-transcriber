import CryptoKit
import XCTest
@testable import TranscriptCore

// A scratch folder plus builders for the files a Local Transcriber output folder holds.
class TreeTestCase: XCTestCase {
    var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    }

    override func tearDown() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }

    // Markdown exactly as the app renders it.
    func markdown(
        name: String = "Talk.m4a",
        seconds: [(Double, String)] = [(0, "Hello there."), (65, "Second minute.")],
        duration: Double? = 90,
        locale: String = "en-US",
        transcriber: TranscriptTranscriber = .speechTranscriber,
        source: SourceMetadata? = nil
    ) -> String {
        TranscriptMarkdownRenderer.render(
            Transcript(
                sourceURL: URL(fileURLWithPath: "/x/\(name)"), localeIdentifier: locale,
                transcriber: transcriber, duration: duration,
                segments: seconds.map { TranscriptSegment(startTime: $0.0, endTime: $0.0 + 1, text: $0.1) }),
            source: source)
    }

    func video(id: String = "abc123", title: String = "A video", channel: String? = "Chan",
               published: String? = "2026-01-02", duration: Double? = 90) -> SourceMetadata {
        SourceMetadata(
            sourceType: "youtube", url: URL(string: "https://www.youtube.com/watch?v=\(id)")!, videoID: id,
            title: title, channel: channel, uploadDate: published, duration: duration,
            acquiredAt: Date(timeIntervalSinceReferenceDate: 0), audioFilename: "audio.m4a")
    }

    @discardableResult
    func write(_ text: String, _ path: String, modified: Date? = nil) throws -> URL {
        try writeData(Data(text.utf8), path, modified: modified)
    }

    @discardableResult
    func writeData(_ data: Data, _ path: String, modified: Date? = nil) throws -> URL {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    // Markdown plus the sidecar the app would write beside it.
    @discardableResult
    func writePair(_ name: String, markdown text: String? = nil, modified: Date? = nil, in directory: String = "") throws -> URL {
        let text = text ?? markdown(name: name + ".m4a")
        let path = directory.isEmpty ? "\(name).md" : "\(directory)/\(name).md"
        let md = try write(text, path, modified: modified)
        let sidecar = TranscriptSidecar(
            recognition: TimedRecognition(results: [
                RecognitionResult(start: 0, end: 1, units: [
                    RecognitionUnit(text: "Hello", kind: .word, start: 0, end: 0.5),
                    RecognitionUnit(text: " there.", kind: .word, start: 0.5, end: 1),
                ]),
                RecognitionResult(start: 65, end: 66, units: [RecognitionUnit(text: "Second minute.", kind: .word, start: 65, end: 66)]),
            ]),
            transcriber: "SpeechTranscriber", locale: "en-US", duration: 90,
            markdownFileName: md.lastPathComponent, markdown: Data(text.utf8))
        try writeData(try sidecar.encoded(), SidecarFile.url(besides: md).path.replacingOccurrences(of: folder.path + "/", with: ""))
        return md
    }

    // Path -> (SHA-256, modification date) for every item below the folder,
    // directories included; equal snapshots mean nothing was written.
    func snapshot() throws -> [String: String] {
        var result: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey])!
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let hash = values.isDirectory == true ? "dir" :
                SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            result[url.path] = "\(hash) \(values.contentModificationDate!.timeIntervalSinceReferenceDate)"
        }
        return result
    }

    func names(_ items: [LibraryTranscript]) -> [String] {
        items.map { $0.markdownURL.path.replacingOccurrences(of: folder.path + "/", with: "") }
    }
}

final class LibraryScannerTests: TreeTestCase {
    func testFindsOnlyLocalTranscriberTranscriptsAndTheirPackages() throws {
        // Ours: flat, collision-resolved, in a source package.
        try writePair("Talk")
        try writePair("Talk 2")
        let source = video()
        try write(markdown(source: source), "abc123/transcript.md")
        try write("{}", "abc123/transcript.timing.json")
        try write("audio", "abc123/audio.m4a")
        try write("{}", "abc123/source.json")

        // Not ours, or not a transcript.
        try write("# Meeting notes\n\n- buy milk\n", "notes.md")
        try write("# Fake\n\n**Source:** `x.m4a`  \n**Engine:** Something Else\n\n## Transcript\n\n### 00:00:00\n\nhi\n", "other-engine.md")
        try write("# Truncated\n\n**Source:** `x.m4a`  \n**Engine:** Apple SpeechAnalyzer\n", "no-transcript-section.md")
        try write("audio", "Talk.m4a")
        try write(markdown(), ".hidden.md")
        try write(markdown(), ".LocalTranscriber-1234.tmp")
        try write(markdown(), "Talk.txt")
        try write("empty package", "NoTranscript/audio.m4a")
        // LTR-52 (a deliberate change to LTR-44's "one folder level"): a folder that is
        // not an entry is an organization folder and its transcripts are listed, but
        // folders are one level deep: nothing below an entry or a second folder level.
        try write(markdown(), "Nested/loose.md")
        try write(markdown(), "Nested/Deep/transcript.md")
        try write(markdown(), "Nested/Deeper/Deepest/loose.md")
        try write(markdown(), "abc123/Inside/loose.md")

        let items = try LibraryScanner.scan(folder: folder)
        XCTAssertEqual(
            Set(names(items)),
            ["Talk.md", "Talk 2.md", "abc123/transcript.md", "Nested/loose.md", "Nested/Deep/transcript.md"])
        XCTAssertEqual(items.first { $0.markdownURL.path.hasSuffix("abc123/transcript.md") }?.artifactURL.lastPathComponent, "abc123")
        XCTAssertEqual(items.first { $0.title == "Talk" && $0.group == nil && $0.kind == .flat }?.artifactURL.lastPathComponent, "Talk.md")
        XCTAssertEqual(try LibraryScanner.scanLibrary(folder: folder).folders.map(\.name), ["Nested", "NoTranscript"])
    }

    func testReadsTheHeader() throws {
        try write(markdown(name: "Interview.m4a", duration: 3725, locale: "nl-NL", transcriber: .dictationTranscriber), "Interview.md")
        let source = video()
        try write(markdown(duration: nil, source: source), "abc123/transcript.md")

        let items = try LibraryScanner.scan(folder: folder)
        let flat = try XCTUnwrap(items.first { $0.kind == .flat })
        XCTAssertEqual(flat.header, TranscriptHeader(
            title: "Interview", source: "Interview.m4a", channel: nil, published: nil,
            duration: 3725, language: "nl-NL", transcriber: "DictationTranscriber"))
        let package = try XCTUnwrap(items.first { $0.kind == .package })
        XCTAssertEqual(package.header.title, "A video")
        XCTAssertEqual(package.header.source, "https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(package.header.channel, "Chan")
        XCTAssertEqual(package.header.published, "2026-01-02")
        XCTAssertNil(package.header.duration, "no Duration line when the length is unknown")
    }

    func testOrdersNewestSavedFirstAndSettlesTiesByPath() throws {
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try writePair("Old", modified: base)
        try writePair("New", modified: base + 2 * day)
        try writePair("Tie B", modified: base + day)
        try writePair("Tie A", modified: base + day)
        let source = video(id: "vid", title: "V")
        try write(markdown(source: source), "vid/transcript.md", modified: base + 3 * day)

        let first = try LibraryScanner.scan(folder: folder)
        XCTAssertEqual(names(first), ["vid/transcript.md", "New.md", "Tie A.md", "Tie B.md", "Old.md"])
        XCTAssertEqual(first.map(\.savedAt), [base + 3 * day, base + 2 * day, base + day, base + day, base])
        XCTAssertEqual(names(try LibraryScanner.scan(folder: folder)), names(first), "the same folder lists the same way")
    }

    func testToleratesALeadingYamlBlockButNotAnUnclosedOne() throws {
        try write("---\ntags: [a]\n---\n\n" + markdown(), "With Yaml.md")
        try write("---\ntags: [a]\n" + markdown(), "Unclosed.md")
        XCTAssertEqual(names(try LibraryScanner.scan(folder: folder)), ["With Yaml.md"])
    }

    func testSymbolicLinksAreNotFollowed() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data(markdown().utf8).write(to: outside.appendingPathComponent("Elsewhere.md"))
        // A symlinked folder that would be a source package if it were followed.
        try Data(markdown().utf8).write(to: outside.appendingPathComponent("transcript.md"))
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("Link.md"), withDestinationURL: outside.appendingPathComponent("Elsewhere.md"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("LinkedFolder"), withDestinationURL: outside)
        XCTAssertEqual(try LibraryScanner.scan(folder: folder), [])
    }

    func testMalformedDurationsNeverStopTheScanOrHideOtherTranscripts() throws {
        try writePair("Good")
        for (index, value) in ["9223372036854775807:00:00", "99999999999999999999:00:00", "-1:00:00", "x:y:z"].enumerated() {
            let text = markdown(name: "Bad \(index).m4a")
                .replacingOccurrences(of: "**Duration:** 00:01:30", with: "**Duration:** \(value)")
            XCTAssertTrue(text.contains(value))
            try write(text, "Bad \(index).md")
        }
        try write(markdown(source: video()).replacingOccurrences(of: "**Duration:** 00:01:30", with: "**Duration:** 9223372036854775807:00:00"),
                  "pkg/transcript.md")

        let items = try LibraryScanner.scan(folder: folder)
        XCTAssertEqual(Set(names(items)), ["Good.md", "Bad 0.md", "Bad 1.md", "Bad 2.md", "Bad 3.md", "pkg/transcript.md"])
        XCTAssertEqual(items.first { $0.markdownURL.lastPathComponent == "Good.md" }?.header.duration, 90)
        XCTAssertTrue(items.filter { $0.markdownURL.lastPathComponent != "Good.md" }.allSatisfy { $0.header.duration == nil },
                      "the unusable length is dropped; the transcript stays listed and readable")
        for item in items { _ = try TranscriptReview.load(item) }
    }

    func testMissingOrUnreadableFolderThrowsInsteadOfListingAnotherFolder() throws {
        XCTAssertThrowsError(try LibraryScanner.scan(folder: folder.appendingPathComponent("does-not-exist")))
        try writePair("Talk")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        XCTAssertThrowsError(try LibraryScanner.scan(folder: folder))
    }

    func testAnEmptyFolderIsAnEmptyLibrary() throws {
        XCTAssertEqual(try LibraryScanner.scan(folder: folder), [])
    }

    func testRescanSeesFilesAddedRenamedAndRemovedOutsideTheApp() throws {
        let talk = try writePair("Talk")
        XCTAssertEqual(names(try LibraryScanner.scan(folder: folder)), ["Talk.md"])

        try writePair("Added")
        XCTAssertEqual(Set(names(try LibraryScanner.scan(folder: folder))), ["Talk.md", "Added.md"])

        try FileManager.default.moveItem(at: talk, to: folder.appendingPathComponent("Renamed.md"))
        XCTAssertEqual(Set(names(try LibraryScanner.scan(folder: folder))), ["Renamed.md", "Added.md"])

        try FileManager.default.removeItem(at: folder.appendingPathComponent("Added.md"))
        XCTAssertEqual(names(try LibraryScanner.scan(folder: folder)), ["Renamed.md"])
    }

    func testScanningAndReviewingNeverWriteAnything() throws {
        try writePair("Talk")
        try writePair("Tampered")
        try write(markdown() + "\nedited by hand\n", "Tampered.md")
        try writePair("Corrupt")
        try write("{not json", "Corrupt.timing.json")
        try write(markdown(), "Legacy.md")
        try write("# Notes\n", "notes.md")
        try write(markdown(), "pkg/transcript.md")

        let before = try snapshot()
        let items = try LibraryScanner.scan(folder: folder)
        XCTAssertEqual(items.count, 5)
        for item in items { _ = try TranscriptReview.load(item) }
        _ = try LibraryScanner.scan(folder: folder)
        XCTAssertEqual(try snapshot(), before, "same hashes, modification dates and directory contents")
    }

    // Records the time of a scan of about 500 artifacts; the count is the assertion.
    func testScansFiveHundredTranscripts() throws {
        for index in 0..<400 { try writePair(String(format: "Transcript %03d", index)) }
        for index in 0..<100 { try write(markdown(), String(format: "pkg%03d/transcript.md", index)) }
        for index in 0..<50 { try write("# Not ours \(index)\n", "other \(index).md") }

        let clock = ContinuousClock()
        var items: [LibraryTranscript] = []
        let elapsed = try clock.measure { items = try LibraryScanner.scan(folder: folder) }
        print("LIBRARY SCAN: \(items.count) transcripts among 400 pairs + 100 packages + 50 other files in \(elapsed)")
        XCTAssertEqual(items.count, 500)
        XCTAssertEqual(items.filter { $0.kind == .package }.count, 100)
    }
}

final class SidebarSelectionRuleTests: XCTestCase {
    func testADeselectOfTheSelectedRowChangesNothing() {
        // Command-click on the selected row: the List proposes nil.
        XCTAssertEqual(SidebarSelectionRule.next(current: "talk", proposed: nil), "talk")
    }

    func testClickingAnotherRowOrTheSameRowSelectsIt() {
        XCTAssertEqual(SidebarSelectionRule.next(current: "talk", proposed: "other"), "other")
        XCTAssertEqual(SidebarSelectionRule.next(current: "talk", proposed: "talk"), "talk")
        XCTAssertEqual(SidebarSelectionRule.next(current: Optional<String>.none, proposed: "talk"), "talk")
    }
}

// LTR-72: the transcript a window asked for opens once its request settles, and
// never against the user's own navigation.
final class ReviewAutoOpenTests: XCTestCase {
    let a = URL(fileURLWithPath: "/lib/A/A.md"), b = URL(fileURLWithPath: "/lib/B/B.md")

    func testTheLastSavedTranscriptOpensOnceQuietAndListedAndOnlyOnce() {
        var open = ReviewAutoOpen()
        open.languageChosen(); open.saved(a)
        open.languageChosen(); open.saved(b)
        XCTAssertNil(open.transcriptToOpen(isQuiet: false, isListed: { _ in true }))   // still choosing or running
        XCTAssertNil(open.transcriptToOpen(isQuiet: true, isListed: { _ in false }))   // not rescanned yet
        XCTAssertEqual(open.transcriptToOpen(isQuiet: true, isListed: { _ in true }), b)
        XCTAssertNil(open.transcriptToOpen(isQuiet: true, isListed: { _ in true }))
    }

    func testUserNavigationWinsOverACompletion() {
        var open = ReviewAutoOpen()
        open.languageChosen(); open.userNavigated(); open.saved(a)
        XCTAssertNil(open.transcriptToOpen(isQuiet: true, isListed: { _ in true }))
        open.languageChosen(); open.saved(a); open.userNavigated()
        XCTAssertNil(open.transcriptToOpen(isQuiet: true, isListed: { _ in true }))
    }

    func testNothingOpensWithoutARequestOrAfterOnlyFailures() {
        var open = ReviewAutoOpen()
        open.saved(a)            // a job this window did not ask for
        XCTAssertNil(open.transcriptToOpen(isQuiet: true, isListed: { _ in true }))
        open.languageChosen()    // its job failed: nothing was saved
        XCTAssertNil(open.transcriptToOpen(isQuiet: true, isListed: { _ in true }))
    }
}

// LTR-72: the language menu's Recent section.
final class RecentChoicesTests: XCTestCase {
    func testFirstAndRepeatedChoices() {
        XCTAssertEqual(RecentChoices.choosing("English", in: []), ["English"])
        XCTAssertEqual(RecentChoices.choosing("English", in: ["English"]), ["English"])
    }

    func testAnExistingChoiceIsPromotedAndANewOneGoesFirst() {
        XCTAssertEqual(RecentChoices.choosing("Russian", in: ["English", "Dutch", "Russian"]), ["Russian", "English", "Dutch"])
        XCTAssertEqual(RecentChoices.choosing("German", in: ["English", "Dutch"]), ["German", "English", "Dutch"])
    }

    func testFiveAtMostTheLeastRecentDropsOutAndNothingRepeats() {
        let full = ["English", "Dutch", "Russian", "German", "French"]
        let italian = RecentChoices.choosing("Italian", in: full)
        XCTAssertEqual(italian, ["Italian", "English", "Dutch", "Russian", "German"])
        XCTAssertEqual(RecentChoices.choosing("Dutch", in: italian), ["Dutch", "Italian", "English", "Russian", "German"])
        XCTAssertEqual(Set(italian).count, italian.count)
    }
}
