import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedFile: URL?
    @State private var mediaInfo: MediaInfo?
    @State private var isTargeted = false
    @State private var isTranscribing = false
    @State private var transcript: Transcript?
    @State private var transcriptionError: String?

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

                    Button {
                        guard let file = self.selectedFile else {
                            return
                        }

                        isTranscribing = true
                        transcript = nil
                        transcriptionError = nil

                        Task {
                            defer { isTranscribing = false }

                            do {
                                transcript = try await TranscriptionService.transcribe(url: file)
                            } catch {
                                transcriptionError = error.localizedDescription
                            }
                        }
                    } label: {
                        if isTranscribing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Transcribe")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isTranscribing)
                    .padding(.top, 8)

                    if let transcript {
                        VStack(spacing: 8) {
                            Text("Done · \(transcript.characterCount) characters")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Save Transcript…") {
                                saveTranscript(transcript)
                            }
                        }
                    }

                    if let transcriptionError {
                        Text(transcriptionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
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
            transcriptionError = nil

            Task {
                mediaInfo = await loadMediaInfo(for: url)
            }

            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .frame(minWidth: 640, minHeight: 420)
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
        } catch {
            transcriptionError = error.localizedDescription
        }
    }
}

private struct MediaInfo {
    let type: String
    let duration: String
    let fileSize: String
}
