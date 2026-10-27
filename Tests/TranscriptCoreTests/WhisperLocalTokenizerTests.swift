import XCTest
@testable import TranscriptCore
@testable import WhisperKit

// The app loads the Whisper tokenizer itself and never through WhisperKit's
// loader, whose failure path downloads from Hugging Face (LTR-76 F1). These tests
// hold the adapter to WhisperKit 1.1.1's own WhisperTokenizerWrapper (built here
// through @testable, as its initializer is internal) and check that every failure
// throws locally.
final class WhisperLocalTokenizerTests: XCTestCase {
    private let vendored = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Vendor/WhisperTokenizer")
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "WhisperLocalTokenizer-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: vendored, to: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: folder.appending(path: "tokenizer.json").path)
        try? FileManager.default.removeItem(at: folder)
    }

    private func contents(_ url: URL) -> [String] {
        (FileManager.default.subpaths(atPath: url.path) ?? []).sorted()
    }

    // Throws, and leaves the folder as it was: WhisperKit's fallback would
    // download into a models/ folder there.
    private func assertParseFailsLocally(_ message: String, line: UInt = #line) async {
        let before = contents(folder)
        do {
            _ = try await LocalWhisperTokenizer.parse(folder)
            XCTFail("parsed: \(message)", line: line)
        } catch {}
        XCTAssertEqual(contents(folder), before, message, line: line)
    }

    private func assertLoadRefused(_ message: String, line: UInt = #line) async {
        do {
            _ = try await LocalWhisperTokenizer.load(from: folder)
            XCTFail("loaded: \(message)", line: line)
        } catch {
            XCTAssertEqual(error as? WhisperLocalTokenizerError, .filesNotVerified, message, line: line)
        }
    }

    // MARK: Loading (A-E)

    func testBundledTokenizerLoads() async throws {
        let tokenizer = try await LocalWhisperTokenizer.load(from: vendored)
        XCTAssertEqual(tokenizer.specialTokens.startOfTranscriptToken, 50258)
        XCTAssertEqual(tokenizer.specialTokens.timeTokenBegin, 50365)
        XCTAssertEqual(tokenizer.convertTokenToId("<|30.00|>"), 51865)
        XCTAssertNotNil(tokenizer.convertTokenToId("<|nl|>"))
    }

    func testMissingFilesAreRefusedAndFailToParse() async throws {
        for name in WhisperModelManifest.tokenizerFiles.map(\.path) {
            let url = folder.appending(path: name)
            let data = try Data(contentsOf: url)
            try FileManager.default.removeItem(at: url)
            await assertLoadRefused(name)
            if name != "config.json" { await assertParseFailsLocally("missing \(name)") }
            try data.write(to: url)
        }
        _ = try await LocalWhisperTokenizer.load(from: folder)
    }

    func testCorruptChecksumIsRefused() async throws {
        let url = folder.appending(path: "tokenizer.json")
        var data = try Data(contentsOf: url)
        data[data.count / 2] ^= 0x01
        try data.write(to: url)
        await assertLoadRefused("one byte changed")
    }

    // A parse failure after the files passed their checks (here: files that
    // would not pass them, handed straight to the parser).
    func testMalformedJSONFailsToParseLocally() async throws {
        for name in ["tokenizer.json", "tokenizer_config.json"] {
            let url = folder.appending(path: name)
            let data = try Data(contentsOf: url)
            try Data("{".utf8).write(to: url)
            await assertLoadRefused("malformed \(name)")
            await assertParseFailsLocally("malformed \(name)")
            try data.write(to: url)
        }
    }

    func testUnreadableFileFailsToParseLocally() async throws {
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: folder.appending(path: "tokenizer.json").path)
        await assertParseFailsLocally("unreadable tokenizer.json")
    }

    // MARK: Fail-closed WhisperKit (F, K, L)

    private func kit(logits: Int?, embed: Int? = 1280) async throws -> LocalWhisperKit {
        try await LocalWhisperKit(WhisperKitConfig(
            downloadBase: folder,
            modelFolder: folder.path,
            tokenizerFolder: folder,
            audioEncoder: StubEncoder(embed: embed),
            textDecoder: StubDecoder(logits: logits),
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: false,
            download: false
        ))
    }

    // loadModels() calls loadTokenizerIfNeeded() once the models are loaded. With
    // no tokenizer set it throws our error: WhisperKit's own loader would throw
    // tokenizerUnavailable here (no logits size), and is never reached.
    func testMissingTokenizerThrowsInsteadOfLoadingOne() async throws {
        let kit = try await kit(logits: nil)
        let before = contents(folder)
        do {
            try await kit.loadTokenizerIfNeeded()
            XCTFail("no tokenizer accepted")
        } catch {
            XCTAssertEqual(error as? WhisperLocalTokenizerError, .tokenizerNotSet)
        }
        XCTAssertNil(kit.tokenizer)
        XCTAssertEqual(contents(folder), before)
        // Also with model sizes that would let WhisperKit's loader go ahead.
        let sized = try await self.kit(logits: 51866)
        do {
            try await sized.loadTokenizerIfNeeded()
            XCTFail("no tokenizer accepted")
        } catch {
            XCTAssertEqual(error as? WhisperLocalTokenizerError, .tokenizerNotSet)
        }
        XCTAssertNil(sized.tokenizer)
        XCTAssertEqual(contents(folder), before)
    }

    func testMultilingualDecoderIsSetFromTheModel() async throws {
        let tokenizer = try await LocalWhisperTokenizer.load(from: vendored)
        let kit = try await kit(logits: 51866)
        kit.tokenizer = tokenizer
        XCTAssertFalse(kit.textDecoder.isModelMultilingual)
        XCTAssertTrue(kit.textDecoder.tokenizer as? LocalWhisperTokenizer === tokenizer)
        try await kit.loadTokenizerIfNeeded()
        XCTAssertTrue(kit.textDecoder.isModelMultilingual)
        XCTAssertTrue(kit.tokenizer as? LocalWhisperTokenizer === tokenizer)
    }

    func testMissingOrInconsistentModelSizesFail() async throws {
        let tokenizer = try await LocalWhisperTokenizer.load(from: vendored)
        for (logits, embed, expected) in [
            (nil, 1280, WhisperLocalTokenizerError.modelDimensionsUnavailable),
            (51866, nil, .modelDimensionsUnavailable),
            (51864, 1280, .vocabularyMismatch(lastTimestampToken: 51865, logits: 51864)),
            (51865, 1280, .vocabularyMismatch(lastTimestampToken: 51865, logits: 51865)),
        ] as [(Int?, Int?, WhisperLocalTokenizerError)] {
            let kit = try await kit(logits: logits, embed: embed)
            kit.tokenizer = tokenizer
            do {
                try await kit.loadTokenizerIfNeeded()
                XCTFail("accepted \(String(describing: logits)) \(String(describing: embed))")
            } catch {
                XCTAssertEqual(error as? WhisperLocalTokenizerError, expected)
            }
            XCTAssertFalse(kit.textDecoder.isModelMultilingual)
        }
    }

    // MARK: Parity with WhisperTokenizerWrapper (G-J)

    private func pair() async throws -> (LocalWhisperTokenizer, WhisperTokenizerWrapper) {
        let local = try await LocalWhisperTokenizer.load(from: vendored)
        let reference = WhisperTokenizerWrapper(tokenizer: try await AutoTokenizerWrapper.from(modelFolder: vendored), at: vendored)
        return (local, reference)
    }

    private static let texts = [
        " Goedemorgen, dit is een korte test van de Nederlandse transcriptie.",
        " Het weer is vandaag mooi: 21,5 graden! Zo'n dag, hè? Één keer per week.",
        " Hello, world! It's a test, isn't it? Numbers like 3.14 and $1,000.",
        " Well... \"quoted\" (parenthesised) - and a dash; then: done.",
        " Привет, как дела? Всё хорошо.",
        " Café naïve façade – “curly quotes” 🎉👍🏽 e\u{301}",
        "今天天气很好，我们去公园散步吧。",
        "これは日本語のテストです。東京へ行きます。",
        "สวัสดีครับ ยินดีที่ได้รู้จัก",
        "",
    ]

    func testSpecialTokensMatch() async throws {
        let (local, reference) = try await pair()
        func fields(_ tokens: SpecialTokens) -> [String] {
            Mirror(reflecting: tokens).children.map { "\($0.label ?? "?")=\($0.value)" }
        }
        XCTAssertEqual(fields(local.specialTokens).count, 11)
        XCTAssertEqual(fields(local.specialTokens), fields(reference.specialTokens))
    }

    func testLanguageTokensMatch() async throws {
        let (local, reference) = try await pair()
        XCTAssertEqual(local.allLanguageTokens, reference.allLanguageTokens)
        XCTAssertEqual(local.allLanguageTokens.count, Set(Constants.languages.values).count)
        for code in ["nl", "en", "ru", "de", "yue"] {
            XCTAssertTrue(local.allLanguageTokens.contains(try XCTUnwrap(local.convertTokenToId("<|\(code)|>"))), code)
        }
    }

    func testEncodingDecodingAndConversionsMatch() async throws {
        let (local, reference) = try await pair()
        for text in Self.texts {
            let tokens = local.encode(text: text)
            XCTAssertEqual(tokens, reference.encode(text: text), text)
            XCTAssertEqual(local.decode(tokens: tokens), reference.decode(tokens: tokens), text)
        }
        for id in 0..<51866 {
            let token = local.convertIdToToken(id)
            XCTAssertEqual(token, reference.convertIdToToken(id), "\(id)")
            if let token { XCTAssertEqual(local.convertTokenToId(token), reference.convertTokenToId(token), token) }
        }
        XCTAssertNil(local.convertIdToToken(51866))
        XCTAssertEqual(local.convertTokenToId("<|no such token|>"), reference.convertTokenToId("<|no such token|>"))
    }

    // Word timings come from splitToWordTokens: the same words and token groups,
    // for text alone and as a segment (start, language, task, timestamps, end).
    func testWordSplittingMatches() async throws {
        let (local, reference) = try await pair()
        let special = local.specialTokens
        for text in Self.texts {
            let body = local.tokenizer.encode(text: text, addSpecialTokens: false)
            for (language, tokens) in [
                ("none", body),
                ("nl", [special.startOfTranscriptToken, local.convertTokenToId("<|nl|>")!, special.transcribeToken, special.timeTokenBegin]
                    + body + [special.timeTokenBegin + 150, special.endToken]),
                ("en", [special.timeTokenBegin + 20] + body + [special.timeTokenBegin + 40]),
            ] {
                let a = local.splitToWordTokens(tokenIds: tokens)
                let b = reference.splitToWordTokens(tokenIds: tokens)
                XCTAssertEqual(a.words, b.words, "\(language): \(text)")
                XCTAssertEqual(a.wordTokens, b.wordTokens, "\(language): \(text)")
            }
        }
        // Spaced and unspaced scripts take different branches.
        let dutch = local.splitToWordTokens(tokenIds: local.tokenizer.encode(text: Self.texts[0], addSpecialTokens: false))
        XCTAssertEqual(dutch.words.first, " Goedemorgen")
        let japanese = local.splitToWordTokens(tokenIds: local.tokenizer.encode(text: Self.texts[7], addSpecialTokens: false))
        XCTAssertFalse(japanese.words.contains { $0.contains("\u{fffd}") })
        XCTAssertEqual(japanese.words.joined(), Self.texts[7])
    }
}

// Model sizes without Core ML models (WhisperKit reads them from the loaded models).
private nonisolated final class StubDecoder: TextDecoder {
    let logits: Int?
    init(logits: Int?) { self.logits = logits }
    override var logitsSize: Int? { logits }
}

private nonisolated final class StubEncoder: AudioEncoder {
    let embed: Int?
    init(embed: Int?) { self.embed = embed }
    override var embedSize: Int? { embed }
}
