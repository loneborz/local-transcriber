import Foundation

// The recognizer a job runs with (doc-3 Addendum 9): one saved preference, Apple
// Speech by default. Whisper is chosen explicitly and never replaces Apple Speech,
// or the other way round.
nonisolated enum TranscriptionEngine: String, Sendable, CaseIterable, Identifiable {
    case appleSpeech
    case whisper

    var id: String { rawValue }

    static let preferenceKey = "transcriptionEngine"

    // The saved preference; a missing or unknown value is Apple Speech.
    static func preferred(in defaults: UserDefaults = .standard) -> TranscriptionEngine {
        defaults.string(forKey: preferenceKey).flatMap(TranscriptionEngine.init) ?? .appleSpeech
    }

    // Whether a job can be created with this engine now. There is no other engine
    // to try instead: Whisper without its model blocks the input. The model is asked
    // about only for Whisper.
    func canStartJob(whisperInstalled: @autoclosure () -> Bool) -> Bool {
        self != .whisper || whisperInstalled()
    }

    // User-facing names (D6).
    var title: String {
        switch self {
        case .appleSpeech: "Apple Speech"
        case .whisper: "Whisper Large V3 Turbo"
        }
    }

    // Picks this engine's own transcriber; BatchQueue calls only the one picked,
    // so a Whisper failure fails the job instead of reaching Apple Speech.
    func transcriber<T>(appleSpeech: T, whisper: T) -> T {
        switch self {
        case .appleSpeech: appleSpeech
        case .whisper: whisper
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
