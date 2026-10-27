import XCTest
@testable import TranscriptCore

final class WhisperEngineTests: XCTestCase {
    // WhisperKit 1.1.1's Constants.languages values include all ten menu languages.
    private let whisperLanguages: Set = ["en", "nl", "de", "fr", "ru", "es", "it", "pt", "tr", "sv", "ja"]

    func testMenuLocalesMapToWhisperCodes() {
        let menu = ["en-US": "en", "nl-NL": "nl", "de-DE": "de", "fr-FR": "fr", "ru-RU": "ru",
                    "es-ES": "es", "it-IT": "it", "pt-BR": "pt", "tr-TR": "tr", "sv-SE": "sv"]
        for (identifier, code) in menu {
            XCTAssertEqual(TranscriptionEngine.whisperLanguage(for: identifier, supported: whisperLanguages), code, identifier)
        }
    }

    func testUnsupportedLanguageIsRefusedNotReplaced() {
        XCTAssertNil(TranscriptionEngine.whisperLanguage(for: "fy-NL", supported: whisperLanguages))
        XCTAssertNil(TranscriptionEngine.whisperLanguage(for: "nl-NL", supported: ["en"]))
    }

    func testUserFacingNames() {
        XCTAssertEqual(TranscriptionEngine.allCases.map(\.title), ["Apple Speech", "Whisper Large V3 Turbo"])
    }

    func testManifestIsThePinnedModel() {
        XCTAssertEqual(WhisperModelManifest.files.count, 24)
        XCTAssertEqual(WhisperModelManifest.totalBytes, 1_638_464_446)
        XCTAssertEqual(Set(WhisperModelManifest.files.map(\.path)).count, 24)
        XCTAssertTrue(WhisperModelManifest.files.allSatisfy { $0.sha256.count == 64 })
        XCTAssertEqual(
            WhisperModelManifest.remoteURL(for: WhisperModelManifest.files[0]).absoluteString,
            "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/0f63a7800b00dd0226abd051b906c246e1907482/openai_whisper-large-v3-v20240930_turbo/AudioEncoder.mlmodelc/analytics/coremldata.bin"
        )
    }

    func testVerificationAndCompleteness() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WhisperManifest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = Data("hello".utf8)
        let url = folder.appendingPathComponent("f")
        try data.write(to: url)
        let good = WhisperModelManifest.File(path: "f", size: 5, sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        XCTAssertTrue(try WhisperModelManifest.matches(url, good))
        XCTAssertFalse(try WhisperModelManifest.matches(url, .init(path: "f", size: 5, sha256: String(repeating: "0", count: 64))))
        XCTAssertFalse(try WhisperModelManifest.matches(url, .init(path: "f", size: 6, sha256: good.sha256)))
        // An empty or partial folder is never complete.
        XCTAssertFalse(WhisperModelManifest.isComplete(at: folder))
    }
}
