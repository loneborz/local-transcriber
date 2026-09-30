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

    init() {
        refresh()
    }

    var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    // Re-resolves the persisted bookmark. Never falls back to another folder.
    func refresh() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
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
                status = .unavailable("Output folder “\(url.lastPathComponent)” is unavailable.")
                return
            }
            if isStale {
                storeBookmark(for: url)
            }
            status = .ready(url)
        } catch {
            status = .unavailable("Output folder is unavailable. Choose it again.")
        }
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
            status = .unavailable("Couldn’t remember that folder: \(error.localizedDescription)")
            return false
        }
        status = .ready(url)
        return true
    }

    // Writes `<baseName>.md`, or `<baseName> 2.md`, `<baseName> 3.md`, … when
    // the name is taken. Existing files are never overwritten.
    func write(_ markdown: String, baseName: String) throws -> URL {
        guard case .ready(let folder) = status else { throw OutputError.notConfigured }

        let didStart = folder.startAccessingSecurityScopedResource()
        defer { if didStart { folder.stopAccessingSecurityScopedResource() } }

        let data = Data(markdown.utf8)
        for attempt in 1...9999 {
            let name = attempt == 1 ? "\(baseName).md" : "\(baseName) \(attempt).md"
            let url = folder.appendingPathComponent(name)
            do {
                // Foundation traps if .withoutOverwriting is combined with .atomic.
                try data.write(to: url, options: .withoutOverwriting)
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
