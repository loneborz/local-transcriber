import Foundation
import Observation
import os

// The one Whisper Large V3 Turbo installation of this app (doc-3 Addendum 8,
// D2-D4, D8). It lives in the app's own container:
//
//   Library/Application Support/Whisper/
//     openai_whisper-large-v3-v20240930_turbo/   the installed model (WhisperModelManifest)
//     .staging/openai_whisper-large-v3-v20240930_turbo/   files being downloaded
//
// Nothing is downloaded unless the user starts it. Every file is checked against
// its pinned SHA-256 in the staging folder, and the folder is moved into place
// only when all files passed, so a partial or failed download is never Installed.
// Verified files stay in the staging folder, so a new attempt fetches only the rest.
@MainActor @Observable
final class WhisperModelStore {
    static let shared = WhisperModelStore(folder: URL.applicationSupportDirectory.appending(path: "Whisper", directoryHint: .isDirectory))

    enum State: Equatable {
        case notInstalled
        case downloading(received: Int64, total: Int64)
        case verifying
        case installed
        case failed(String)
    }

    private(set) var state: State = .notInstalled
    // A job is loading the model; the first load compiles it for this Mac (D8).
    private(set) var isPreparing = false
    // Loaded at least once on this macOS build, so the next load needs no compile.
    private(set) var isPrepared = false
    // Whether a waiting or running Whisper job still needs the model. BatchQueue,
    // which owns the jobs, answers; a job stays unsettled until its transcription
    // has returned, whether it succeeded or failed.
    var jobsNeedModel: () -> Bool = { false }

    // Application Support/Whisper for the app; a scratch folder and a small
    // manifest in tests.
    let folder: URL
    private let files: [WhisperModelManifest.File]
    private let defaults: UserDefaults
    var modelFolder: URL { folder.appending(path: WhisperModelManifest.modelName, directoryHint: .isDirectory) }
    var stagingFolder: URL {
        folder.appending(path: ".staging", directoryHint: .isDirectory)
            .appending(path: WhisperModelManifest.modelName, directoryHint: .isDirectory)
    }
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    private static let preparedKey = "whisperPreparedOnOSBuild"
    private static let log = Logger(subsystem: "nl.wavesweb.LocalTranscriber", category: "whisper")

    private var work: Task<Void, Never>?
    private var activeDownload: URLSessionDownloadTask?

    init(folder: URL, files: [WhisperModelManifest.File] = WhisperModelManifest.files, defaults: UserDefaults = .standard) {
        self.folder = folder
        self.files = files
        self.defaults = defaults
        refresh()
    }

    var isInstalled: Bool { state == .installed }
    var isBusy: Bool {
        switch state {
        case .downloading, .verifying: true
        default: false
        }
    }

    // Removal is refused while this is true.
    var isInUse: Bool { isBusy || isPreparing || jobsNeedModel() }

    func refresh() {
        guard !isBusy else { return }
        let isComplete = WhisperModelManifest.isComplete(at: modelFolder, files: files)
        // A failure's reason stays until a new attempt replaces it or the model appears (LTR-84).
        if case .failed = state, !isComplete { return }
        state = isComplete ? .installed : .notInstalled
        isPrepared = state == .installed
            && defaults.string(forKey: Self.preparedKey) == ProcessInfo.processInfo.operatingSystemVersionString
    }

    // Queue admission asks here (LTR-82): whether the model counts as installed and
    // its files are still there now. Narrower than refresh(): the only change is a
    // stale Installed, removed outside the app, becoming Not Installed, so the
    // guidance shows.
    func verifyInstalled() -> Bool {
        guard state == .installed else { return false }
        if WhisperModelManifest.isComplete(at: modelFolder, files: files) { return true }
        state = .notInstalled
        isPrepared = false
        return false
    }

