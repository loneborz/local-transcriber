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
        // Only one folder level is read.
        try write(markdown(), "Nested/loose.md")
        try write(markdown(), "Nested/Deep/transcript.md")

        let items = try LibraryScanner.scan(folder: folder)
        XCTAssertEqual(Set(names(items)), ["Talk.md", "Talk 2.md", "abc123/transcript.md"])
        XCTAssertEqual(items.first { $0.kind == .package }?.artifactURL.lastPathComponent, "abc123")
        XCTAssertEqual(items.first { $0.title == "Talk" }?.artifactURL.lastPathComponent, "Talk.md")
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

final class LibraryJoinTests: TreeTestCase {
    func testAJobIsMatchedByTheFileOrPackageFolderItSaved() throws {
        let flat = try writePair("Talk")
        try write(markdown(), "pkg/transcript.md")
        let items = LibraryJoin.index(try LibraryScanner.scan(folder: folder))

        XCTAssertEqual(LibraryJoin.item(forSavedURL: flat, in: items)?.title, "Talk")
        XCTAssertEqual(LibraryJoin.item(forSavedURL: folder.appendingPathComponent("pkg", isDirectory: true), in: items)?.kind, .package)
        XCTAssertEqual(LibraryJoin.item(forSavedURL: folder.appendingPathComponent("pkg"), in: items)?.kind, .package, "with or without a trailing slash")
        XCTAssertEqual(LibraryJoin.item(forSavedURL: folder.appendingPathComponent("./Talk.md"), in: items)?.title, "Talk")
    }

    func testAJobSavedElsewhereOrNotYetListedIsNotJoined() throws {
        try writePair("Talk")
        let items = LibraryJoin.index(try LibraryScanner.scan(folder: folder))
        XCTAssertNil(LibraryJoin.item(forSavedURL: folder.appendingPathComponent("Talk 2.md"), in: items))
        XCTAssertNil(LibraryJoin.item(forSavedURL: URL(fileURLWithPath: "/elsewhere/Talk.md"), in: items))
        XCTAssertNil(LibraryJoin.item(forSavedURL: folder.appendingPathComponent("Talk.md"), in: [:]))
    }
}

extension LibraryJoinTests {
    func testASavedJobWaitsInProgressOnlyForAnEntryInTheFolderBeingListed() throws {
        try writePair("Talk")
        let index = LibraryJoin.index(try LibraryScanner.scan(folder: folder))
        let listed = folder.appendingPathComponent("Talk.md")
        let notYetScanned = folder.appendingPathComponent("New.md")

        XCTAssertFalse(LibraryJoin.isAwaitingEntry(savedURL: listed, folder: folder, in: index), "already a library item")
        XCTAssertTrue(LibraryJoin.isAwaitingEntry(savedURL: notYetScanned, folder: folder, in: index), "saved here, not listed yet")
        XCTAssertFalse(LibraryJoin.isAwaitingEntry(savedURL: URL(fileURLWithPath: "/other/Old.md"), folder: folder, in: index),
                       "saved in another folder: not part of this library")
        XCTAssertFalse(LibraryJoin.isAwaitingEntry(savedURL: folder.deletingLastPathComponent().appendingPathComponent("\(folder.lastPathComponent) copy/New.md"), folder: folder, in: index),
                       "a sibling folder with the same prefix is another folder")
        XCTAssertFalse(LibraryJoin.isAwaitingEntry(savedURL: notYetScanned, folder: nil, in: index), "no usable folder")
    }
}

final class WorkspaceFlowTests: TreeTestCase {
    private func entry(_ batch: Int, _ kind: Kind) -> QueueEntry {
        QueueEntry(id: UUID(), batch: batch, isSettled: kind == .saved, isUnfinished: kind == .running)
    }
    private enum Kind { case saved, running, failed }   // failed: also Complete with a failed save

    private func shown(_ jobs: [QueueEntry], floor: Int) -> [UUID] {
        QueueWorkspace.visible(jobs, firstVisibleBatch: floor)
    }

    func testNewTranscriptionAfterASingleJobCompletedShowsAFreshWorkspace() {
        let done = [entry(1, .saved)]
        let floor = QueueWorkspace.firstVisibleBatch(afterStartingFresh: done)
        XCTAssertEqual(shown(done, floor: floor), [], "nothing from the finished batch")
    }

    func testNewTranscriptionAfterReviewingASavedTranscriptIsFreshToo() {
        // Several finished batches, none running.
        let jobs = [entry(1, .saved), entry(2, .saved), entry(2, .saved)]
        XCTAssertEqual(shown(jobs, floor: QueueWorkspace.firstVisibleBatch(afterStartingFresh: jobs)), [])
    }

    func testANewBatchStartsOwnVisibleWorkAndHidesEarlierSettledBatches() {
        let earlier = [entry(1, .saved), entry(1, .saved)]
        let new = entry(2, .running)
        let floor = QueueWorkspace.firstVisibleBatch(forNewBatch: 2)
        XCTAssertEqual(shown(earlier + [new], floor: floor), [new.id])
    }

