import AVFoundation
import Speech

enum TranscriptionPhase: Sendable {
    case preparingVideo
    case transcribing

    var label: String {
        switch self {
        case .preparingVideo: "Preparing video…"
        case .transcribing: "Transcribing…"
        }
    }
}

enum TranscriptionService {
    static func transcribe(
        url: URL,
        locale: Locale = Locale(identifier: "en-US"),
        onPhaseChange: @MainActor (TranscriptionPhase) -> Void = { _ in }
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

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let segments: [TranscriptSegment] = try transcriber.results.reduce(into: []) {
            partialResult,
            result in

            let range = result.range
            partialResult.append(
                TranscriptSegment(
                    startTime: CMTimeGetSeconds(range.start),
                    endTime: CMTimeGetSeconds(CMTimeRangeGetEnd(range)),
                    text: String(result.text.characters)
                )
            )
        }

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

        return Transcript(
            sourceURL: url,
            localeIdentifier: locale.identifier,
            duration: duration,
            segments: try await segments
        )
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
        case .unsupportedM4AExport:
            return "This video's audio cannot be exported as an M4A file by AVFoundation."
        case .exportSessionUnavailable:
            return "AVFoundation could not create an M4A export session for this video."
        case .exportFailed(let reason):
            return "AVFoundation could not export this video's audio: \(reason)"
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

struct Transcript: Sendable {
    let sourceURL: URL
    let localeIdentifier: String
    let duration: TimeInterval?
    let segments: [TranscriptSegment]

    var characterCount: Int {
        segments.reduce(0) { $0 + $1.text.count }
    }
}

struct TranscriptSegment: Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

enum TranscriptMarkdownRenderer {
    static func render(_ transcript: Transcript) -> String {
        let sourceName = transcript.sourceURL.lastPathComponent
        var metadata = ["**Source:** `\(sourceName)`"]

        if let duration = transcript.duration {
            metadata.append("**Duration:** \(timestamp(duration.rounded()))")
        }

        metadata.append("**Language:** \(transcript.localeIdentifier)")
        metadata.append("**Engine:** Apple SpeechAnalyzer")

        var markdown = "# \(transcript.sourceURL.deletingPathExtension().lastPathComponent)\n\n"
        markdown += metadata.joined(separator: "  \n")
        markdown += "\n\n## Transcript"

        var blocks: [(minute: Int, startTime: TimeInterval, text: String)] = []
        let segments = transcript.segments.enumerated().sorted {
            $0.element.startTime == $1.element.startTime
                ? $0.offset < $1.offset
                : $0.element.startTime < $1.element.startTime
        }

        for (_, segment) in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let minute = Int(max(0, segment.startTime) / 60)
            if blocks.last?.minute == minute {
                blocks[blocks.count - 1].text += " " + text
            } else {
                blocks.append((minute, segment.startTime, text))
            }
        }

        for block in blocks {
            markdown += "\n\n### \(timestamp(block.startTime))\n\n\(block.text)"
        }

        return markdown + "\n"
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        return String(
            format: "%02d:%02d:%02d",
            totalSeconds / 3600,
            (totalSeconds % 3600) / 60,
            totalSeconds % 60
        )
    }
}
