import AVFoundation
import os
import Speech

enum TranscriptionPhase: Sendable {
    case preparingVideo
    case preparingLanguage
    case transcribing

    var label: String {
        switch self {
        case .preparingVideo: "Preparing audio…"
        case .preparingLanguage: "Preparing language…"
        case .transcribing: "Transcribing…"
        }
    }
}

enum TranscriptionService {
    private static let log = Logger(subsystem: "nl.wavesweb.LocalTranscriber", category: "assets")

    static func transcribe(
        url: URL,
        locale: Locale,
        onPhaseChange: @MainActor (TranscriptionPhase) -> Void = { _ in },
        // How far into the audio the recognizer has delivered results (seconds), and
        // the audio's total length. Reported as results arrive; coverage of the audio,
        // not an estimate of the work left.
        onProgress: @escaping @MainActor (_ position: TimeInterval, _ total: TimeInterval) -> Void = { _, _ in }
    ) async throws -> Transcript {
        var temporaryAudioURL: URL?
        defer {
            if let temporaryAudioURL {
                try? FileManager.default.removeItem(at: temporaryAudioURL)
            }
        }

        let audioURL: URL
        let sourceAudioDuration: TimeInterval?
        switch url.pathExtension.lowercased() {
        case "mp4", "mov":
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("m4a")
            temporaryAudioURL = outputURL
            onPhaseChange(.preparingVideo)
            sourceAudioDuration = try await exportAudio(from: url, to: outputURL)
            audioURL = outputURL
        default:
            audioURL = url
            sourceAudioDuration = nil
        }

        let file = try AVAudioFile(forReading: audioURL)
        if let sourceAudioDuration {
            try validateNormalizedAudio(file, covers: sourceAudioDuration)
        }

        let totalDuration = file.processingFormat.sampleRate > 0
            ? Double(file.length) / file.processingFormat.sampleRate
            : 0
        let reportPosition: @Sendable (TimeInterval) async -> Void = { position in
            guard totalDuration > 0 else { return }
            await onProgress(position, totalDuration)
        }

        let transcriptLocaleIdentifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let speechLocale = Self.exactSupportedLocale(
            await SpeechTranscriber.supportedLocale(equivalentTo: locale),
            matching: locale
        )
        let dictationLocale = Self.exactSupportedLocale(
            await DictationTranscriber.supportedLocale(equivalentTo: locale),
            matching: locale
        )

        let transcriber: any SpeechModule
        let transcriptTranscriber: TranscriptTranscriber
        let collectSegments: () async throws -> CollectedResults
        if let speechLocale {
            let speechTranscriber = SpeechTranscriber(
                locale: speechLocale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange]
            )
            transcriber = speechTranscriber
            transcriptTranscriber = .speechTranscriber
            collectSegments = {
                try await Self.collectSegments(from: speechTranscriber, progress: reportPosition) { $0.text }
            }
        } else if let dictationLocale {
            // Punctuation is on deliberately (LTR-16): it adds sentences in nl-NL and
            // sv-SE without changing words, and has no effect in ru-RU and tr-TR.
            let dictationTranscriber = DictationTranscriber(
                locale: dictationLocale,
                contentHints: [],
                transcriptionOptions: [.punctuation],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange]
            )
            transcriber = dictationTranscriber
            transcriptTranscriber = .dictationTranscriber
            collectSegments = {
                var collected = try await Self.collectSegments(from: dictationTranscriber, progress: reportPosition) { $0.text }
                // Only the Markdown segments are adjusted; the raw recognition stays as emitted.
                collected.segments = Self.reattachingLeadingPunctuation(collected.segments)
                return collected
            }
        } else {
            throw TranscriptionError.unsupportedLocale(transcriptLocaleIdentifier)
        }

        // The installation request reserves the locale if it is not yet reserved, and
        // throws when the app's reservations are used up (LTR-73).
        let assetLocale = speechLocale ?? dictationLocale ?? locale
        await Self.makeRoomForReservation(of: assetLocale)
        if let installationRequest = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            onPhaseChange(.preparingLanguage)
            try await installationRequest.downloadAndInstall()
        }
        Self.recordUse(of: assetLocale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let segments = try await collectSegments()

        onPhaseChange(.transcribing)
        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let sampleRate = file.processingFormat.sampleRate
        let duration = sampleRate.isFinite && sampleRate > 0
            ? Double(file.length) / sampleRate
            : nil

        let collected = try await segments
        return Transcript(
            sourceURL: url,
            localeIdentifier: transcriptLocaleIdentifier,
            transcriber: transcriptTranscriber,
            duration: duration,
            segments: collected.segments,
            recognition: collected.recognition
        )
    }

    // UserDefaults key: the locales prepared by this app, most recently used first.
    private static let localeUseKey = "speechLocalesByUse"

    // Releases the least recently used other reservations when the app's allowance
    // would not fit this locale; nothing while there is room, so prepared languages
    // keep their assets. Jobs run one at a time (BatchQueue), so no recognition is
    // using a released locale. A release that fails leaves the request to throw.
    private static func makeRoomForReservation(of locale: Locale) async {
        let reserved = await AssetInventory.reservedLocales
        let release = LocaleReservations.toRelease(
            needed: locale.identifier,
            reserved: reserved.map(\.identifier),
            maximum: AssetInventory.maximumReservedLocales,
            recentlyUsed: UserDefaults.standard.stringArray(forKey: localeUseKey) ?? []
        )
        log.info("assets: need \(locale.identifier, privacy: .public); reserved \(reserved.map(\.identifier), privacy: .public) of \(AssetInventory.maximumReservedLocales, privacy: .public); releasing \(release, privacy: .public)")
        for reservedLocale in reserved where release.contains(reservedLocale.identifier) {
            await AssetInventory.release(reservedLocale: reservedLocale)
        }
    }

    private static func recordUse(of locale: Locale) {
        let used = UserDefaults.standard.stringArray(forKey: localeUseKey) ?? []
        UserDefaults.standard.set(LocaleReservations.used(locale.identifier, in: used), forKey: localeUseKey)
    }

    private static func exactSupportedLocale(
        _ supportedLocale: Locale?,
        matching requestedLocale: Locale
    ) -> Locale? {
        guard let supportedLocale else { return nil }
        let supportedIdentifier = supportedLocale.identifier.replacingOccurrences(of: "_", with: "-")
        let requestedIdentifier = requestedLocale.identifier.replacingOccurrences(of: "_", with: "-")
        return supportedIdentifier.caseInsensitiveCompare(requestedIdentifier) == .orderedSame
            ? supportedLocale
            : nil
    }

    private struct CollectedResults {
        var segments: [TranscriptSegment]
        var recognition: TimedRecognition
    }

    private static func collectSegments<Module: SpeechModule>(
        from module: Module,
        progress: @Sendable (TimeInterval) async -> Void,
        text: (Module.Result) -> AttributedString
    ) async throws -> CollectedResults {
        try await module.results.reduce(into: CollectedResults(segments: [], recognition: TimedRecognition())) { partialResult, result in
            let range = result.range
            let start = CMTimeGetSeconds(range.start)
            let end = CMTimeGetSeconds(CMTimeRangeGetEnd(range))
            if end.isFinite { await progress(end) }
            let attributedText = text(result)
            partialResult.segments.append(
                TranscriptSegment(startTime: start, endTime: end, text: String(attributedText.characters))
            )
            partialResult.recognition.results.append(
                recognitionResult(from: attributedText, start: start, end: end)
            )
        }
    }

    // The per-run timing the recognizer attaches to its text (audioTimeRange),
    // kept as emitted. Runs without any timing are not split into units: the
    // result then is segment-level data.
    private static func recognitionResult(
        from text: AttributedString,
        start: Double,
        end: Double
    ) -> RecognitionResult {
        let units = text.runs.map { run in
            let runText = String(text[run.range].characters)
            let range = run.audioTimeRange
            return RecognitionUnit(
                text: runText,
                kind: RecognitionUnit.classify(runText),
                start: range.map { CMTimeGetSeconds($0.start) },
                end: range.map { CMTimeGetSeconds(CMTimeRangeGetEnd($0)) }
            )
        }
        if units.contains(where: { $0.start != nil || $0.end != nil }) {
            return RecognitionResult(start: start, end: end, units: units)
        }
        let whole = String(text.characters)
        return RecognitionResult(
            start: start,
            end: end,
            units: whole.isEmpty ? [] : [RecognitionUnit(text: whole, kind: .segment)]
        )
    }

    // DictationTranscriber starts each result after the first with the previous
    // sentence's closing mark (". De temperatuur"); move it back to where it belongs.
    private static func reattachingLeadingPunctuation(
        _ segments: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        segments.reduce(into: []) { result, segment in
            let text = segment.text.drop(while: \.isWhitespace)
            let mark = text.prefix { ".,?!;:…".contains($0) }
            guard !mark.isEmpty, let previous = result.popLast() else {
                result.append(segment)
                return
            }
            result.append(TranscriptSegment(
                startTime: previous.startTime,
                endTime: previous.endTime,
                text: previous.text + mark
            ))
            result.append(TranscriptSegment(
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: String(text.dropFirst(mark.count))
            ))
        }
    }

    private static func exportAudio(from url: URL, to outputURL: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw TranscriptionError.noAudioTrack
        }

        let sourceTimeRange = try await audioTrack.load(.timeRange)
        let sourceDuration = CMTimeGetSeconds(sourceTimeRange.duration)
        guard sourceDuration.isFinite, sourceDuration > 0 else {
            throw TranscriptionError.invalidSourceDuration
        }

        let preset = AVAssetExportPresetAppleM4A
        guard await AVAssetExportSession.compatibility(
            ofExportPreset: preset,
            with: asset,
            outputFileType: .m4a
        ) else {
            throw TranscriptionError.unsupportedM4AExport
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw TranscriptionError.exportSessionUnavailable
        }

        do {
            try await exportSession.export(to: outputURL, as: .m4a)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranscriptionError.exportFailed(error.localizedDescription)
        }

        return sourceDuration
    }

    private static func validateNormalizedAudio(
        _ file: AVAudioFile,
        covers sourceDuration: TimeInterval
    ) throws {
        let sampleRate = file.processingFormat.sampleRate
        let normalizedDuration = sampleRate.isFinite && sampleRate > 0
            ? Double(file.length) / sampleRate
            : .nan
        guard normalizedDuration.isFinite, normalizedDuration > 0 else {
            throw TranscriptionError.invalidNormalizedDuration
        }

        let tolerance = max(2, sourceDuration * 0.001)
        guard normalizedDuration + tolerance >= sourceDuration else {
            throw TranscriptionError.truncatedAudio(
                expected: sourceDuration,
                actual: normalizedDuration
            )
        }
    }
}

private enum TranscriptionError: LocalizedError {
    case noAudioTrack
    case invalidSourceDuration
    case unsupportedLocale(String)
    case unsupportedM4AExport
    case exportSessionUnavailable
    case exportFailed(String)
    case invalidNormalizedDuration
    case truncatedAudio(expected: TimeInterval, actual: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "This video does not contain an audio track."
        case .invalidSourceDuration:
            return "The video's audio track duration could not be determined."
        case .unsupportedLocale(let locale):
            return "No on-device speech transcriber supports \(locale) on this Mac."
        case .unsupportedM4AExport:
            return "This video's audio can’t be exported as an M4A file."
        case .exportSessionUnavailable:
            return "No M4A export session could be created for this video."
        case .exportFailed(let reason):
            return "This video's audio couldn’t be exported: \(reason)"
        case .invalidNormalizedDuration:
            return "The exported audio duration could not be determined."
        case .truncatedAudio(let expected, let actual):
            return String(
                format: "The exported audio is incomplete: %.1f seconds exported, expected about %.1f seconds.",
                actual,
                expected
            )
        }
    }
}
