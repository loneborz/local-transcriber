import AppKit
import Foundation
import Observation

enum OutputError: LocalizedError {
    case notConfigured
    case tooManyCollisions

    var errorDescription: String? {
        switch self {
        case .notConfigured: "No output folder is configured."
        case .tooManyCollisions: "Too many files with this name already exist."
        }
    }
}

// The user-chosen folder that finished transcripts are written to. The folder
// is remembered across launches with a security-scoped bookmark, because the
// sandbox only grants access to a panel-selected folder for the current process.
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

    isolated deinit {
        accessedFolder?.stopAccessingSecurityScopedResource()
    }

    var isReady: Bool {
        if case .ready = status { return true }
        return false
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
    @discardableResult
    func choose() -> Bool {
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

    // Writes `<baseName>.md`, or `<baseName> 2.md`, `<baseName> 3.md`, … when
    // the name is taken. Existing files are never overwritten.
    func write(_ markdown: String, baseName: String) throws -> URL {
        let data = Data(markdown.utf8)
        return try placeWithoutOverwriting(baseName: baseName, pathExtension: "md") {
            // Foundation traps if .withoutOverwriting is combined with .atomic.
            try data.write(to: $0, options: .withoutOverwriting)
        }
    }

    // Moves a finished recording out of app-local staging under the same
    // naming rule. moveItem never replaces an existing file.
    func saveRecording(_ stagedFile: URL, baseName: String) throws -> URL {
        try placeWithoutOverwriting(baseName: baseName, pathExtension: stagedFile.pathExtension) {
            try FileManager.default.moveItem(at: stagedFile, to: $0)
        }
    }

    // Calls `place` with `<baseName>.<ext>`, then `<baseName> 2.<ext>`, … until
    // it does not fail because the file already exists.
    private func placeWithoutOverwriting(
        baseName: String,
        pathExtension: String,
        _ place: (URL) throws -> Void
    ) throws -> URL {
        guard case .ready(let folder) = status else { throw OutputError.notConfigured }

        let didStart = folder.startAccessingSecurityScopedResource()
        defer { if didStart { folder.stopAccessingSecurityScopedResource() } }

        for attempt in 1...9999 {
            let name = attempt == 1 ? baseName : "\(baseName) \(attempt)"
            let url = folder.appendingPathComponent("\(name).\(pathExtension)")
            do {
                try place(url)
                return url
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            } catch {
                refresh()
                throw error
            }
        }
        throw OutputError.tooManyCollisions
    }

    // Writes a source package: a new `<videoID>/` folder holding the audio,
    // `source.json` and `transcript.md`. An existing folder is never reused or
    // overwritten; the next free `<videoID> 2`, `<videoID> 3`, … is created
    // instead. If any step fails, the folder created here is removed again so
    // no half-written package is left behind.
    func writePackage(videoID: String, audio: URL, manifest: Data, transcript: String) throws -> URL {
        guard case .ready(let folder) = status else { throw OutputError.notConfigured }

        let didStart = folder.startAccessingSecurityScopedResource()
        defer { if didStart { folder.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        for attempt in 1...9999 {
            let name = attempt == 1 ? videoID : "\(videoID) \(attempt)"
            let package = folder.appendingPathComponent(name, isDirectory: true)
            do {
                try fileManager.createDirectory(at: package, withIntermediateDirectories: false)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            } catch {
                refresh()
                throw error
            }

            do {
                try fileManager.copyItem(
                    at: audio,
                    to: package.appendingPathComponent(SourcePackageManifest.audioFilename)
                )
                try manifest.write(
                    to: package.appendingPathComponent(SourcePackageManifest.manifestFilename),
                    options: .withoutOverwriting
                )
                try Data(transcript.utf8).write(
                    to: package.appendingPathComponent(SourcePackageManifest.transcriptFilename),
                    options: .withoutOverwriting
                )
                return package
            } catch {
                try? fileManager.removeItem(at: package)
                refresh()
                throw error
            }
        }
        throw OutputError.tooManyCollisions
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
