import AVFoundation
import os
import WhisperKit

// Whisper Large V3 Turbo through WhisperKit (LTR-76; doc-3 Addenda 7 and 8).
// Recognition is fully local: the model comes from WhisperModelStore's folder in
// the app's container and the tokenizer is bundled with the app
// (Contents/Resources/WhisperTokenizer). WhisperKit's download is off and every
// file is checked before loading, because WhisperKit would otherwise fetch a
// missing tokenizer from the network. Audio is loaded whole (WhisperKit's
// incremental loading is not adopted). Never falls back to Apple Speech.
enum WhisperTranscriptionService {
    private nonisolated static let log = Logger(subsystem: "nl.wavesweb.LocalTranscriber", category: "whisper")
    nonisolated static let transcriber = TranscriptTranscriber.whisperLargeV3Turbo

    nonisolated static var tokenizerFolder: URL? { Bundle.main.url(forResource: "WhisperTokenizer", withExtension: nil) }
    private static let tokenizerFiles = ["config.json", "tokenizer.json", "tokenizer_config.json"]

    // The runtime's own language list.
    static let supportedLanguages = Set(Constants.languages.values)

    static func supports(_ language: TranscriptionLanguage) -> Bool {
        TranscriptionEngine.whisperLanguage(for: language.rawValue, supported: supportedLanguages) != nil
    }

    // Same shape as TranscriptionService.transcribe, so BatchQueue can call either.
    static func transcribe(
        url: URL,
        locale: Locale,
        onPhaseChange: @MainActor (TranscriptionPhase) -> Void = { _ in },
        onProgress: @escaping @MainActor (_ position: TimeInterval, _ total: TimeInterval) -> Void = { _, _ in }
    ) async throws -> Transcript {
        let localeIdentifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        guard let language = TranscriptionEngine.whisperLanguage(for: localeIdentifier, supported: supportedLanguages) else {
            throw WhisperTranscriptionError.unsupportedLanguage(localeIdentifier)
        }
        let store = WhisperModelStore.shared
        store.refresh()
        guard store.isInstalled else { throw WhisperTranscriptionError.modelNotInstalled }
        guard let tokenizerFolder,
              tokenizerFiles.allSatisfy({ FileManager.default.fileExists(atPath: tokenizerFolder.appending(path: $0).path) })
        else { throw WhisperTranscriptionError.tokenizerMissing }

        // Video is exported to audio first, exactly as for Apple Speech.
        let audio = try await TranscriptionService.prepareAudio(for: url, onPhaseChange: onPhaseChange)
        defer { audio.removeTemporaryFile() }
        // Duration as the Apple path measures it, so both share the file's time base.
        let file = try audio.open()
        let sampleRate = file.processingFormat.sampleRate
        let duration = sampleRate.isFinite && sampleRate > 0 ? Double(file.length) / sampleRate : nil

        onPhaseChange(.preparingModel)
        store.preparationStarted()
        let kit: WhisperKit
        do {
            kit = try await load(tokenizerFolder: tokenizerFolder)
            store.preparationEnded(succeeded: true)
        } catch {
            store.preparationEnded(succeeded: false)
            throw WhisperTranscriptionError.preparationFailed(error.localizedDescription)
        }
        onPhaseChange(.transcribing)
        let segments: [WhisperSegment]
        do {
            segments = try await run(kit, audioURL: audio.url, language: language, duration: duration, onProgress: onProgress)
        } catch {
            throw WhisperTranscriptionError.recognitionFailed(error.localizedDescription)
        }
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

    // Off the main actor: the first load compiles the model for this Mac (about
    // 71 s on the LTR-66 Mac; not a guarantee).
    @concurrent
    private nonisolated static func load(tokenizerFolder: URL) async throws -> WhisperKit {
        let start = ContinuousClock.now
        let kit = try await WhisperKit(WhisperKitConfig(
            modelFolder: WhisperModelStore.modelFolder.path,
            tokenizerFolder: tokenizerFolder,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        ))
        log.info("model loaded in \(start.duration(to: .now), privacy: .public)")
        return kit
    }

    @concurrent
    private nonisolated static func run(
        _ kit: WhisperKit,
        audioURL: URL,
        language: String,
        duration: TimeInterval?,
        onProgress: @escaping @MainActor (TimeInterval, TimeInterval) -> Void
    ) async throws -> [WhisperSegment] {
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
        let start = ContinuousClock.now
        let results: [TranscriptionResult]
        do {
            results = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        } catch {
            await kit.unloadModels()
            throw error
        }
        await kit.unloadModels()
        try Task.checkCancellation()
        log.info("transcribed in \(start.duration(to: .now), privacy: .public)")

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
    case modelNotInstalled
    case tokenizerMissing
    case preparationFailed(String)
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage(let locale):
            "Whisper Large V3 Turbo doesn’t support \(locale). Choose another language or Apple Speech."
        case .modelNotInstalled:
            "Whisper Large V3 Turbo isn’t installed. Download it in Settings › General, then choose Retry."
        case .tokenizerMissing:
            "This copy of Local Transcriber is missing the Whisper tokenizer files. Reinstall the app."
        case .preparationFailed(let reason):
            "Whisper couldn’t prepare the model: \(reason)"
        case .recognitionFailed(let reason):
            "Whisper couldn’t transcribe this file: \(reason)"
        }
    }
}
