import Foundation

// What a job was created from.
nonisolated enum JobSource {
    case file(URL)
    case youtube(videoID: String, url: URL)
}

// An input that waits for its language (LTR-72). Session only: an imported file
// that was not started is forgotten on quit. A recording's audio is already saved
// in its entry folder, and the library offers it again after a relaunch (`offer`).
nonisolated struct PendingInput: Identifiable {
    let id = UUID()
    let source: JobSource
    let recording: (folder: URL, startedAt: Date)?
    // Apple Speech unless the user picks Whisper for this input (D1).
    var engine = TranscriptionEngine.appleSpeech

    var name: String {
        switch source {
        case .file(let url): url.lastPathComponent
        case .youtube(let videoID, _): "YouTube · \(videoID)"
        }
    }
}

nonisolated extension [PendingInput] {
    // Changes the engine of an input that still waits. One that has become a job
    // is no longer here, so its job keeps the engine it started with.
    mutating func setEngine(_ engine: TranscriptionEngine, for id: PendingInput.ID) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].engine = engine
    }

    // Removes and returns the input, as configured, when it is started.
    mutating func take(_ id: PendingInput.ID) -> PendingInput? {
        firstIndex(where: { $0.id == id }).map { remove(at: $0) }
    }
}