    // Space the installed files take on disk (allocated blocks). An APFS clone
    // shares blocks with its original, so the space a removal frees can be smaller.
    var diskUsage: Int64? {
        guard state == .installed,
              let items = FileManager.default.enumerator(at: modelFolder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        else { return nil }
        var total: Int64 = 0
        for case let url as URL in items {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: Install

    // Downloads the pinned files from Hugging Face (D4). Started only by the user.
    func download() {
        install { file, destination, report in
            try await Self.fetch(WhisperModelManifest.remoteURL(for: file), to: destination, report: report) { task in
                await MainActor.run { self.activeDownload = task }
            }
        }
    }

    // Copies the files from a local folder that holds the model folder (Debug
    // builds, for testing). The same verification applies.
    func install(fromFolder source: URL) {
        install { file, destination, report in
            let from = source.appending(path: WhisperModelManifest.modelName).appending(path: file.path)
            try FileManager.default.copyItem(at: from, to: destination)
            report(file.size)
        }
    }

    func cancel() {
        work?.cancel()
        activeDownload?.cancel()
    }

    typealias Fetch = (WhisperModelManifest.File, URL, @escaping @Sendable (Int64) -> Void) async throws -> Void

    // Internal (not private) so tests can pass their own fetch.
    func install(_ fetch: @escaping Fetch) {
        guard !isBusy, state != .installed else { return }
        let total = totalBytes
        state = .downloading(received: 0, total: total)
        let (files, staging, model) = (files, stagingFolder, modelFolder)
        work = Task {
            do {
                try await Self.stageAndPromote(files, staging: staging, model: model, fetch) { received in
                    Task { @MainActor in
                        if case .downloading = self.state {
                            self.state = .downloading(received: received, total: total)
                        }
                    }
                } verifying: {
                    await MainActor.run { self.state = .verifying }
                }
                state = .installed
                isPrepared = false
            } catch is CancellationError {
                state = .notInstalled
            } catch let error as URLError where error.code == .cancelled {
                state = .notInstalled
            } catch {
                Self.log.error("install failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(error.localizedDescription)
            }
            activeDownload = nil
            work = nil
        }
    }

    @concurrent
    private nonisolated static func stageAndPromote(
        _ files: [WhisperModelManifest.File],
        staging stagingFolder: URL,
        model modelFolder: URL,
        _ fetch: Fetch,
        progress: @escaping @Sendable (Int64) -> Void,
        verifying: @Sendable () async -> Void
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        var done: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let staged = stagingFolder.appending(path: file.path)
            // A file verified by an earlier, interrupted attempt is kept.
            if (try? WhisperModelManifest.matches(staged, file)) == true {
                done += file.size
                progress(done)
                continue
            }
            try? fileManager.removeItem(at: staged)
            try fileManager.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
            let base = done
            try await fetch(file, staged) { progress(base + $0) }
            guard try WhisperModelManifest.matches(staged, file) else {
                try? fileManager.removeItem(at: staged)
                throw WhisperModelError.checksumMismatch(file.path)
            }
            done += file.size
            progress(done)
        }
        await verifying()
        try prune(stagingFolder, keeping: files)
        guard WhisperModelManifest.isComplete(at: stagingFolder, files: files) else { throw WhisperModelError.incomplete }
        // Same volume, so the move is a rename: the model appears complete or not at all.
        try? fileManager.removeItem(at: modelFolder)
        try fileManager.moveItem(at: stagingFolder, to: modelFolder)
        try? fileManager.removeItem(at: stagingFolder.deletingLastPathComponent())
    }

    // Deletes everything in the staging folder that is not a pinned file or a folder
    // above one, such as a partial ".download" left by an interrupted attempt, so
    // only the pinned files move into place.
    private nonisolated static func prune(_ staging: URL, keeping files: [WhisperModelManifest.File]) throws {
        let kept = Set(files.flatMap { file in
            let parts = file.path.split(separator: "/")
            return (1...parts.count).map { parts.prefix($0).joined(separator: "/") }
        })
        guard let items = FileManager.default.enumerator(atPath: staging.path) else { return }
        for case let path as String in items where !kept.contains(path) {
            try FileManager.default.removeItem(at: staging.appending(path: path))
            items.skipDescendants()
        }
    }

    // One file over URLSession, reporting bytes received. The redirect to the CDN is followed.
    private nonisolated static func fetch(
        _ url: URL,
        to destination: URL,
        report: @escaping @Sendable (Int64) -> Void,
        started: @escaping @Sendable (URLSessionDownloadTask) async -> Void
    ) async throws {
        // The task's Progress does not report while a large file arrives, so the
        // received byte count is polled instead.
        final class Poll: @unchecked Sendable { var task: Task<Void, Never>? }
        let poll = Poll()
        let downloaded: URL = try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { location, response, error in
                poll.task?.cancel()
                if let error { return continuation.resume(throwing: error) }
                guard let location, let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    return continuation.resume(throwing: WhisperModelError.http((response as? HTTPURLResponse)?.statusCode ?? 0))
                }
                // The system deletes `location` when this handler returns.
                let kept = destination.appendingPathExtension("download")
                do {
                    try? FileManager.default.removeItem(at: kept)
                    try FileManager.default.moveItem(at: location, to: kept)
                    continuation.resume(returning: kept)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            task.resume()
            poll.task = Task {
                await started(task)
                while !Task.isCancelled {
                    report(task.countOfBytesReceived)
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
        try FileManager.default.moveItem(at: downloaded, to: destination)
    }

    // MARK: Remove

    // Deletes the installed model and any staged files, nothing else (D3). The
    // caller confirms first; refused while installing or while a job needs the model.
    func remove() throws {
        guard !isInUse else { throw WhisperModelError.inUse }
        // Never follow a link that points elsewhere.
        guard (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true
        else { throw WhisperModelError.unexpectedLocation(folder.path) }
        for item in [modelFolder, stagingFolder.deletingLastPathComponent()]
        where FileManager.default.fileExists(atPath: item.path) {
            // removeItem deletes links inside the folder, not what they point to.
            try FileManager.default.removeItem(at: item)
        }
        defaults.removeObject(forKey: Self.preparedKey)
        isPrepared = false
        state = .notInstalled
    }

    // MARK: Preparation (called by WhisperTranscriptionService)

    func preparationStarted() { isPreparing = true }

    func preparationEnded(succeeded: Bool) {
        isPreparing = false
        if succeeded {
            defaults.set(ProcessInfo.processInfo.operatingSystemVersionString, forKey: Self.preparedKey)
            isPrepared = true
        }
    }
}

enum WhisperModelError: LocalizedError {
    case checksumMismatch(String)
    case incomplete
    case http(Int)
    case unexpectedLocation(String)
    case inUse

    var errorDescription: String? {
        switch self {
        case .checksumMismatch(let path):
            "The downloaded file \(path) doesn’t match its checksum, so it was deleted. Try again."
        case .incomplete:
            "The download is incomplete. Try again."
        case .http(let status):
            "The model server answered with status \(status). Try again later."
        case .unexpectedLocation(let path):
            "The Whisper folder at \(path) is not where the app keeps it, so nothing was removed."
        case .inUse:
            "Whisper Large V3 Turbo is being installed or is needed by a waiting or running transcription. Try again when that has finished."
        }
    }
}
