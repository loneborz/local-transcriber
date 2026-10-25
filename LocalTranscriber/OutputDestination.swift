import AppKit
import Foundation
import Observation

enum OutputError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured: "No output folder is configured."
        }
    }
}

// The user-chosen folder that finished transcripts are written to. The folder
// is remembered across launches with a security-scoped bookmark, because the
// sandbox only grants access to a panel-selected folder for the current process.
// The app owns one instance, shared by every window and Settings.
@MainActor @Observable
final class OutputDestination {
    enum Status {
        case none
        case ready(URL)
        case unavailable(String)
    }

    private static let bookmarkKey = "outputDestinationBookmark"

    private(set) var status: Status = .none
    // Kept open while the folder is ready, so a recording saved there can be
    // read back by the queue, also after a relaunch.
    @ObservationIgnored private var accessedFolder: URL?

    init() {
        refresh()
    }

    // Every window's queue and recorder, held weakly. Busy state is computed from
    // the live objects, never stored, so a closed window cannot leave a stale
    // lock: its recorder is cancelled on close, and its queue drops out once it
    // is gone (a queue still running after its window closed keeps the lock
    // until its last save, which is when it stops writing here).
    private struct Weak<T: AnyObject> { weak var value: T? }
    private var queues: [Weak<BatchQueue>] = []
    private var recorders: [Weak<Recorder>] = []

    func register(_ queue: BatchQueue, _ recorder: Recorder) {
        queues.removeAll { $0.value == nil }
        recorders.removeAll { $0.value == nil }
        if !queues.contains(where: { $0.value === queue }) { queues.append(Weak(value: queue)) }
        if !recorders.contains(where: { $0.value === recorder }) { recorders.append(Weak(value: recorder)) }
    }

    // App-wide, across all windows.
    var isTranscribing: Bool { queues.contains { $0.value?.isProcessing == true } }
    var isRecording: Bool { recorders.contains { $0.value?.isIdle == false } }
    // Recordings that closing a window or quitting would lose (RecordingCloseGuard).
    var protectedRecorders: [Recorder] { recorders.compactMap(\.value).filter { $0.protection != nil } }

    // The folder receives job saves and the recording at Stop; the source-package
    // mode is read at each YouTube save.
    var canChangeFolder: Bool { !isTranscribing && !isRecording }
    var canChangeSourcePackage: Bool { !isTranscribing }

    isolated deinit {
        accessedFolder?.stopAccessingSecurityScopedResource()
    }

    var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    // The folder the library lists; nil unless the folder is ready.
    var readyFolder: URL? {
        if case .ready(let url) = status { url } else { nil }
    }

    // Re-resolves the persisted bookmark. Never falls back to another folder.
    func refresh() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
            hold(nil)
            status = .none
            return
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                hold(nil)
                status = .unavailable("Output folder “\(url.lastPathComponent)” is unavailable.")
                return
            }
            if isStale {
                storeBookmark(for: url)
            }
            hold(url)
            status = .ready(url)
        } catch {
            hold(nil)
            status = .unavailable("Output folder is unavailable. Choose it again.")
        }
    }

    // Holds security-scoped access to `folder` and releases what was held
    // before. A folder that is accessible without it (start returns false) is
    // simply not held.
    private func hold(_ folder: URL?) {
        let didStart = folder?.startAccessingSecurityScopedResource() ?? false
        accessedFolder?.stopAccessingSecurityScopedResource()
        accessedFolder = didStart ? folder : nil
    }

    // An existing folder can still refuse files (read-only volume,
    // permissions, lost sandbox access); only a real write proves it doesn't.
    func checkWritable() throws {
        guard case .ready(let folder) = status else { throw OutputError.notConfigured }

        let didStart = folder.startAccessingSecurityScopedResource()
        defer { if didStart { folder.stopAccessingSecurityScopedResource() } }

        let probe = folder.appendingPathComponent(".LocalTranscriber-\(UUID().uuidString)")
        try Data().write(to: probe, options: .withoutOverwriting)
        try? FileManager.default.removeItem(at: probe)
    }

    // Folder-only picker. Returns true when a folder was chosen and remembered.
    // Every entry point comes through here, so the app-wide guard lives here.
    @discardableResult
    func choose() -> Bool {
        guard canChangeFolder else { return false }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where transcripts are saved."
        if case .ready(let current) = status {
            panel.directoryURL = current
        }

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        if let error = storeBookmark(for: url) {
            hold(nil)
            status = .unavailable("Couldn’t remember that folder: \(error.localizedDescription)")
            return false
        }
        hold(url)
        status = .ready(url)
        return true
    }

    // Writes a finished transcript as a new entry folder (see LibraryOperations).
    // Into the folder of a recording when `existingFolder` is given. Never
    // overwrites or reuses an existing file or folder.
    func writeEntry(
        baseName: String,
        existingFolder: URL?,
        markdown: String,
        createdAt: Date,
        audio: URL?,
        manifest: Data?
    ) throws -> LibraryOperations.WrittenEntry {
        guard case .ready(let folder) = status else { throw OutputError.notConfigured }

        let didStart = folder.startAccessingSecurityScopedResource()
        defer { if didStart { folder.stopAccessingSecurityScopedResource() } }

        do {
            return try LibraryOperations.writeEntry(
                baseName: baseName, in: folder, existingFolder: existingFolder, markdown: markdown,
                createdAt: createdAt, audio: audio, manifest: manifest)
        } catch {
            refresh()
            throw error
        }
    }

    // Writes the timing sidecar for a Markdown file this destination placed (see
    // SidecarFile for the naming and the no-overwrite rule). Never replaces a file.
    func writeSidecar(_ data: Data, besides markdownURL: URL) throws -> URL {
        guard case .ready(let folder) = status else { throw OutputError.notConfigured }

        let didStart = folder.startAccessingSecurityScopedResource()
        defer { if didStart { folder.stopAccessingSecurityScopedResource() } }

        return try SidecarFile.write(data, besides: markdownURL)
    }

    // Moves a finished recording out of app-local staging into a new entry
    // folder of its own, where its transcript is added later. Returns the audio.
    func saveRecording(_ stagedFile: URL, baseName: String, startedAt: Date) throws -> URL {
        guard case .ready(let folder) = status else { throw OutputError.notConfigured }

        let didStart = folder.startAccessingSecurityScopedResource()
        defer { if didStart { folder.stopAccessingSecurityScopedResource() } }

        do {
            return try LibraryOperations.saveRecording(stagedFile, baseName: baseName, in: folder, startedAt: startedAt)
        } catch {
            refresh()
            throw error
        }
    }

    @discardableResult
    private func storeBookmark(for url: URL) -> Error? {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            return nil
        } catch {
            return error
        }
    }
}