    func testAMultiFileBatchKeepsItsResultsWhileItRunsAndUntilTheUserStartsFresh() {
        let batch = [entry(3, .saved), entry(3, .saved), entry(3, .running)]
        // Starting fresh while it is still running does not retire it.
        let floorWhileRunning = QueueWorkspace.firstVisibleBatch(afterStartingFresh: batch)
        XCTAssertEqual(floorWhileRunning, 3)
        XCTAssertEqual(shown(batch, floor: floorWhileRunning), batch.map(\.id))
        // Finished and the user still there: the floor was not moved, results stay.
        let finished = [entry(3, .saved), entry(3, .saved), entry(3, .saved)]
        XCTAssertEqual(shown(finished, floor: 3), finished.map(\.id))
        // Deliberately leaving the context retires it.
        XCTAssertEqual(shown(finished, floor: QueueWorkspace.firstVisibleBatch(afterStartingFresh: finished)), [])
    }

    func testFailedAndSaveFailedJobsStayReachableInAFreshWorkspaceForRetryAndSave() {
        let failed = entry(1, .failed)
        let saved = entry(1, .saved)
        let jobs = [saved, failed]
        let floor = QueueWorkspace.firstVisibleBatch(afterStartingFresh: jobs)
        XCTAssertEqual(shown(jobs, floor: floor), [failed.id], "recoverable work is never hidden, however old")
        XCTAssertEqual(shown(jobs, floor: QueueWorkspace.firstVisibleBatch(forNewBatch: 9)), [failed.id])
    }

    func testHidingIsAWindowNotADeletion() {
        let jobs = [entry(1, .saved), entry(1, .saved), entry(2, .failed)]
        _ = shown(jobs, floor: 5)
        XCTAssertEqual(jobs.count, 3, "the retained queue is a separate value; the window never mutates it")
        XCTAssertEqual(shown(jobs, floor: 0), jobs.map(\.id), "moving the window back shows everything again")
    }

    func testStartingFreshOnAnEmptyQueueIsHarmless() {
        XCTAssertEqual(QueueWorkspace.firstVisibleBatch(afterStartingFresh: []), 1)
        XCTAssertEqual(shown([], floor: 1), [])
    }

    func testOnlyAWholeSingleJobBatchOpensItselfAndNeverOverAnotherTranscript() {
        XCTAssertTrue(AutoOpen.shouldRequest(batchJobCount: 1, userIsReviewingTranscript: false))
        XCTAssertFalse(AutoOpen.shouldRequest(batchJobCount: 2, userIsReviewingTranscript: false), "multi-file batch: no jumping")
        XCTAssertFalse(AutoOpen.shouldRequest(batchJobCount: 5, userIsReviewingTranscript: false))
        XCTAssertFalse(AutoOpen.shouldRequest(batchJobCount: 1, userIsReviewingTranscript: true), "deliberate selection is respected")
    }

    func testThePendingOpenFindsTheFileThatWasActuallyWrittenNotTheOneWithTheSameStem() throws {
        // The same source saved twice: the second Markdown is "Talk 2.md" and has the same title.
        let sameSource = markdown(name: "Talk.m4a")
        let first = try writePair("Talk", markdown: sameSource)
        let second = try writePair("Talk 2", markdown: sameSource)
        let index = LibraryJoin.index(try LibraryScanner.scan(folder: folder))

        guard case .open(let opened) = PendingOpen(savedURL: second).resolve(in: index, userIsReviewingTranscript: false) else {
            return XCTFail("expected the saved file to open")
        }
        XCTAssertEqual(opened.markdownURL.lastPathComponent, "Talk 2.md")
        XCTAssertEqual(opened.title, "Talk")
        XCTAssertEqual(LibraryJoin.item(forSavedURL: first, in: index)?.title, "Talk", "same title: only the URL tells them apart")
    }

    func testThePendingOpenOpensAPackageByItsFolder() throws {
        try write(markdown(), "abc123/transcript.md")
        let index = LibraryJoin.index(try LibraryScanner.scan(folder: folder))
        guard case .open(let opened) = PendingOpen(savedURL: folder.appendingPathComponent("abc123")).resolve(in: index, userIsReviewingTranscript: false) else {
            return XCTFail()
        }
        XCTAssertEqual(opened.kind, .package)
    }

    func testThePendingOpenIsDroppedWhenTheLibraryDoesNotListTheFileOrTheUserTookOver() throws {
        let saved = try writePair("Talk")
        let index = LibraryJoin.index(try LibraryScanner.scan(folder: folder))
        XCTAssertEqual(PendingOpen(savedURL: folder.appendingPathComponent("Missing.md")).resolve(in: index, userIsReviewingTranscript: false), .drop)
        XCTAssertEqual(PendingOpen(savedURL: URL(fileURLWithPath: "/elsewhere/Talk.md")).resolve(in: index, userIsReviewingTranscript: false), .drop)
        XCTAssertEqual(PendingOpen(savedURL: saved).resolve(in: [:], userIsReviewingTranscript: false), .drop, "a scan that did not find it")
        XCTAssertEqual(PendingOpen(savedURL: saved).resolve(in: index, userIsReviewingTranscript: true), .drop)
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
