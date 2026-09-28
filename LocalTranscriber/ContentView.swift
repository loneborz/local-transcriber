import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedFile: URL?
    @State private var mediaInfo: MediaInfo?
    @State private var isTargeted = false
    @State private var isTranscribing = false
    @State private var selectedLanguage = TranscriptionLanguage.english
    @State private var processingPhase: TranscriptionPhase?
    @State private var transcript: Transcript?
    @State private var processingDuration: Duration?
    @State private var transcriptionError: String?
    @State private var savedTranscriptURL: URL?

    private let supportedExtensions = [
        "mp4",
        "mov",
        "m4a",
        "mp3",
        "wav"
    ]

    var body: some View {
        VStack(spacing: 20) {
            Image(
                systemName: selectedFile == nil
                    ? "waveform.badge.plus"
                    : "checkmark.circle.fill"
            )
            .font(.system(size: 42, weight: .light))

            if let selectedFile {
                VStack(spacing: 10) {
                    Text(selectedFile.lastPathComponent)
                        .font(.title3.weight(.medium))

                    if let mediaInfo {
                        HStack(spacing: 12) {
                            Text(mediaInfo.type)
                            Text("·")
                            Text(mediaInfo.duration)
                            Text("·")
                            Text(mediaInfo.fileSize)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Text(selectedFile.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        Text("Language")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Language", selection: $selectedLanguage) {
                            ForEach(TranscriptionLanguage.allCases) { language in
                                Text(language.title).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .disabled(isTranscribing)
                    }

                    Button {
                        guard let file = self.selectedFile else {
                            return
                        }
                        let locale = selectedLanguage.locale

                        let clock = ContinuousClock()
                        let startedAt = clock.now
                        processingPhase = nil
                        isTranscribing = true
                        transcript = nil
                        processingDuration = nil
                        transcriptionError = nil
                        savedTranscriptURL = nil

                        Task {
                            defer {
                                processingPhase = nil
                                isTranscribing = false
                            }

                            do {
                                let completedTranscript = try await TranscriptionService.transcribe(
                                    url: file,
                                    locale: locale,
                                    onPhaseChange: { processingPhase = $0 }
                                )
                                let elapsed = startedAt.duration(to: clock.now)
                                guard selectedFile == file else { return }
                                transcript = completedTranscript
                                processingDuration = elapsed
                            } catch {
                                guard selectedFile == file else { return }
                                transcriptionError = error.localizedDescription
                            }
                        }
                    } label: {
                        if isTranscribing {
                            Image(systemName: "waveform")
                                .font(.system(size: 14))
                                .symbolEffect(.breathe, options: .repeating, isActive: isTranscribing)
                        } else {
                            Text("Transcribe")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isTranscribing)
                    .padding(.top, 8)

                    if isTranscribing, let processingPhase {
                        Text(processingPhase.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let transcript {
                        VStack(spacing: 8) {
                            Text("Done · \(transcript.characterCount) characters")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let processingDuration {
                                let formattedMediaDuration = transcript.duration.flatMap(formatMediaDuration)
                                let processingTime = formatProcessingDuration(processingDuration)
                                let realtimeSpeed = transcript.duration.flatMap {
                                    formatRealtimeSpeed(
                                        mediaDuration: $0,
                                        processingDuration: processingDuration
                                    )
                                }

                                VStack(spacing: 5) {
                                    if let formattedMediaDuration {
                                        Text("\(formattedMediaDuration) processed in \(processingTime)")
                                    }

                                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                                        if let formattedMediaDuration {
                                            GridRow {
                                                Text("Media duration")
                                                Text(formattedMediaDuration).monospacedDigit()
                                            }
                                        }

                                        GridRow {
                                            Text("Processing time")
                                            Text(processingTime).monospacedDigit()
                                        }

                                        if let realtimeSpeed {
                                            GridRow {
                                                Text("Realtime speed")
                                                Text(realtimeSpeed).monospacedDigit()
                                            }
                                        }
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Button("Save Transcript…") {
                                saveTranscript(transcript)
                            }

                            if let savedTranscriptURL {
                                HStack(spacing: 0) {
                                    Text("Saved · ")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Button(savedTranscriptURL.lastPathComponent) {
                                        NSWorkspace.shared.activateFileViewerSelecting([savedTranscriptURL])
                                    }
                                    .font(.caption)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.tint)
                                }
                            }
                        }
                    }

                    if let transcriptionError {
                        Text(transcriptionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }

                    Button("New Transcript", action: startNewTranscript)
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .disabled(isTranscribing)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Drop audio or video")
                        .font(.title2.weight(.semibold))

                    Text("MP4 · MOV · M4A · MP3 · WAV")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(.ultraThinMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(
                    isTargeted
                        ? Color.accentColor
                        : Color.secondary.opacity(0.25),
                    lineWidth: isTargeted ? 2 : 1
                )
                .padding(24)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else {
                return false
            }

            guard supportedExtensions.contains(
                url.pathExtension.lowercased()
            ) else {
                return false
            }

            selectedFile = url
            mediaInfo = nil
            transcript = nil
            processingDuration = nil
            transcriptionError = nil
            savedTranscriptURL = nil

            Task {
                let info = await loadMediaInfo(for: url)
                guard selectedFile == url else { return }
                mediaInfo = info
            }

            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    private func startNewTranscript() {
        guard !isTranscribing else { return }

        selectedFile = nil
        mediaInfo = nil
        transcript = nil
        processingDuration = nil
        transcriptionError = nil
        savedTranscriptURL = nil
        processingPhase = nil
        isTargeted = false
    }

    private func loadMediaInfo(for url: URL) async -> MediaInfo {
        let asset = AVURLAsset(url: url)

        let duration: CMTime

        do {
            duration = try await asset.load(.duration)
        } catch {
            duration = .zero
        }

        let seconds = max(0, CMTimeGetSeconds(duration))

        let resourceValues = try? url.resourceValues(
            forKeys: [.fileSizeKey]
        )

        let bytes = resourceValues?.fileSize ?? 0

        return MediaInfo(
            type: url.pathExtension.uppercased(),
            duration: formatDuration(seconds),
            fileSize: ByteCountFormatter.string(
                fromByteCount: Int64(bytes),
                countStyle: .file
            )
        )
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else {
            return "Unknown duration"
        }

        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(
            format: "%d:%02d",
            minutes,
            seconds
        )
    }

    private func formatMediaDuration(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }

        if seconds < 60 {
            let tenths = (seconds * 10).rounded() / 10
            return "\(formatNumber(tenths, decimals: tenths.rounded() == tenths ? 0 : 1))s"
        }

        guard seconds < Double(Int.max) else { return nil }
        let wholeSeconds = Int(seconds)
        let hours = wholeSeconds / 3600
        let minutes = (wholeSeconds % 3600) / 60
        return hours > 0
            ? "\(hours)h \(twoDigits(minutes))m"
            : "\(minutes)m"
    }

    private func formatProcessingDuration(_ duration: Duration) -> String {
        let seconds = durationSeconds(duration)
        if seconds < 60 {
            let tenths = (seconds * 10).rounded() / 10
            return "\(formatNumber(tenths, decimals: tenths.rounded() == tenths ? 0 : 1))s"
        }

        guard seconds < Double(Int.max) else { return "\(formatNumber(seconds, decimals: 0))s" }
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours)h \(twoDigits(minutes))m \(twoDigits(remainingSeconds))s"
        }
        return "\(minutes)m \(remainingSeconds)s"
    }

    private func formatRealtimeSpeed(
        mediaDuration: TimeInterval,
        processingDuration: Duration
    ) -> String? {
        guard mediaDuration.isFinite, mediaDuration > 0 else { return nil }
        let elapsedSeconds = durationSeconds(processingDuration)
        guard elapsedSeconds > 0 else { return nil }

        let speed = mediaDuration / elapsedSeconds
        guard speed.isFinite, speed > 0 else { return nil }

        let rounded = speed >= 20 ? speed.rounded() : (speed * 10).rounded() / 10
        let decimals = speed < 20 && rounded.rounded() != rounded ? 1 : 0
        return "\(formatNumber(rounded, decimals: decimals))×"
    }

    private func durationSeconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    private func formatNumber(_ value: Double, decimals: Int) -> String {
        String(
            format: decimals == 0 ? "%.0f" : "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private func twoDigits(_ value: Int) -> String {
        String(format: "%02d", value)
    }

    private func saveTranscript(_ transcript: Transcript) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.markdown]
        panel.nameFieldStringValue = "\(transcript.sourceURL.deletingPathExtension().lastPathComponent).md"

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        do {
            try TranscriptMarkdownRenderer.render(transcript).write(
                to: destination,
                atomically: true,
                encoding: .utf8
            )
            savedTranscriptURL = destination
            transcriptionError = nil
        } catch {
            savedTranscriptURL = nil
            transcriptionError = error.localizedDescription
        }
    }
}

private struct MediaInfo {
    let type: String
    let duration: String
    let fileSize: String
}

private enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case english = "en-US"
    case dutch = "nl-NL"
    case german = "de-DE"
    case french = "fr-FR"
    case russian = "ru-RU"
    case spanish = "es-ES"
    case italian = "it-IT"
    case portuguese = "pt-BR"
    case turkish = "tr-TR"
    case swedish = "sv-SE"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var title: String {
        switch self {
        case .english: "English"
        case .dutch: "Dutch"
        case .german: "German"
        case .french: "French"
        case .russian: "Russian"
        case .spanish: "Spanish"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        case .turkish: "Turkish"
        case .swedish: "Swedish"
        }
    }
}
