#if DEBUG
import AppKit
import SwiftUI

// Debug builds only (LTR-76 phase 1): routes new jobs to Whisper and copies a
// local model folder into the container. This is not the user-facing engine
// choice or model installation; both are still open (doc-3 Addendum 7 F).
struct WhisperDeveloperMenu: Commands {
    static let engineKey = "developerTranscribeWithWhisper"
    @AppStorage(engineKey) private var transcribeWithWhisper = false

    var body: some Commands {
        CommandMenu("Developer") {
            Toggle("Transcribe New Jobs with Whisper", isOn: $transcribeWithWhisper)
            Button("Install Whisper Model from Folder…") { install() }
        }
    }

    // The chosen folder must have the layout of WhisperTranscriptionService.folder
    // (the model folder and tokenizer/). It replaces the container's copy; on
    // APFS the copy is a clone, so it is instant and takes no extra space.
    private func install() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Choose a folder with \(WhisperTranscriptionService.transcriber.rawValue) and tokenizer"
        guard panel.runModal() == .OK, let source = panel.url else { return }

        let target = WhisperTranscriptionService.folder
        let alert = NSAlert()
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
            alert.messageText = "Whisper model installed"
            alert.informativeText = target.path
        } catch {
            alert.messageText = "Whisper model not installed"
            alert.informativeText = error.localizedDescription
        }
        alert.runModal()
    }
}
#endif
