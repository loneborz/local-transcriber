import CryptoKit
import XCTest
@testable import TranscriptCore

// LTR-48, LTR-51, LTR-52: entry folders, entry.json, and the actions on them.
class ManagedLibraryCase: TreeTestCase {
    let created = Date(timeIntervalSince1970: 1_700_000_000)

    func sha(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    // An entry as the app writes it: folder, Markdown, sidecar, entry.json (and audio).
    @discardableResult
    func makeEntry(_ name: String, in directory: String = "", created: Date? = nil, pinned: Bool = false,
                   archived: Bool = false, audio: Bool = false) throws -> URL {
        let path = directory.isEmpty ? name : "\(directory)/\(name)"
        let md = try writePair(name, in: path)
        let folder = md.deletingLastPathComponent()
        try EntryMetadata.create(EntryMetadata(createdAt: created ?? self.created, pinned: pinned, archived: archived), folder)
        if audio { try write("audio", "\(path)/audio.m4a") }
        return md
    }

    func scan() throws -> LibraryListing { try LibraryScanner.scanLibrary(folder: folder) }

    func entry(_ title: String) throws -> LibraryTranscript {
        try XCTUnwrap(scan().items.first { $0.title == title }, "no entry \(title)")
    }
}

final class EntryMetadataTests: ManagedLibraryCase {
    func testRoundTripAndDeterministicEncoding() throws {
        let metadata = EntryMetadata(createdAt: created, pinned: true, archived: false)
        let data = try metadata.encoded()
        XCTAssertEqual(EntryMetadata.decode(data), .valid(metadata))
        XCTAssertEqual(try metadata.encoded(), data)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"pinned\" : true"))
        XCTAssertFalse(text.contains("archived"), "false is omitted")
        XCTAssertTrue(text.contains("2023-11-14T22:13:20Z"), "ISO 8601, UTC")
    }

    func testCreationTimeIsOptionalAndNeverInvented() throws {
        let data = Data(#"{"schemaVersion":1}"#.utf8)
        XCTAssertEqual(EntryMetadata.decode(data), .valid(EntryMetadata(createdAt: nil)))
    }

    func testMalformedUnsupportedAndOversizedFilesAreReportedNotTrusted() throws {
        XCTAssertEqual(EntryMetadata.decode(Data("not json".utf8)), .unreadable)
        XCTAssertEqual(EntryMetadata.decode(Data(#"{"schemaVersion":1,"pinned":"yes"}"#.utf8)), .unreadable)
        XCTAssertEqual(EntryMetadata.decode(Data(#"{"schemaVersion":2,"future":true}"#.utf8)), .unsupported(2))

        let dir = folder.appendingPathComponent("E", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        XCTAssertEqual(EntryMetadata.read(in: dir), .missing)
        try Data(count: EntryMetadata.maxBytes + 1).write(to: dir.appendingPathComponent("entry.json"))
        XCTAssertEqual(EntryMetadata.read(in: dir), .unreadable)
    }

    func testUpdateNeverReplacesAFileItCannotRead() throws {
        for (index, text) in ["garbage", #"{"schemaVersion":9}"#].enumerated() {
            let dir = folder.appendingPathComponent("E\(index)", isDirectory: true)
            let file = try write(text, "E\(index)/entry.json")
            XCTAssertThrowsError(try EntryMetadata.update(in: dir) { $0.pinned = true })
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), text)
        }
    }

    func testUpdateCreatesAMissingFileWithoutAnInventedDate() throws {
        let dir = folder.appendingPathComponent("E", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        try EntryMetadata.update(in: dir) { $0.archived = true }
        XCTAssertEqual(EntryMetadata.read(in: dir), .valid(EntryMetadata(createdAt: nil, archived: true)))
    }
}

final class EntryNameTests: XCTestCase {
    func testSanitizedNamesAreAlwaysSafeFileNames() {
        XCTAssertEqual(EntryName.sanitized("Weekly Meeting"), "Weekly Meeting")
        XCTAssertEqual(EntryName.sanitized("a/b:c"), "a-b-c")
        XCTAssertFalse(EntryName.sanitized("../../etc").contains("/"))
        XCTAssertFalse(EntryName.sanitized("../../etc").hasPrefix("."))
        XCTAssertEqual(EntryName.sanitized("..."), "Untitled")
        XCTAssertEqual(EntryName.sanitized("   "), "Untitled")
        XCTAssertEqual(EntryName.sanitized(".hidden"), "hidden")
        XCTAssertEqual(EntryName.sanitized("tab\there\nnew\u{0}nul"), "tab here new nul")
        let long = EntryName.sanitized(String(repeating: "é", count: 300))
        XCTAssertLessThanOrEqual(long.utf8.count, EntryName.maxBytes)
        XCTAssertFalse(EntryName.sanitized("x/../y").contains("/"))
    }

    func testTypedNamesAreAcceptedOrRefusedWithAReason() throws {
        XCTAssertEqual(try EntryName.validated("  Research  ").get(), "Research")
        for bad in ["", "   ", ".x", "a/b", "a:b", "..", "a\u{0}b", String(repeating: "x", count: 200)] {
            XCTAssertThrowsError(try EntryName.validated(bad).get(), bad) { error in
                guard case LibraryError.invalidName = error else { return XCTFail("\(error)") }
            }
        }
    }
}

final class EntryWriteTests: ManagedLibraryCase {
    func testAnEntryIsAFolderWithRecognizableNamesAndTheExactMarkdown() throws {
        let text = markdown(name: "Weekly Meeting.m4a")
        let written = try LibraryOperations.writeEntry(
            baseName: "Weekly Meeting", in: folder, markdown: text, createdAt: created)
        XCTAssertEqual(written.folder.lastPathComponent, "Weekly Meeting")
        XCTAssertEqual(written.markdown.lastPathComponent, "Weekly Meeting.md")
        XCTAssertEqual(try String(contentsOf: written.markdown, encoding: .utf8), text, "byte-identical Markdown")
        XCTAssertNil(written.metadataWarning)
        XCTAssertEqual(EntryMetadata.read(in: written.folder), .valid(EntryMetadata(createdAt: created, unopened: true)))

        let item = try entry("Weekly Meeting")
        XCTAssertEqual(item.kind, .entry)
        XCTAssertEqual(item.createdAt, created)
    }

    func testCollisionsGetNumbersAndNeverOverwriteAnything() throws {
        let first = try LibraryOperations.writeEntry(baseName: "Talk", in: folder, markdown: markdown(), createdAt: created)
        let before = try sha(first.markdown)
        let second = try LibraryOperations.writeEntry(baseName: "Talk", in: folder, markdown: markdown(seconds: [(0, "Other")]), createdAt: created)
        let third = try LibraryOperations.writeEntry(baseName: "Talk", in: folder, markdown: markdown(), createdAt: created)
        XCTAssertEqual([first, second, third].map(\.markdown.lastPathComponent), ["Talk.md", "Talk 2.md", "Talk 3.md"])
        XCTAssertEqual(second.folder.lastPathComponent, "Talk 2", "folder and Markdown stay consistent")
        XCTAssertEqual(try sha(first.markdown), before)
    }

    func testAnUnrelatedFileWithTheNameIsNotReused() throws {
        let other = try write("mine", "Talk")
        let written = try LibraryOperations.writeEntry(baseName: "Talk", in: folder, markdown: markdown(), createdAt: created)
        XCTAssertEqual(written.folder.lastPathComponent, "Talk 2")
        XCTAssertEqual(try String(contentsOf: other, encoding: .utf8), "mine")
    }

    func testHostileNamesStayInsideTheParent() throws {
        let written = try LibraryOperations.writeEntry(baseName: "../../escape", in: folder, markdown: markdown(), createdAt: created)
        XCTAssertEqual(written.folder.deletingLastPathComponent().standardizedFileURL.path, folder.standardizedFileURL.path)
    }

    func testASourcePackageKeepsItsAudioAndManifestInTheSameFolder() throws {
        let audio = try write("audio bytes", "tmp/Title [abc].m4a")
        let written = try LibraryOperations.writeEntry(
            baseName: "A video", in: folder, markdown: markdown(source: video()), createdAt: created,
            audio: audio, manifest: Data("{}".utf8))
        XCTAssertEqual(try String(contentsOf: written.folder.appendingPathComponent("audio.m4a"), encoding: .utf8), "audio bytes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.folder.appendingPathComponent("source.json").path))
        let item = try entry("A video")
        XCTAssertEqual(AudioResolution.candidateURL(for: item)?.lastPathComponent, "audio.m4a")
    }

    func testAFailureBeforeTheMarkdownLeavesNoHalfWrittenFolder() throws {
        let missing = folder.appendingPathComponent("nope.m4a")
        XCTAssertThrowsError(try LibraryOperations.writeEntry(
            baseName: "Broken", in: folder, markdown: markdown(), createdAt: created, audio: missing, manifest: nil))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    func testAMetadataFailureNeverLosesTheTranscriptAndIsReported() throws {
        struct Boom: Error {}
        let written = try LibraryOperations.writeEntry(
            baseName: "Talk", in: folder, markdown: markdown(), createdAt: created, writeMetadata: { _, _ in throw Boom() })
        XCTAssertNotNil(written.metadataWarning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.markdown.path))
        let item = try entry("Talk")
        XCTAssertNil(item.createdAt)
        XCTAssertEqual(item.metadata, .missing)
        XCTAssertEqual(item.sortDate, item.savedAt, "falls back to the save date, which is shown as saved")
        // Recoverable: the next action creates the file.
        let pinned = try LibraryOperations.setPinned(item, true)
        XCTAssertTrue(pinned.isPinned)
    }

    func testARecordingIsAnEntryWithItsAudioAndLaterItsTranscript() throws {
        let staged = try write("recorded", "staging/recording.m4a")
        let audio = try LibraryOperations.saveRecording(staged, baseName: "Recording 2026-10-16 10.00.00 (Mic)", in: folder, startedAt: created)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        let entryFolder = audio.deletingLastPathComponent()
        XCTAssertEqual(entryFolder.lastPathComponent, "Recording 2026-10-16 10.00.00 (Mic)")
        XCTAssertEqual(audio.lastPathComponent, "Recording 2026-10-16 10.00.00 (Mic).m4a")
        XCTAssertEqual(EntryMetadata.read(in: entryFolder), .valid(EntryMetadata(createdAt: created)))
        XCTAssertEqual(try scan().items, [], "an entry still being transcribed is not listed")
        XCTAssertEqual(try scan().folders.map(\.name), ["staging"], "the recording folder is not an organization folder")

        let written = try LibraryOperations.writeEntry(
            baseName: "ignored", in: folder, existingFolder: entryFolder,
            markdown: markdown(name: audio.lastPathComponent), createdAt: Date())
        XCTAssertEqual(written.folder, entryFolder)
        let item = try XCTUnwrap(scan().items.first)
        XCTAssertEqual(item.createdAt, created, "the recording start, not the save")
        XCTAssertEqual(AudioResolution.candidateURL(for: item), audio)
    }

    func testARecordingThatCannotBeFiledKeepsTheStagedFile() throws {
        let staged = try write("recorded", "staging/recording.m4a")
        let missingParent = folder.appendingPathComponent("gone", isDirectory: true)
        XCTAssertThrowsError(try LibraryOperations.saveRecording(staged, baseName: "R", in: missingParent, startedAt: created))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
    }
}

final class ManagedScanTests: ManagedLibraryCase {
    func testEntriesFoldersAndLegacyTranscriptsAreListedTogether() throws {
        try makeEntry("New One")
        try writePair("Legacy Flat")
        try write(markdown(source: video()), "abc123/transcript.md")
        try makeEntry("In Meetings", in: "Meetings")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Empty"), withIntermediateDirectories: false)

        let listing = try scan()
        XCTAssertEqual(Set(names(listing.items)), [
            "New One/New One.md", "Legacy Flat.md", "abc123/transcript.md", "Meetings/In Meetings/In Meetings.md"])
        XCTAssertEqual(listing.folders.map(\.name), ["Empty", "Meetings"], "empty folders are listed")
        XCTAssertEqual(listing.items.filter(\.isManaged).count, 2)
        XCTAssertEqual(try entry("In Meetings").group?.lastPathComponent, "Meetings")
    }

    func testAFolderHoldingBothKindsIsAnEntryAndItsSubfoldersAreNotRead() throws {
        try makeEntry("Mixed")
        try writePair("Inside", in: "Mixed/Inside")
        let listing = try scan()
        XCTAssertEqual(names(listing.items), ["Mixed/Mixed.md"])
        XCTAssertEqual(listing.folders, [])
    }

    func testAnOrganizationFolderWithLegacyAndNewEntriesKeepsBoth() throws {
        try makeEntry("New", in: "Both")
        try writePair("Old", in: "Both")
        XCTAssertEqual(Set(names(try scan().items)), ["Both/New/New.md", "Both/Old.md"])
    }

    func testFoldersAreOneLevelDeepAndEntriesAreNotSearchedForBelowThem() throws {
        try makeEntry("Deep", in: "A/B")
        try makeEntry("Shallow", in: "A")
        let listing = try scan()
        XCTAssertEqual(names(listing.items), ["A/Shallow/Shallow.md"])
        XCTAssertEqual(listing.folders.map(\.name), ["A"])
    }

    func testAFinderRenamedEntryFolderIsStillAnEntryNamedByItsFolder() throws {
        try makeEntry("Old Name")
        try FileManager.default.moveItem(at: folder.appendingPathComponent("Old Name"), to: folder.appendingPathComponent("New Name"))
        let item = try XCTUnwrap(scan().items.first)
        XCTAssertEqual(item.title, "New Name")
        XCTAssertEqual(item.markdownURL.lastPathComponent, "Old Name.md")
        XCTAssertEqual(item.createdAt, created, "entry.json travels with the folder")
        XCTAssertEqual(item.sidecarURL.lastPathComponent, "Old Name.timing.json")
    }

    func testAnEntryWithoutAValidEntryJsonIsStillListedAndReadable() throws {
        let cases: [(String, String?)] = [("Missing", nil), ("Malformed", "{ nope"), ("Future", #"{"schemaVersion":7}"#)]
        for (name, text) in cases {
            try writePair(name, in: name)
            if let text { try write(text, "\(name)/entry.json") }
        }
        let items = try scan().items
        XCTAssertEqual(Set(items.map(\.title)), ["Missing", "Malformed", "Future"])
        XCTAssertEqual(try entry("Malformed").metadata, .unreadable)
        XCTAssertEqual(try entry("Future").metadata, .unsupported(7))
        XCTAssertEqual(try entry("Missing").metadata, .missing)
        XCTAssertTrue(items.allSatisfy { $0.createdAt == nil && !$0.isPinned && !$0.isArchived })
        // Actions on the unreadable ones are refused and leave the file as it was.
        XCTAssertThrowsError(try LibraryOperations.setPinned(try entry("Malformed"), true))
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("Malformed/entry.json"), encoding: .utf8), "{ nope")
    }

    func testAFolderWithOnlyEntryJsonIsIncompleteAndHidden() throws {
        try EntryMetadata.create(EntryMetadata(createdAt: created), try makeFolder("Half"))
        let listing = try scan()
        XCTAssertEqual(listing.items, [])
        XCTAssertEqual(listing.folders, [])
    }

    // LTR-72: a recording left waiting for its language (for example at quit) is found
    // again, at the top level and in an organization folder, oldest first.
    func testASavedRecordingWithoutATranscriptIsListedAsUntranscribed() throws {
        let top = try makeFolder("Recording A")
        try EntryMetadata.create(EntryMetadata(createdAt: created.addingTimeInterval(60)), top)
        try write("audio", "Recording A/Recording A.m4a")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Work/Recording B"), withIntermediateDirectories: true)
        try EntryMetadata.create(EntryMetadata(createdAt: created), folder.appendingPathComponent("Work/Recording B"))
        try write("audio", "Work/Recording B/Recording B.m4a")
        try EntryMetadata.create(EntryMetadata(createdAt: created), try makeFolder("Half"))    // no audio of its name
        let listing = try scan()
        XCTAssertEqual(listing.items, [])
        XCTAssertEqual(listing.untranscribed.map(\.audio.lastPathComponent), ["Recording B.m4a", "Recording A.m4a"])
        XCTAssertEqual(listing.untranscribed.map(\.folder.lastPathComponent), ["Recording B", "Recording A"])
        XCTAssertEqual(listing.untranscribed.map(\.createdAt), [created, created.addingTimeInterval(60)])

        // Its transcript goes into that folder; then it is an entry, not untranscribed.
        try LibraryOperations.writeEntry(baseName: "ignored", in: folder, existingFolder: top, markdown: markdown(), createdAt: created)
        let after = try scan()
        XCTAssertEqual(after.items.map(\.markdownURL.lastPathComponent), ["Recording A.md"])
        XCTAssertEqual(after.untranscribed.map(\.folder.lastPathComponent), ["Recording B"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: top.appendingPathComponent("Recording A.m4a").path))
    }

    func testSymbolicLinksAreNeverFollowedInsideFoldersEither() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data(markdown().utf8).write(to: outside.appendingPathComponent("transcript.md"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Org"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Org/Linked"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("TopLink"), withDestinationURL: outside)
        let listing = try scan()
        XCTAssertEqual(listing.items, [])
        XCTAssertEqual(listing.folders.map(\.name), ["Org"])
    }

    func testOrderIsNewestFirstByCreationTimeThenSaveDateAndPinnedAndArchivedAreSeparate() throws {
        try makeEntry("Old", created: Date(timeIntervalSince1970: 1_000))
        try makeEntry("New", created: Date(timeIntervalSince1970: 3_000))
        try makeEntry("Mid", created: Date(timeIntervalSince1970: 2_000), pinned: true)
        try makeEntry("Pinned Old", created: Date(timeIntervalSince1970: 500), pinned: true)
        try makeEntry("Gone", archived: true)
        try makeEntry("Gone Pinned", pinned: true, archived: true)
        try makeEntry("Filed", in: "Work", created: Date(timeIntervalSince1970: 4_000))
        try makeEntry("Filed Pinned", in: "Work", pinned: true)

        let sections = LibrarySections(try scan())
        XCTAssertEqual(sections.pinned.map(\.title), ["Filed Pinned", "Mid", "Pinned Old"], "pinned first, newest first, across folders")
        XCTAssertEqual(sections.recent.map(\.title), ["New", "Old"], "pinned and archived entries are not Recent")
        XCTAssertEqual(sections.folders.map(\.folder.name), ["Work"])
        XCTAssertEqual(sections.folders[0].entries.map(\.title), ["Filed Pinned", "Filed"], "a pinned entry is also listed in its folder")
        XCTAssertEqual(Set(sections.archived.map(\.title)), ["Gone", "Gone Pinned"], "archived wins over pinned; one place only")
    }

    func testAnEntryWithoutACreationTimeSortsByItsSaveDate() throws {
        try writePair("Saved Late", modified: Date(timeIntervalSince1970: 9_000), in: "Saved Late")
        try makeEntry("Created", created: Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(try scan().items.map(\.title), ["Saved Late", "Created"])
    }

    func testScanningWritesNothingAndLegacyFilesAreUntouched() throws {
        try writePair("Legacy")
        try write(markdown(source: video()), "pkg/transcript.md")
        try makeEntry("New", in: "F")
        let before = try snapshot()
        _ = try scan()
        XCTAssertEqual(try snapshot(), before)
    }

    func testScanTimeOnALargeNestedLibrary() throws {
        for f in 0..<20 {
            for e in 0..<100 { try makeEntry(String(format: "Entry %03d", e), in: String(format: "Folder %02d", f)) }
        }
        for e in 0..<300 { try makeEntry(String(format: "Loose %03d", e)) }
        for e in 0..<200 { try writePair(String(format: "Legacy %03d", e)) }

        var listing = LibraryListing()
        let elapsed = try ContinuousClock().measure { listing = try scan() }
        print("MANAGED SCAN: \(listing.items.count) transcripts in \(listing.folders.count) folders in \(elapsed)")
        XCTAssertEqual(listing.items.count, 2_000 + 300 + 200)
        XCTAssertEqual(listing.folders.count, 20)
    }

    private func makeFolder(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

final class LibraryActionTests: ManagedLibraryCase {
    func testRenameChangesOnlyNamesAndKeepsEveryByte() throws {
        let md = try makeEntry("Old", audio: true)
        let folderURL = md.deletingLastPathComponent()
        let mdHash = try sha(md), sidecarHash = try sha(SidecarFile.url(besides: md)), metaHash = try sha(folderURL.appendingPathComponent("entry.json"))

        let renamed = try LibraryOperations.rename(try entry("Old"), to: "  Weekly Meeting ")
        let newFolder = folder.appendingPathComponent("Weekly Meeting")
        XCTAssertEqual(renamed.markdownURL, newFolder.appendingPathComponent("Weekly Meeting.md"))
        XCTAssertEqual(try sha(renamed.markdownURL), mdHash, "Markdown is never rewritten")
        XCTAssertEqual(try sha(renamed.sidecarURL), sidecarHash, "sidecar is never rewritten")
        XCTAssertEqual(try sha(newFolder.appendingPathComponent("entry.json")), metaHash, "creation time unchanged")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: newFolder.path).sorted(),
                       ["Weekly Meeting.md", "Weekly Meeting.timing.json", "audio.m4a", "entry.json"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folderURL.path))

        let listed = try entry("Weekly Meeting")
        XCTAssertEqual(listed.createdAt, created)
        XCTAssertNotNil(SidecarReadback.decodes(listed.sidecarURL), "the sidecar still decodes")
    }

    func testRenameRefusesInvalidAndTakenNamesAndChangesNothing() throws {
        try makeEntry("A"); try makeEntry("B")
        let before = try snapshot()
        let a = try entry("A")
        for bad in ["", "a/b", "x:y", ".dot"] {
            XCTAssertThrowsError(try LibraryOperations.rename(a, to: bad), bad)
        }
        XCTAssertThrowsError(try LibraryOperations.rename(a, to: "B")) { XCTAssertEqual($0 as? LibraryError, .nameTaken("B")) }
        XCTAssertEqual(try snapshot(), before)
    }

    func testRenameRefusesWhenAFileInsideWouldCollide() throws {
        let md = try makeEntry("A")
        try write("other", "A/B.md")
        let before = try snapshot()
        XCTAssertThrowsError(try LibraryOperations.rename(try entry("A"), to: "B")) { XCTAssertEqual($0 as? LibraryError, .nameTaken("B.md")) }
        XCTAssertEqual(try snapshot(), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: md.path))
    }

    func testRenameCanOnlyChangeTheCaseOfAName() throws {
        try makeEntry("talk")
        let renamed = try LibraryOperations.rename(try entry("talk"), to: "Talk")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Talk"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: renamed.entryFolderURL.path).sorted(),
                       ["Talk.md", "Talk.timing.json", "entry.json"])
    }

    func testRenameRepairsAFolderThatWasRenamedInFinder() throws {
        try makeEntry("Old")
        try FileManager.default.moveItem(at: folder.appendingPathComponent("Old"), to: folder.appendingPathComponent("Finder Name"))
        let renamed = try LibraryOperations.rename(try entry("Finder Name"), to: "Finder Name")
        XCTAssertEqual(renamed.markdownURL.lastPathComponent, "Finder Name.md")
        XCTAssertEqual(renamed.sidecarURL.lastPathComponent, "Finder Name.timing.json")
    }

    func testARenameThatFailsPartwayIsRolledBack() throws {
        let sub = try { () -> URL in
            let md = try makeEntry("Inner", in: "Group")
            return md.deletingLastPathComponent().deletingLastPathComponent()
        }()
        func names() throws -> [String: String] { try snapshot().filter { !$0.value.hasPrefix("dir") }.mapValues { String($0.split(separator: " ")[0]) } }
        let before = try names()
        let item = try entry("Inner")
        // The folder itself cannot be renamed when its parent is not writable.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sub.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sub.path) }
        XCTAssertThrowsError(try LibraryOperations.rename(item, to: "Renamed"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sub.path)
        XCTAssertEqual(try names(), before, "the Markdown and sidecar names went back")
    }

    func testPinAndArchivePersistAndOnlyTouchEntryJson() throws {
        let md = try makeEntry("Talk")
        let mdHash = try sha(md)
        var item = try entry("Talk")
        item = try LibraryOperations.setPinned(item, true)
        item = try LibraryOperations.setArchived(item, true)
        XCTAssertTrue(item.isPinned && item.isArchived)

        let reread = try entry("Talk")
        XCTAssertTrue(reread.isPinned && reread.isArchived)
        XCTAssertEqual(reread.createdAt, created)
        XCTAssertEqual(try sha(md), mdHash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: md.path), "archive moves no file")

        item = try LibraryOperations.setArchived(reread, false)
        item = try LibraryOperations.setPinned(item, false)
        XCTAssertFalse(try entry("Talk").isPinned || entry("Talk").isArchived)
    }

    func testMovingAnEntryMovesTheWholeFolderUnchanged() throws {
        let md = try makeEntry("Talk", audio: true)
        let hashes = try ["Talk.md", "Talk.timing.json", "entry.json", "audio.m4a"].map { try sha(md.deletingLastPathComponent().appendingPathComponent($0)) }
        let work = try LibraryOperations.createOrganizationFolder(named: "Work", in: folder)

        let moved = try LibraryOperations.move(try entry("Talk"), to: work.url, root: folder)
        XCTAssertEqual(moved.group, work.url)
        let newFolder = work.url.appendingPathComponent("Talk")
        XCTAssertEqual(try ["Talk.md", "Talk.timing.json", "entry.json", "audio.m4a"].map { try sha(newFolder.appendingPathComponent($0)) }, hashes)
        XCTAssertEqual(try entry("Talk").group?.lastPathComponent, "Work")
        XCTAssertEqual(try entry("Talk").createdAt, created)

        let back = try LibraryOperations.move(try entry("Talk"), to: folder, root: folder)
        XCTAssertNil(back.group)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(), ["Talk", "Work"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.url.path), [])
    }

    func testMovingKeepsPinnedArchivedAndNewStateAndNoOpsInsideTheSameFolder() throws {
        let talk = try makeEntry("Talk"); try makeEntry("Other", in: "Work")
        try EntryMetadata(createdAt: created, unopened: true).encoded()
            .write(to: talk.deletingLastPathComponent().appendingPathComponent("entry.json"))
        let work = try XCTUnwrap(scan().folders.first)
        _ = try LibraryOperations.setPinned(try entry("Talk"), true)
        _ = try LibraryOperations.setArchived(try entry("Talk"), true)
        let before = try entry("Talk")
        XCTAssertTrue(before.isNew)

        let moved = try LibraryOperations.move(before, to: work.url, root: folder)
        let after = try entry("Talk")
        XCTAssertEqual(after.group, work.url)
        XCTAssertTrue(after.isPinned && after.isArchived && after.isNew)
        XCTAssertEqual(after.metadata, before.metadata)

        // Dropping on the folder it is already in changes nothing on disk.
        let snap = try snapshot()
        XCTAssertEqual(try LibraryOperations.move(moved, to: work.url, root: folder), moved)
        XCTAssertEqual(try snapshot(), snap)
    }

    // /tmp is a symlink to /private/tmp. An id built with standardizedFileURL lost the
    // /private prefix only while the file existed, so a moved entry's old id differed
    // from the id it had before the move and the open selection could not follow it.
    func testEntryIdsDoNotChangeWhenTheFileIsGoneInASymlinkedLocation() throws {
        let root = URL(fileURLWithPath: "/private/tmp/ltr-id-\(UUID().uuidString)")
        let work = root.appendingPathComponent("Work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let entryFolder = root.appendingPathComponent("Talk")
        try FileManager.default.createDirectory(at: entryFolder, withIntermediateDirectories: true)
        try markdown(name: "Talk.m4a").write(to: entryFolder.appendingPathComponent("Talk.md"), atomically: true, encoding: .utf8)
        try EntryMetadata.create(EntryMetadata(createdAt: created), entryFolder)

        let before = try XCTUnwrap(LibraryScanner.scanLibrary(folder: root).items.first)
        let moved = try LibraryOperations.move(before, to: work, root: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: before.markdownURL.path))
        XCTAssertEqual(before.id, try XCTUnwrap(LibraryScanner.scanLibrary(folder: root).items.first { $0.group != nil }).id.replacingOccurrences(of: "/Work", with: ""))
        XCTAssertEqual(moved.id, try XCTUnwrap(LibraryScanner.scanLibrary(folder: root).items.first).id)
        XCTAssertEqual(URL(fileURLWithPath: "/private/tmp/x").libraryKey, "/tmp/x")
        XCTAssertEqual(URL(fileURLWithPath: "/private/other/x").libraryKey, "/private/other/x")
        XCTAssertEqual(URL(fileURLWithPath: "/private/var/folders/x").libraryKey, "/var/folders/x")
        XCTAssertEqual(URL(fileURLWithPath: "/private/etc").libraryKey, "/etc")
        // Only the three macOS aliases: a longer name or another directory below /private stays distinct.
        XCTAssertEqual(URL(fileURLWithPath: "/private/tmpfoo/x").libraryKey, "/private/tmpfoo/x")
        XCTAssertEqual(URL(fileURLWithPath: "/private/varnish").libraryKey, "/private/varnish")
        XCTAssertNotEqual(URL(fileURLWithPath: "/private/other/x").libraryKey, URL(fileURLWithPath: "/other/x").libraryKey)
    }

    func testMovingRefusesTakenNamesAndDestinationsOutsideTheLibrary() throws {
        try makeEntry("Talk"); try makeEntry("Talk", in: "Work")
        let before = try snapshot()
        let loose = try XCTUnwrap(scan().items.first { $0.group == nil })
        XCTAssertThrowsError(try LibraryOperations.move(loose, to: folder.appendingPathComponent("Work"), root: folder)) {
            XCTAssertEqual($0 as? LibraryError, .nameTaken("Talk"))
        }
        let nested = folder.appendingPathComponent("Work/Talk")
        XCTAssertThrowsError(try LibraryOperations.move(loose, to: nested, root: folder)) { XCTAssertEqual($0 as? LibraryError, .outsideLibrary) }
        XCTAssertThrowsError(try LibraryOperations.move(loose, to: folder.deletingLastPathComponent(), root: folder))
        XCTAssertThrowsError(try LibraryOperations.move(loose, to: folder.appendingPathComponent("Missing"), root: folder))
        XCTAssertEqual(try snapshot(), before)
    }

    func testOrganizationFoldersAreRealFoldersWithCheckedNames() throws {
        let made = try LibraryOperations.createOrganizationFolder(named: " Meetings ", in: folder)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Meetings").path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(try scan().folders, [made])
        XCTAssertThrowsError(try LibraryOperations.createOrganizationFolder(named: "meetings", in: folder), "case-insensitive duplicate")
        XCTAssertThrowsError(try LibraryOperations.createOrganizationFolder(named: "a/b", in: folder))
        XCTAssertThrowsError(try LibraryOperations.createOrganizationFolder(named: "", in: folder))
    }

    func testTrashMovesTheWholeEntryAndNeverFallsBackToDeleting() throws {
        let md = try makeEntry("Talk", audio: true)
        let item = try entry("Talk")
        XCTAssertEqual(LibraryOperations.contents(of: item).map(\.name), ["audio.m4a", "entry.json", "Talk.md", "Talk.timing.json"])

        var trashed: [URL] = []
        struct Refused: Error {}
        XCTAssertThrowsError(try LibraryOperations.trash(item) { _ in throw Refused() })
        XCTAssertTrue(FileManager.default.fileExists(atPath: md.path), "a failed Trash move deletes nothing")

        try LibraryOperations.trash(item) { trashed.append($0) }
        XCTAssertEqual(trashed, [md.deletingLastPathComponent()], "the entry folder, not just the Markdown")
    }

    func testLegacyEntriesAreReadOnlyAndNothingChangesWhenAnActionIsTried() throws {
        try writePair("Legacy")
        try write(markdown(source: video()), "pkg/transcript.md")
        let before = try snapshot()
        for item in try scan().items {
            XCTAssertFalse(item.isManaged)
            XCTAssertThrowsError(try LibraryOperations.rename(item, to: "X")) { XCTAssertEqual($0 as? LibraryError, .notManaged) }
            XCTAssertThrowsError(try LibraryOperations.setPinned(item, true))
            XCTAssertThrowsError(try LibraryOperations.setArchived(item, true))
            XCTAssertThrowsError(try LibraryOperations.move(item, to: folder, root: folder))
            XCTAssertThrowsError(try LibraryOperations.trash(item) { _ in XCTFail("must not trash") })
        }
        XCTAssertEqual(try snapshot(), before)
    }
}

private enum SidecarReadback {
    static func decodes(_ url: URL) -> TranscriptSidecar? {
        (try? Data(contentsOf: url)).flatMap { try? TranscriptSidecar.decode($0) }
    }
}

// Fixes for the independent review (Codex, 2026-10-16).
final class ReviewFixTests: ManagedLibraryCase {
    func testAnOrganizationFolderHoldingALegacyTranscriptOfItsOwnNameStaysAFolder() throws {
        try writePair("Work", in: "Work")
        try writePair("Other", in: "Work")
        let listing = try scan()
        XCTAssertEqual(listing.folders.map(\.name), ["Work"])
        XCTAssertEqual(Set(names(listing.items)), ["Work/Work.md", "Work/Other.md"])
        XCTAssertTrue(listing.items.allSatisfy { !$0.isManaged })
    }

    func testASoleMarkdownOfTheFoldersNameStillListsWhenEntryJsonIsMissing() throws {
        try writePair("Solo", in: "Solo")
        XCTAssertEqual(try scan().items.map(\.kind), [.entry])
    }

    func testAnActionOnAStaleSnapshotNeverTouchesWhateverIsAtThePathNow() throws {
        try makeEntry("A")
        let stale = try entry("A")
        try FileManager.default.moveItem(at: folder.appendingPathComponent("A"), to: folder.appendingPathComponent("Moved"))
        try write("unrelated", "A/notes.txt")
        XCTAssertThrowsError(try LibraryOperations.trash(stale) { _ in XCTFail("must not trash") })
        XCTAssertThrowsError(try LibraryOperations.rename(stale, to: "X"))
        XCTAssertThrowsError(try LibraryOperations.setPinned(stale, true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("A/notes.txt").path))
    }

    func testNamesThatMacOSTreatsAsPackagesAreRefusedOrDefused() throws {
        XCTAssertThrowsError(try EntryName.validated("Interview.app").get())
        XCTAssertThrowsError(try EntryName.validated("Research.bundle").get())
        XCTAssertEqual(try EntryName.validated("Notes v1.2").get(), "Notes v1.2")
        XCTAssertEqual(EntryName.sanitized("Interview.app"), "Interview-app")
        let written = try LibraryOperations.writeEntry(baseName: "Talk.app", in: folder, markdown: markdown(), createdAt: created)
        XCTAssertEqual(try scan().items.map(\.markdownURL), [written.markdown])
    }
}


// The folder actions of the UI pass (LTR-57).
final class FolderActionTests: ManagedLibraryCase {
    func testRenameKeepsEveryTranscriptAndByte() throws {
        let md = try makeEntry("Talk", in: "Old")
        let hash = try sha(md)
        let renamed = try LibraryOperations.renameFolder(LibraryFolder(url: folder.appendingPathComponent("Old")), to: " New ")
        XCTAssertEqual(renamed.name, "New")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Old").path))
        let item = try entry("Talk")
        XCTAssertEqual(item.group?.lastPathComponent, "New")
        XCTAssertEqual(try sha(item.markdownURL), hash)
        XCTAssertEqual(item.createdAt, created)
    }

    func testRenameRefusesTakenInvalidAndPackageNamesWithoutChangingAnything() throws {
        try makeEntry("A", in: "One"); try makeEntry("B", in: "Two")
        let before = try snapshot()
        let one = LibraryFolder(url: folder.appendingPathComponent("One"))
        XCTAssertThrowsError(try LibraryOperations.renameFolder(one, to: "Two")) { XCTAssertEqual($0 as? LibraryError, .nameTaken("Two")) }
        XCTAssertThrowsError(try LibraryOperations.renameFolder(one, to: "two"), "case-insensitive duplicate")
        for bad in ["", "a/b", ".hidden", "x.app"] { XCTAssertThrowsError(try LibraryOperations.renameFolder(one, to: bad), bad) }
        XCTAssertEqual(try snapshot(), before)
    }

    func testRenameCanChangeOnlyTheCase() throws {
        try makeEntry("A", in: "work")
        _ = try LibraryOperations.renameFolder(LibraryFolder(url: folder.appendingPathComponent("work")), to: "Work")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Work"])
        XCTAssertEqual(try scan().items.count, 1)
    }

    func testAFolderOfManagedTranscriptsGoesToTheTrashWhole() throws {
        try makeEntry("A", in: "Work", audio: true); try makeEntry("B", in: "Work")
        let work = LibraryFolder(url: folder.appendingPathComponent("Work"))
        XCTAssertEqual(try LibraryOperations.inspect(work), .init(entryCount: 2, unmanaged: []))
        var trashed: [URL] = []
        try LibraryOperations.trashFolder(work) { trashed.append($0) }
        XCTAssertEqual(trashed, [work.url])
    }

    func testAFolderWithOtherFilesIsNeverTrashedAndSaysWhat() throws {
        try makeEntry("A", in: "Work")
        try write("notes", "Work/notes.txt")
        try writePair("Legacy", in: "Work")
        try write("x", "Work/.DS_Store")
        let work = LibraryFolder(url: folder.appendingPathComponent("Work"))
        let contents = try LibraryOperations.inspect(work)
        XCTAssertEqual(contents.entryCount, 1)
        XCTAssertEqual(Set(contents.unmanaged), ["Legacy.md", "Legacy.timing.json", "notes.txt"])
        XCTAssertThrowsError(try LibraryOperations.trashFolder(work) { _ in XCTFail("must not trash") }) {
            XCTAssertEqual($0 as? LibraryError, .folderHasOtherFiles("Work"))
        }
    }

    func testAFailedTrashMoveDeletesNothingAndAMissingFolderIsReported() throws {
        try makeEntry("A", in: "Work")
        let work = LibraryFolder(url: folder.appendingPathComponent("Work"))
        struct Refused: Error {}
        XCTAssertThrowsError(try LibraryOperations.trashFolder(work) { _ in throw Refused() })
        XCTAssertEqual(try scan().items.count, 1)
        try FileManager.default.removeItem(at: work.url)
        XCTAssertThrowsError(try LibraryOperations.trashFolder(work) { _ in XCTFail() })
        XCTAssertThrowsError(try LibraryOperations.renameFolder(work, to: "X"))
    }

    func testAnEmptyFolderCanBeTrashed() throws {
        let empty = try LibraryOperations.createOrganizationFolder(named: "Empty", in: folder)
        var trashed = 0
        try LibraryOperations.trashFolder(empty) { _ in trashed += 1 }
        XCTAssertEqual(trashed, 1)
    }
}


// Fixes for the independent review of the UI pass (Codex, 2026-10-17).
final class FolderSafetyTests: ManagedLibraryCase {
    func testInspectionFailsClosedWhenTheFolderCannotBeListed() throws {
        try makeEntry("A", in: "Work")
        let work = LibraryFolder.current(at: folder.appendingPathComponent("Work"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: work.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: work.url.path) }
        XCTAssertThrowsError(try LibraryOperations.inspect(work))
        XCTAssertThrowsError(try LibraryOperations.trashFolder(work) { _ in XCTFail("must not trash") })
    }

    func testAForeignFolderWithAnEntryJsonIsNotAManagedTranscript() throws {
        try write("{ nope", "Work/Foreign/entry.json")
        try write("report", "Work/Foreign/report.docx")
        try write(#"{"schemaVersion":1}"#, "Work/Lookalike/entry.json")
        try write("report", "Work/Lookalike/report.docx")
        let work = LibraryFolder.current(at: folder.appendingPathComponent("Work"))
        let contents = try LibraryOperations.inspect(work)
        // Garbage entry.json: not ours. A well-formed one with a foreign file inside: the file is reported.
        XCTAssertEqual(contents.entryCount, 1)
        XCTAssertEqual(Set(contents.unmanaged), ["Foreign", "Lookalike/report.docx"])
        XCTAssertThrowsError(try LibraryOperations.trashFolder(work) { _ in XCTFail("must not trash") })
    }

    func testAnIncompleteRecordingEntryIsManagedButExtraFilesInsideAnEntryAreNot() throws {
        try EntryMetadata.create(EntryMetadata(createdAt: created), try dir("Work/Recording"))
        try write("audio", "Work/Recording/Recording.m4a")
        try makeEntry("Done", in: "Work")
        let work = LibraryFolder.current(at: folder.appendingPathComponent("Work"))
        XCTAssertEqual(try LibraryOperations.inspect(work), .init(entryCount: 2, unmanaged: []))
        try write("mine", "Work/Done/notes.txt")
        XCTAssertEqual(try LibraryOperations.inspect(work).unmanaged, ["Done/notes.txt"])
        XCTAssertThrowsError(try LibraryOperations.trashFolder(work) { _ in XCTFail("must not trash") })
    }

    func testFolderActionsRefuseAReplacementThatTookThePath() throws {
        try makeEntry("A", in: "Work")
        let listed = LibraryFolder.current(at: folder.appendingPathComponent("Work"))
        try FileManager.default.moveItem(at: listed.url, to: folder.appendingPathComponent("Elsewhere"))
        try write("unrelated", "Work/keep.txt")   // a different folder now sits at the path
        XCTAssertThrowsError(try LibraryOperations.renameFolder(listed, to: "Renamed"))
        XCTAssertThrowsError(try LibraryOperations.trashFolder(listed) { _ in XCTFail("must not trash") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Work/keep.txt").path))
    }

    func testSelectionRowRules() throws {
        // A loose pinned entry has only its Pinned row; a pinned entry in a folder has both.
        try makeEntry("Loose", pinned: true); try makeEntry("Filed", in: "F", pinned: true)
        let items = try scan().items
        let loose = try XCTUnwrap(items.first { $0.title == "Loose" }), filed = try XCTUnwrap(items.first { $0.title == "Filed" })
        func hasListRow(_ i: LibraryTranscript) -> Bool { i.isArchived || i.group != nil || !i.isPinned }
        XCTAssertFalse(hasListRow(loose))
        XCTAssertTrue(hasListRow(filed))
    }

    private func dir(_ path: String) throws -> URL {
        let url = folder.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}


// The "New" badge (LTR-61): saved by a transcription, not opened yet.
final class NewBadgeTests: ManagedLibraryCase {
    func testAFreshTranscriptionIsNewAndOldEntriesNeverAre() throws {
        let written = try LibraryOperations.writeEntry(baseName: "Fresh", in: folder, markdown: markdown(), createdAt: created)
        try makeEntry("Old")               // an entry.json without the field
        try writePair("Legacy")            // a v0.6 transcript
        let items = try scan().items
        XCTAssertEqual(items.filter(\.isNew).map(\.title), ["Fresh"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.markdown.path))
    }

    func testOpeningClearsItOnDiskAndNothingElseChanges() throws {
        _ = try LibraryOperations.writeEntry(baseName: "Fresh", in: folder, markdown: markdown(), createdAt: created)
        let item = try entry("Fresh")
        XCTAssertTrue(item.isNew)
        let mdHash = try sha(item.markdownURL)
        let opened = try LibraryOperations.markOpened(item)
        XCTAssertFalse(opened.isNew)
        let reread = try entry("Fresh")
        XCTAssertFalse(reread.isNew, "survives a rescan, as it would a relaunch")
        XCTAssertEqual(reread.createdAt, created)
        XCTAssertEqual(try sha(reread.markdownURL), mdHash)
        // Opening it again writes nothing.
        let before = try snapshot()
        _ = try LibraryOperations.markOpened(reread)
        XCTAssertEqual(try snapshot(), before)
    }

    func testARecordingBecomesNewOnlyWhenItsTranscriptIsSaved() throws {
        let staged = try write("recorded", "staging/recording.m4a")
        let audio = try LibraryOperations.saveRecording(staged, baseName: "Rec", in: folder, startedAt: created)
        let entryFolder = audio.deletingLastPathComponent()
        XCTAssertEqual(EntryMetadata.read(in: entryFolder).metadata?.unopened, false, "audio alone is not a new transcript")
        _ = try LibraryOperations.writeEntry(
            baseName: "x", in: folder, existingFolder: entryFolder, markdown: markdown(name: audio.lastPathComponent), createdAt: Date())
        XCTAssertEqual(EntryMetadata.read(in: entryFolder).metadata?.unopened, true)
        XCTAssertEqual(EntryMetadata.read(in: entryFolder).metadata?.createdAt, created, "still the recording start")
    }

    func testOneBadgeStateForAPinnedEntryInItsFolder() throws {
        _ = try LibraryOperations.writeEntry(baseName: "Fresh", in: try mkdir("Work"), markdown: markdown(), createdAt: created)
        var item = try entry("Fresh")
        item = try LibraryOperations.setPinned(item, true)
        let sections = LibrarySections(try scan())
        XCTAssertEqual(sections.pinned.map(\.isNew), [true])
        XCTAssertEqual(sections.folders[0].entries.map(\.isNew), [true], "the Pinned row and the folder row are one entry")
        _ = try LibraryOperations.markOpened(item)
        let after = LibrarySections(try scan())
        XCTAssertEqual(after.pinned.map(\.isNew) + after.folders[0].entries.map(\.isNew), [false, false])
    }

    func testTheFieldIsOptionalAndOmittedWhenFalse() throws {
        let data = try EntryMetadata(createdAt: created, unopened: true).encoded()
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"unopened\" : true"))
        XCTAssertFalse(String(decoding: try EntryMetadata(createdAt: created).encoded(), as: UTF8.self).contains("unopened"))
        XCTAssertEqual(EntryMetadata.decode(Data(#"{"schemaVersion":1}"#.utf8)), .valid(EntryMetadata(createdAt: nil)))
    }

    private func mkdir(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
