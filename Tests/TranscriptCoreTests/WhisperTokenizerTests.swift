import XCTest
@testable import TranscriptCore

// The bundled tokenizer is checked against its pins before WhisperKit sees it,
// so a missing, damaged or malformed file fails before any load (LTR-76 F1).
final class WhisperTokenizerTests: XCTestCase {
    private let vendored = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Vendor/WhisperTokenizer")
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "WhisperTokenizer-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: vendored, to: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var isVerified: Bool { WhisperModelManifest.isVerified(at: folder, files: WhisperModelManifest.tokenizerFiles) }

    func testVendoredTokenizerMatchesItsPins() {
        XCTAssertTrue(WhisperModelManifest.isVerified(at: vendored, files: WhisperModelManifest.tokenizerFiles))
        XCTAssertTrue(isVerified)
    }

    func testMissingFileFails() throws {
        for name in WhisperModelManifest.tokenizerFiles.map(\.path) {
            let url = folder.appending(path: name)
            let data = try Data(contentsOf: url)
            try FileManager.default.removeItem(at: url)
            XCTAssertFalse(isVerified, name)
            try data.write(to: url)
        }
        XCTAssertTrue(isVerified)
    }

    // Same size, one byte changed: only the hash can tell.
    func testCorruptFileOfTheSameSizeFails() throws {
        let url = folder.appending(path: "tokenizer.json")
        var data = try Data(contentsOf: url)
        data[data.count / 2] ^= 0x01
        try data.write(to: url)
        XCTAssertFalse(isVerified)
    }

    func testMalformedJSONFails() throws {
        try Data("{".utf8).write(to: folder.appending(path: "tokenizer_config.json"))
        XCTAssertFalse(isVerified)
    }
}
