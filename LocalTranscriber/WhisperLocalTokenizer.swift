import Foundation
import NaturalLanguage
import WhisperKit

// Strictly local Whisper tokenizer (LTR-76 F1; doc-3 Addendum 8 D5 and D7).
//
// WhisperKit loads its tokenizer in WhisperKit.loadTokenizerIfNeeded() through
// ModelUtilities.loadTokenizer, which downloads it from Hugging Face when the
// local files are missing or fail to load. The app never takes that path:
// - LocalWhisperTokenizer.load checks the bundled files against their pinned
//   hashes, then reads and parses them with AutoTokenizerWrapper.from(modelFolder:),
//   which only reads files and throws on any error (no Hub branch).
// - The tokenizer is assigned before loadModels(), and LocalWhisperKit replaces
//   loadTokenizerIfNeeded() so a missing tokenizer throws instead of loading one.
//
// Compatibility: LocalWhisperTokenizer reproduces WhisperTokenizerWrapper, and
// LocalWhisperKit the decoder setup of loadTokenizerIfNeeded(), of WhisperKit
// 1.1.1 (argmax-oss-swift 1bbc57cb, Sources/WhisperKit/Core/Models.swift and
// WhisperKit.swift). WhisperTokenizerWrapper's initializer is internal, so it
// cannot be built from the app. Recheck both, and WhisperLocalTokenizerTests,
// on any WhisperKit upgrade.
// Adapted from WhisperKit, Copyright (c) 2024 argmax, inc., MIT License (see Credits).

nonisolated enum WhisperLocalTokenizerError: LocalizedError, Equatable {
    case filesNotVerified
    case tokenizerNotSet
    case modelDimensionsUnavailable
    case vocabularyMismatch(lastTimestampToken: Int?, logits: Int)

    var errorDescription: String? {
        switch self {
        case .filesNotVerified:
            "The bundled Whisper tokenizer files are missing or damaged."
        case .tokenizerNotSet:
            "The Whisper tokenizer was not loaded from the app before the model."
        case .modelDimensionsUnavailable:
            "The Whisper model doesn’t report its vocabulary and audio sizes."
        case .vocabularyMismatch(let token, let logits):
            "The Whisper tokenizer doesn’t match the model (last timestamp token \(token.map(String.init) ?? "none"), \(logits) logits)."
        }
    }
}

