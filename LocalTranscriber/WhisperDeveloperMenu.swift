#if DEBUG
import AppKit
import SwiftUI

// Debug builds only: installs the Whisper model from a local folder (one that
// holds openai_whisper-large-v3-v20240930_turbo), so tests reuse a verified copy
// instead of downloading. The files go through the same staging and checksum
// verification as the download in Settings.
struct WhisperDeveloperMenu: Commands {
    var body: some Commands {
        CommandMenu("Developer") {
            Button("Install Whisper Model from Folder…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.message = "Choose a folder that contains \(WhisperModelManifest.modelName)"
                guard panel.runModal() == .OK, let source = panel.url else { return }
                WhisperModelStore.shared.install(fromFolder: source)
            }
        }
    }
}
#endif
