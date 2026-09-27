import SwiftUI

struct ContentView: View {
    @State private var selectedFile: URL?
    @State private var isTargeted = false

    private let supportedExtensions = [
        "mp4",
        "mov",
        "m4a",
        "mp3",
        "wav"
    ]

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: selectedFile == nil ? "waveform.badge.plus" : "checkmark.circle.fill")
                .font(.system(size: 42, weight: .light))

            if let selectedFile {
                VStack(spacing: 8) {
                    Text(selectedFile.lastPathComponent)
                        .font(.title3.weight(.medium))

                    Text(selectedFile.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
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

            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                return false
            }

            selectedFile = url
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}
