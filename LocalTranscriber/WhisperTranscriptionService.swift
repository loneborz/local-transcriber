import AVFoundation
import os
import WhisperKit

// Whisper Large V3 Turbo through WhisperKit (LTR-76 phase 1; doc-3 Addendum 7).
// Reads the model and its tokenizer from the app's own container and never
// downloads: WhisperKit's download is off, and the tokenizer files are checked
// first because WhisperKit would otherwise fetch a missing tokenizer from the
// network. Audio is loaded whole (WhisperKit's incremental loading is not
// adopted). No user-facing engine choice yet: Debug builds route jobs here from
// the Developer menu (WhisperDeveloperMenu.swift).
enum WhisperTranscriptionService {
    private nonisolated static let log = Logger(subsystem: "nl.wavesweb.LocalTranscriber", category: "whisper")
    nonisolated static let transcriber = TranscriptTranscriber.whisperLargeV3Turbo

    // <container>/Library/Application Support/Whisper/
    //   openai_whisper-large-v3-v20240930_turbo/   the Core ML model folder
    //   tokenizer/                                 config.json, tokenizer.json, tokenizer_config.json
    nonisolated static var folder: URL { URL.applicationSupportDirectory.appending(path: "Whisper", directoryHint: .isDirectory) }
    nonisolated static var modelFolder: URL { folder.appending(path: transcriber.rawValue, directoryHint: .isDirectory) }
    nonisolated static var tokenizerFolder: URL { folder.appending(path: "tokenizer", directoryHint: .isDirectory) }
    private static let modelFiles = ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"]
    private static let tokenizerFiles = ["config.json", "tokenizer.json", "tokenizer_config.json"]

    // Same shape as TranscriptionService.transcribe, so BatchQueue can call either.
    static func transcribe(
        url: URL,
        locale: Locale,
        onPhaseChange: @MainActor (TranscriptionPhase) -> Void = { _ in },
        onProgress: @escaping @MainActor (_ position: TimeInterval, _ total: TimeInterval) -> Void = { _, _ in }
    ) async throws -> Transcript {
        let localeIdentifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        guard let language = locale.language.languageCode?.identifier,
              Constants.languages.values.contains(language) else {
            throw WhisperTranscriptionError.unsupportedLanguage(localeIdentifier)
        }
        for name in modelFiles where !FileManager.default.fileExists(atPath: modelFolder.appending(path: name).path) {
            throw WhisperTranscriptionError.missingFile(modelFolder.appending(path: name).path)
        }
        for name in tokenizerFiles where !FileManager.default.fileExists(atPath: tokenizerFolder.appending(path: name).path) {
            throw WhisperTranscriptionError.missingFile(tokenizerFolder.appending(path: name).path)
        }

        // Duration as the Apple path measures it, so both share the file's time base.
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.processingFormat.sampleRate
        let duration = sampleRate.isFinite && sampleRate > 0 ? Double(file.length) / sampleRate : nil

        onPhaseChange(.preparingModel)
        let segments = try await run(audioURL: url, language: language, duration: duration, onPhaseChange: onPhaseChange, onProgress: onProgress)
        let mapped = WhisperRecognition.map(segments)
        return Transcript(
            sourceURL: url,
            localeIdentifier: localeIdentifier,
            transcriber: transcriber,
            duration: duration,
            segments: mapped.segments,
            recognition: mapped.recognition
        )
    }

    // Off the main actor: model loading (the first one compiles the model for
    // this Mac, about 71 s in LTR-66) and decoding take minutes.
    @concurrent
    private nonisolated static func run(
        audioURL: URL,
        language: String,
        duration: TimeInterval?,
        onPhaseChange: @MainActor (TranscriptionPhase) -> Void,
        onProgress: @escaping @MainActor (TimeInterval, TimeInterval) -> Void
    ) async throws -> [WhisperSegment] {
        let clock = ContinuousClock()
        let loadStart = clock.now
        let kit = try await WhisperKit(WhisperKitConfig(
            modelFolder: modelFolder.path,
            tokenizerFolder: tokenizerFolder,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        ))
        log.info("model loaded in \(loadStart.duration(to: clock.now), privacy: .public)")
        await onPhaseChange(.transcribing)

        if let duration, duration > 0 {
            kit.segmentDiscoveryCallback = { segments in
                guard let end = segments.map(\.end).max() else { return }
                Task { @MainActor in onProgress(min(Double(end), duration), duration) }
            }
        }
        let options = DecodingOptions(
            task: .transcribe, language: language, temperature: 0,
            usePrefillPrompt: true, detectLanguage: false, wordTimestamps: true
        )
        let decodeStart = clock.now
        let results: [TranscriptionResult]
        do {
            results = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        } catch {
            await kit.unloadModels()
            throw error
        }
        await kit.unloadModels()
        try Task.checkCancellation()
        log.info("transcribed in \(decodeStart.duration(to: clock.now), privacy: .public)")

        return results.flatMap(\.segments).map { segment in
            WhisperSegment(
                start: segment.start, end: segment.end, text: segment.text,
                words: segment.words?.map { WhisperWord(text: $0.word, start: $0.start, end: $0.end) }
            )
        }
    }
}

enum WhisperTranscriptionError: LocalizedError {
    case unsupportedLanguage(String)
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage(let locale):
            "Whisper does not support \(locale)."
        case .missingFile(let path):
            "The Whisper model is not installed: \(path) is missing. Nothing was downloaded."
        }
    }
}
