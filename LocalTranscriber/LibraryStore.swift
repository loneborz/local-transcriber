import Foundation
import Observation
import os

// The in-memory result of scanning the output folder. It is rebuilt on demand
// and kept nowhere: no database, no index file, nothing written. The folder is
// the store (doc-3); this is only the last listing of it.
@MainActor @Observable
final class LibraryStore {
    private(set) var items: [LibraryTranscript] = []
    // Where `items` came from; nil when there is no usable output folder.
    private(set) var folder: URL?
    // Set when the folder could not be listed (items are then empty).
    private(set) var loadError: String?
    private(set) var isLoading = false
    // Saved jobs find their library entry here.
    private(set) var joinIndex: LibraryJoin.Index = [:]
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
            joinIndex = [:]
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
            let result = Result { try LibraryScanner.scan(folder: newFolder) }
            let elapsed = started.duration(to: .now)
            let index = (try? result.get()).map(LibraryJoin.index) ?? [:]
            await self.apply(result, index: index, request: request, elapsed: elapsed)
        }
    }

    private func apply(
        _ result: Result<[LibraryTranscript], Error>,
        index: LibraryJoin.Index,
        request: Int,
        elapsed: Duration
    ) {
        guard request == generation else { return }
        isLoading = false
        defer { revision += 1 }
        switch result {
        case .success(let scanned):
            items = scanned
            joinIndex = index
            loadError = nil
            let milliseconds = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
            Self.log.info("library scan: \(scanned.count, privacy: .public) transcripts in \(milliseconds, format: .fixed(precision: 1), privacy: .public) ms")
        case .failure(let error):
            items = []
            joinIndex = [:]
            loadError = error.localizedDescription
            Self.log.error("library scan failed: \(error.localizedDescription)")
        }
    }
}
