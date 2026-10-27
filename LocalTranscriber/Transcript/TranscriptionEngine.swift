import Foundation

// The recognizer chosen for one input (doc-3 Addendum 8, D1): Apple Speech is the
// default; Whisper is chosen explicitly and never replaces Apple Speech, or the
// other way round.
nonisolated enum TranscriptionEngine: String, Sendable, CaseIterable, Identifiable {
    case appleSpeech
    case whisper

    var id: String { rawValue }

    // User-facing names (D6).
    var title: String {
        switch self {
        case .appleSpeech: "Apple Speech"
        case .whisper: "Whisper Large V3 Turbo"
        }
    }

    // The Whisper language code for a locale identifier ("nl-NL" -> "nl"), or nil
    // when Whisper does not support that language. `supported` is the runtime's
    // own list (WhisperKit's Constants.languages values).
    static func whisperLanguage(for identifier: String, supported: Set<String>) -> String? {
        let code = Locale(identifier: identifier).language.languageCode?.identifier
        return code.flatMap { supported.contains($0) ? $0 : nil }
    }
}