nonisolated final class LocalWhisperTokenizer: WhisperTokenizer, Sendable {
    let tokenizer: TokenizerWrapper
    let specialTokens: SpecialTokens
    let allLanguageTokens: Set<Int>

    // The bundled files, verified against their pins, then parsed.
    @concurrent
    static func load(from folder: URL) async throws -> LocalWhisperTokenizer {
        guard WhisperModelManifest.isVerified(at: folder, files: WhisperModelManifest.tokenizerFiles) else {
            throw WhisperLocalTokenizerError.filesNotVerified
        }
        return try await parse(folder)
    }

    // File reads and JSON parsing only; any missing, unreadable or malformed file throws.
    @concurrent
    static func parse(_ folder: URL) async throws -> LocalWhisperTokenizer {
        LocalWhisperTokenizer(tokenizer: try await AutoTokenizerWrapper.from(modelFolder: folder))
    }

    // As WhisperTokenizerWrapper.init(tokenizer:at:).
    init(tokenizer: TokenizerWrapper) {
        let specialTokens = SpecialTokens(
            endToken: tokenizer.convertTokenToId("<|endoftext|>") ?? Self.defaultEndToken,
            englishToken: tokenizer.convertTokenToId("<|en|>") ?? Self.defaultEnglishToken,
            noSpeechToken: tokenizer.convertTokenToId("<|nospeech|>") ?? Self.defaultNoSpeechToken,
            noTimestampsToken: tokenizer.convertTokenToId("<|notimestamps|>") ?? Self.defaultNoTimestampsToken,
            specialTokenBegin: tokenizer.convertTokenToId("<|endoftext|>") ?? Self.defaultSpecialTokenBegin,
            startOfPreviousToken: tokenizer.convertTokenToId("<|startofprev|>") ?? Self.defaultStartOfPreviousToken,
            startOfTranscriptToken: tokenizer.convertTokenToId("<|startoftranscript|>") ?? Self.defaultStartOfTranscriptToken,
            timeTokenBegin: tokenizer.convertTokenToId("<|0.00|>") ?? Self.defaultTimeTokenBegin,
            transcribeToken: tokenizer.convertTokenToId("<|transcribe|>") ?? Self.defaultTranscribeToken,
            translateToken: tokenizer.convertTokenToId("<|translate|>") ?? Self.defaultTranslateToken,
            whitespaceToken: tokenizer.convertTokenToId(" ") ?? Self.defaultWhitespaceToken
        )
        self.tokenizer = tokenizer
        self.specialTokens = specialTokens
        self.allLanguageTokens = Set(
            Constants.languages
                .compactMap { tokenizer.convertTokenToId("<|\($0.value)|>") }
                .filter { $0 > specialTokens.specialTokenBegin }
        )
    }

    func encode(text: String) -> [Int] {
        tokenizer.encode(text: text)
    }

    func decode(tokens: [Int]) -> String {
        tokenizer.decode(tokens: tokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        tokenizer.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        tokenizer.convertIdToToken(id)
    }

    // As WhisperTokenizerWrapper.splitToWordTokens(tokenIds:). Word timings
    // depend on it, so it is kept as it is.
    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        let decodedWords = tokenizer.decode(tokens: tokenIds.filter { $0 < specialTokens.specialTokenBegin })

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(decodedWords)
        let languageCode = recognizer.dominantLanguage.flatMap {
            Locale(identifier: $0.rawValue).language.languageCode?.identifier
        }

        if ["zh", "ja", "th", "lo", "my", "yue"].contains(languageCode) {
            return splitTokensOnUnicode(tokens: tokenIds)
        } else {
            return splitTokensOnSpaces(tokens: tokenIds)
        }
    }

    private func splitTokensOnUnicode(tokens: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        let decodedFull = tokenizer.decode(tokens: tokens)
        let replacementString = "\u{fffd}"

        var words: [String] = []
        var wordTokens: [[Int]] = []
        var currentTokens: [Int] = []

        for token in tokens {
            currentTokens.append(token)
            let decoded = tokenizer.decode(tokens: currentTokens)

            var hasUnicodeInFullString = false
            if let range = decoded.range(of: replacementString) {
                hasUnicodeInFullString = decodedFull[range] == replacementString
            }

            if !decoded.contains(replacementString) || hasUnicodeInFullString {
                words.append(decoded)
                wordTokens.append(currentTokens)
                currentTokens = []
            }
        }

        return (words, wordTokens)
    }

    private func splitTokensOnSpaces(tokens: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        let (subwords, subwordTokensList) = splitTokensOnUnicode(tokens: tokens)
        var words: [String] = []
        var wordTokens: [[Int]] = []

        for (subword, subwordTokens) in zip(subwords, subwordTokensList) {
            let special = subwordTokens.first! >= specialTokens.specialTokenBegin
            let withSpace = subword.hasPrefix(" ")
            var punctuation = false
            if let strippedSubword = UnicodeScalar(subword.trimmingCharacters(in: .whitespaces)) {
                punctuation = CharacterSet.punctuationCharacters.contains(strippedSubword)
            }
            if special || withSpace || punctuation || words.isEmpty {
                words.append(subword)
                wordTokens.append(subwordTokens)
            } else {
                words[words.count - 1] += subword
                wordTokens[words.count - 1].append(contentsOf: subwordTokens)
            }
        }

        return (words, wordTokens)
    }

    // WhisperTokenizerWrapper's defaults (base vocabulary).
    static var defaultWhitespaceToken: Int { 220 }
    static var defaultSpecialTokenBegin: Int { 50257 }
    static var defaultEndToken: Int { 50257 }
    static var defaultStartOfPreviousToken: Int { 50361 }
    static var defaultStartOfTranscriptToken: Int { 50258 }
    static var defaultEnglishToken: Int { 50259 }
    static var defaultTranscribeToken: Int { 50359 }
    static var defaultTranslateToken: Int { 50358 }
    static var defaultNoSpeechToken: Int { 50362 }
    static var defaultNoTimestampsToken: Int { 50363 }
    static var defaultTimeTokenBegin: Int { 50364 }
}

// WhisperKit that never loads a tokenizer itself. loadModels() calls
// loadTokenizerIfNeeded() once the models are loaded; this version never calls
// WhisperKit's own (network-capable) loader. It throws unless the app's tokenizer
// is set, and sets the decoder's multilingual flag from the loaded model as
// WhisperKit does. modelVariant (private(set), only used to pick a tokenizer to
// load) and the tokenizer load timing stay at their defaults.
nonisolated final class LocalWhisperKit: WhisperKit {
    override func loadTokenizerIfNeeded() async throws {
        guard let tokenizer else { throw WhisperLocalTokenizerError.tokenizerNotSet }
        guard let logitsDim = textDecoder.logitsSize, audioEncoder.embedSize != nil else {
            throw WhisperLocalTokenizerError.modelDimensionsUnavailable
        }
        // Whisper's last token is the <|30.00|> timestamp, so the tokenizer and
        // the decoder must agree on its position.
        let lastTimestampToken = tokenizer.convertTokenToId("<|30.00|>")
        guard lastTimestampToken == logitsDim - 1 else {
            throw WhisperLocalTokenizerError.vocabularyMismatch(lastTimestampToken: lastTimestampToken, logits: logitsDim)
        }
        // ModelUtilities.isModelMultilingual (internal): only the English-only vocabulary has 51864 logits.
        textDecoder.isModelMultilingual = logitsDim != 51864
    }
}
