import Foundation
import Observation
import os

// The in-memory result of scanning the output folder. It is rebuilt on demand
// and kept nowhere: no database, no index file, nothing written. The folder is
// the store (doc-3); this is only the last listing of it.
extension Notification.Name {
    // Posted by a store after it changed files, so other windows rescan.
    static let libraryDidChange = Notification.Name("LocalTranscriber.libraryDidChange")
}

@MainActor @Observable
final class LibraryStore {
    private(set) var items: [LibraryTranscript] = []
    // The organization folders, empty ones included.
    private(set) var folders: [LibraryFolder] = []
    // Where `items` came from; nil when there is no usable output folder.
    private(set) var folder: URL?
    // Set when the folder could not be listed (items are then empty).
    private(set) var loadError: String?
    private(set) var isLoading = false
    // Counts finished scans (success or failure), so a view can react to "the
    // library now reflects the disk" without comparing lists.
    private(set) var revision = 0

    @ObservationIgnored private var generation = 0
    private static let log = Logger(subsystem: "nl.wavesweb.LocalTranscriber", category: "library")

    // Rescans `newFolder` off the main thread. A different folder empties the
    // list at once, so another folder's transcripts are never shown under the
    // new folder's status. Only the newest request applies its result.
    func refresh(folder newFolder: URL?) {
        generation += 1
        let request = generation

        if newFolder != folder {
            items = []
            folders = []
            loadError = nil
        }
        folder = newFolder

        guard let newFolder else {
            isLoading = false
            loadError = nil
            return
        }

        isLoading = true
        Task.detached(priority: .userInitiated) {
            let started = ContinuousClock.now
            let result = Result { try LibraryScanner.scanLibrary(folder: newFolder) }
            let elapsed = started.duration(to: .now)
            await self.apply(result, request: request, elapsed: elapsed)
        }
    }

    private func apply(
        _ result: Result<LibraryListing, Error>,
        request: Int,
        elapsed: Duration
    ) {
        guard request == generation else { return }
        isLoading = false
        defer { revision += 1 }
        switch result {
        case .success(let scanned):
            items = scanned.items
            folders = scanned.folders
            loadError = nil
            let milliseconds = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
            Self.log.info("library scan: \(scanned.items.count, privacy: .public) transcripts in \(milliseconds, format: .fixed(precision: 1), privacy: .public) ms")
        case .failure(let error):
            items = []
            folders = []
            loadError = error.localizedDescription
            Self.log.error("library scan failed: \(error.localizedDescription)")
        }
    }

    // MARK: changing the library
    //
    // Each action changes files (see LibraryOperations), shows the result at once
    // and lets a rescan and the other windows confirm it. A failure throws and
    // changes nothing.

    var sections: LibrarySections { LibrarySections(LibraryListing(items: items, folders: folders)) }

    @discardableResult
    func rename(_ item: LibraryTranscript, to name: String) throws -> LibraryTranscript {
        replace(item, with: try LibraryOperations.rename(item, to: name))
    }

    func setPinned(_ item: LibraryTranscript, _ pinned: Bool) throws {
        replace(item, with: try LibraryOperations.setPinned(item, pinned))
    }

    // Opening a transcript clears its New badge, here and (by notification) in every window.
    func markOpened(_ item: LibraryTranscript) throws {
        guard item.isNew else { return }
        replace(item, with: try LibraryOperations.markOpened(item))
    }

    func setArchived(_ item: LibraryTranscript, _ archived: Bool) throws {
        replace(item, with: try LibraryOperations.setArchived(item, archived))
    }

    // `destination` is an organization folder, or nil for the top level.
    @discardableResult
    func move(_ item: LibraryTranscript, to destination: LibraryFolder?) throws -> LibraryTranscript {
        guard let folder else { throw LibraryError.outsideLibrary }
        return replace(item, with: try LibraryOperations.move(item, to: destination?.url ?? folder, root: folder))
    }

    func trash(_ item: LibraryTranscript) throws {
        try LibraryOperations.trash(item)
        items.removeAll { $0.id == item.id }
        changed()
    }

    // Renames the folder and shows its transcripts at their new paths at once.
    func renameFolder(_ folder: LibraryFolder, to name: String) throws -> LibraryFolder {
        let renamed = try LibraryOperations.renameFolder(folder, to: name)
        let old = folder.url.path, new = renamed.url.path
        items = items.map { item in
            guard item.markdownURL.path.hasPrefix(old + "/") else { return item }
            var moved = item
            moved.markdownURL = URL(fileURLWithPath: new + String(item.markdownURL.path.dropFirst(old.count)))
            moved.group = item.group == nil ? nil : renamed.url
            return moved
        }
        folders = folders.map { $0.id == folder.id ? renamed : $0 }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        changed()
        return renamed
    }

    func trashFolder(_ folder: LibraryFolder) throws {
        try LibraryOperations.trashFolder(folder)
        items.removeAll { $0.markdownURL.path.hasPrefix(folder.url.path + "/") }
        folders.removeAll { $0.id == folder.id }
        changed()
    }

    func createFolder(named name: String) throws -> LibraryFolder {
        guard let folder else { throw LibraryError.outsideLibrary }
        let created = try LibraryOperations.createOrganizationFolder(named: name, in: folder)
        folders.append(created)
        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        changed()
        return created
    }

    @discardableResult
    private func replace(_ old: LibraryTranscript, with new: LibraryTranscript) -> LibraryTranscript {
        items.removeAll { $0.id == old.id }
        items.append(new)
        items.sort(by: LibraryScanner.isOrderedBefore)
        changed()
        return new
    }

    private func changed() {
        refresh(folder: folder)
        NotificationCenter.default.post(name: .libraryDidChange, object: self)
    }
}
