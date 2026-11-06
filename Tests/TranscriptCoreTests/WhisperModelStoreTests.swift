import CryptoKit
import Observation
import XCTest
@testable import TranscriptCore

// WhisperModelStore on a scratch folder with a three-file manifest: no network,
// no real model (LTR-76).
final class WhisperModelStoreTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private let contents = ["Encoder.mlmodelc/weights/weight.bin": "weights", "Encoder.mlmodelc/metadata.json": "{}", "config.json": "config"]
    private var files: [WhisperModelManifest.File] {
        contents.keys.sorted().map { path in
            let data = Data(contents[path]!.utf8)
            return .init(path: path, size: Int64(data.count), sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        }
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "WhisperStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "WhisperStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeStore(_ folder: URL? = nil) -> WhisperModelStore {
        WhisperModelStore(folder: folder ?? root.appending(path: "Whisper"), files: files, defaults: defaults)
    }

    // A folder holding the model folder, as the Developer menu's install expects.
    private func source(corrupting corrupt: String? = nil, omitting omit: String? = nil) throws -> URL {
        let source = root.appending(path: "source-\(UUID().uuidString)")
        for (path, text) in contents where path != omit {
            let url = source.appending(path: WhisperModelManifest.modelName).appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((path == corrupt ? text + "!" : text).utf8).write(to: url)
        }
        return source
    }

    private func settle(_ store: WhisperModelStore) async throws {
        for _ in 0..<2000 where store.isBusy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(store.isBusy, "install did not finish")
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func testFreshFolderIsNotInstalled() {
        let store = makeStore()
        XCTAssertEqual(store.state, .notInstalled)
        XCTAssertFalse(store.isPrepared)
        XCTAssertNil(store.diskUsage)
    }

    func testSuccessfulInstallPassesDownloadingAndVerifying() async throws {
        let store = makeStore()
        var states: [WhisperModelStore.State] = []
        func track() {
            withObservationTracking { _ = store.state } onChange: {
                Task { @MainActor in states.append(store.state); track() }
            }
        }
        track()
        store.install(fromFolder: try source())
        XCTAssertEqual(store.state, .downloading(received: 0, total: store.totalBytes))
        try await settle(store)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(store.state, .installed)
        XCTAssertTrue(states.contains(.verifying), "\(states)")
        XCTAssertTrue(states.contains(.downloading(received: store.totalBytes, total: store.totalBytes)), "\(states)")
        XCTAssertTrue(WhisperModelManifest.isComplete(at: store.modelFolder, files: files))
        XCTAssertFalse(exists(store.folder.appending(path: ".staging")))
        XCTAssertGreaterThan(store.diskUsage ?? 0, 0)
        // Installed once on this OS build only after its first load (Preparing).
        XCTAssertFalse(store.isPrepared)
    }

    func testChecksumMismatchFailsWithoutPromotingAndKeepsVerifiedFiles() async throws {
        let store = makeStore()
        store.install(fromFolder: try source(corrupting: "Encoder.mlmodelc/weights/weight.bin"))
        try await settle(store)
        guard case .failed(let message) = store.state else { return XCTFail("\(store.state)") }
        XCTAssertTrue(message.contains("Encoder.mlmodelc/weights/weight.bin"), message)
        XCTAssertTrue(message.contains("checksum"), message)
        XCTAssertFalse(exists(store.modelFolder))
        // Manifest order: metadata.json was verified before the bad file and stays
        // staged; the bad file is deleted; config.json was never fetched.
        XCTAssertTrue(exists(store.stagingFolder.appending(path: "Encoder.mlmodelc/metadata.json")))
        XCTAssertFalse(exists(store.stagingFolder.appending(path: "Encoder.mlmodelc/weights/weight.bin")))
        XCTAssertFalse(exists(store.stagingFolder.appending(path: "config.json")))
        // A relaunch does not take the failed attempt for an installation.
        XCTAssertEqual(makeStore().state, .notInstalled)
    }

    func testMissingSourceFileFails() async throws {
        let store = makeStore()
        store.install(fromFolder: try source(omitting: "config.json"))
        try await settle(store)
        guard case .failed = store.state else { return XCTFail("\(store.state)") }
        XCTAssertFalse(exists(store.modelFolder))
    }

    func testRecoveryAfterFailureFetchesOnlyWhatIsMissing() async throws {
        let store = makeStore()
        store.install(fromFolder: try source(corrupting: "Encoder.mlmodelc/weights/weight.bin"))
        try await settle(store)
        guard case .failed = store.state else { return XCTFail("\(store.state)") }

        let good = try source()
        let fetched = Fetched()
        store.install { file, destination, report in
            fetched.paths.append(file.path)
            try FileManager.default.copyItem(at: good.appending(path: WhisperModelManifest.modelName).appending(path: file.path), to: destination)
            report(file.size)
        }
        try await settle(store)
        XCTAssertEqual(store.state, .installed)
        XCTAssertEqual(fetched.paths, ["Encoder.mlmodelc/weights/weight.bin", "config.json"])
    }

    func testInterruptedDownloadIsNotInstalledAndResumes() async throws {
        let store = makeStore()
        let good = try source()
        let started = Fetched()
        store.install { file, destination, report in
            started.paths.append(file.path)
            if file.path == "Encoder.mlmodelc/weights/weight.bin" {
                try await Task.sleep(for: .seconds(30))   // cancelled below
            }
            try FileManager.default.copyItem(at: good.appending(path: WhisperModelManifest.modelName).appending(path: file.path), to: destination)
        }
        for _ in 0..<1000 where !started.paths.contains("Encoder.mlmodelc/weights/weight.bin") { try await Task.sleep(for: .milliseconds(5)) }
        store.cancel()
        try await settle(store)
        XCTAssertEqual(store.state, .notInstalled)
        XCTAssertFalse(exists(store.modelFolder))
        XCTAssertEqual(makeStore().state, .notInstalled)

        // A URLSession cancellation counts the same.
        store.install { _, _, _ in throw URLError(.cancelled) }
        try await settle(store)
        XCTAssertEqual(store.state, .notInstalled)

        store.install(fromFolder: good)
        try await settle(store)
        XCTAssertEqual(store.state, .installed)
    }

    func testIncompleteInstallationAfterRelaunchIsNotInstalled() throws {
        let store = makeStore()
        let good = try source().appending(path: WhisperModelManifest.modelName)
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: good, to: store.modelFolder)
        XCTAssertEqual(makeStore().state, .installed)

        // A file missing.
        try FileManager.default.removeItem(at: store.modelFolder.appending(path: "config.json"))
        XCTAssertEqual(makeStore().state, .notInstalled)
        // A file of the wrong size.
        try Data("configuration".utf8).write(to: store.modelFolder.appending(path: "config.json"))
        XCTAssertEqual(makeStore().state, .notInstalled)
        // Only a staging folder.
        try FileManager.default.removeItem(at: store.modelFolder)
        try FileManager.default.createDirectory(at: store.stagingFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: good, to: store.stagingFolder)
        XCTAssertEqual(makeStore().state, .notInstalled)
    }

    func testInstallingOverAnInstalledModelDoesNothing() async throws {
        let store = makeStore()
        store.install(fromFolder: try source())
        try await settle(store)
        store.install(fromFolder: try source(corrupting: "config.json"))
        XCTAssertEqual(store.state, .installed)
        XCTAssertTrue(try WhisperModelManifest.matches(store.modelFolder.appending(path: "config.json"), files.first { $0.path == "config.json" }!))
    }

    func testPreparingThenReadySurvivesRelaunchAndRemoval() async throws {
        let store = makeStore()
        store.install(fromFolder: try source())
        try await settle(store)
        store.preparationStarted()
        XCTAssertTrue(store.isPreparing)
        store.preparationEnded(succeeded: false)
        XCTAssertFalse(store.isPreparing)
        XCTAssertFalse(store.isPrepared)
        store.preparationStarted()
        store.preparationEnded(succeeded: true)
        XCTAssertTrue(store.isPrepared)
        XCTAssertTrue(makeStore().isPrepared)
        try store.remove()
        XCTAssertFalse(store.isPrepared)
        XCTAssertFalse(makeStore().isPrepared)
    }

    func testRemovalDeletesOnlyTheModelAndStaging() async throws {
        let store = makeStore()
        store.install(fromFolder: try source())
        try await settle(store)
        try FileManager.default.createDirectory(at: store.stagingFolder, withIntermediateDirectories: true)
        let neighbour = store.folder.appending(path: "notes.txt")
        try Data("keep".utf8).write(to: neighbour)
        let transcript = root.appending(path: "Transcript.md")
        try Data("keep".utf8).write(to: transcript)

        try store.remove()
        XCTAssertEqual(store.state, .notInstalled)
        XCTAssertFalse(exists(store.modelFolder))
        XCTAssertFalse(exists(store.folder.appending(path: ".staging")))
        XCTAssertTrue(exists(neighbour))
        XCTAssertTrue(exists(transcript))
    }

    // LTR-82: the preference survives removal, and Whisper then blocks admission.
    func testRemovalKeepsThePreferenceAndBlocksAdmission() async throws {
        defaults.set(TranscriptionEngine.whisper.rawValue, forKey: TranscriptionEngine.preferenceKey)
        let store = makeStore()
        store.install(fromFolder: try source())
        try await settle(store)
        var pending = [PendingInput(source: .file(root.appending(path: "a.m4a")), recording: nil)]
        let id = pending[0].id

        try store.remove()

        XCTAssertEqual(TranscriptionEngine.preferred(in: defaults), .whisper)
        XCTAssertNil(pending.admit(id, whisperInstalled: store.verifyInstalled(), defaults: defaults))
        XCTAssertEqual(pending.count, 1)
    }

    // LTR-82: a model removed outside the app is not admitted on the stored state.
    func testModelRemovedOutsideTheAppIsRefusedAtAdmission() async throws {
        defaults.set(TranscriptionEngine.whisper.rawValue, forKey: TranscriptionEngine.preferenceKey)
        let store = makeStore()
        store.install(fromFolder: try source())
        try await settle(store)
        store.preparationStarted()
        store.preparationEnded(succeeded: true)
        var pending = [PendingInput(source: .file(root.appending(path: "a.m4a")), recording: nil)]
        let id = pending[0].id

        try FileManager.default.removeItem(at: store.modelFolder.appending(path: "config.json"))
        XCTAssertTrue(store.isInstalled, "the stored state has not noticed yet")

        XCTAssertNil(pending.admit(id, whisperInstalled: store.verifyInstalled(), defaults: defaults))
        XCTAssertEqual(pending.map(\.id), [id])
        XCTAssertEqual(TranscriptionEngine.preferred(in: defaults), .whisper)
        // The guidance can now show.
        XCTAssertEqual(store.state, .notInstalled)
        XCTAssertFalse(store.isPrepared)
    }

    func testVerifyingAnIntactModelAdmitsAndChangesNothing() async throws {
        defaults.set(TranscriptionEngine.whisper.rawValue, forKey: TranscriptionEngine.preferenceKey)
        let store = makeStore()
        store.install(fromFolder: try source())
        try await settle(store)
        store.preparationStarted()
        store.preparationEnded(succeeded: true)
        var pending = [PendingInput(source: .file(root.appending(path: "a.m4a")), recording: nil)]

        var changed = false
        withObservationTracking {
            _ = store.state
            _ = store.isPrepared
        } onChange: {
            changed = true
        }
        XCTAssertEqual(pending.admit(pending[0].id, whisperInstalled: store.verifyInstalled(), defaults: defaults)?.engine, .whisper)
        XCTAssertFalse(changed)
        XCTAssertEqual(store.state, .installed)
        XCTAssertTrue(store.isPrepared)
    }

    // What refresh() would replace: the reason a download failed stays readable.
    func testVerifyingKeepsAFailedDownloadsReason() async throws {
        let store = makeStore()
        store.install(fromFolder: try source(corrupting: "config.json"))
        try await settle(store)
        guard case .failed(let reason) = store.state else { return XCTFail("\(store.state)") }

        XCTAssertFalse(store.verifyInstalled())
        XCTAssertEqual(store.state, .failed(reason))
    }

    func testVerifyingDoesNotDisturbAnInstallInProgress() async throws {
        let store = makeStore()
        let release = AsyncStream<Void>.makeStream()
        store.install { _, _, _ in
            for await _ in release.stream { break }
            throw CancellationError()
        }
        XCTAssertTrue(store.isBusy)
        let before = store.state

        XCTAssertFalse(store.verifyInstalled())
        XCTAssertEqual(store.state, before)

        release.continuation.yield()
        release.continuation.finish()
        try await settle(store)
    }

    func testRemovalIsRefusedWhileInUse() async throws {
        let store = makeStore()
        store.install(fromFolder: try source())
        try await settle(store)
        store.preparationStarted()
        XCTAssertThrowsError(try store.remove()) { XCTAssertEqual($0.localizedDescription, WhisperModelError.inUse.localizedDescription) }
        XCTAssertEqual(store.state, .installed)
        XCTAssertTrue(exists(store.modelFolder))
        store.preparationEnded(succeeded: true)

        try store.remove()
        store.install { _, _, _ in try await Task.sleep(for: .seconds(30)) }
        XCTAssertThrowsError(try store.remove())
        store.cancel()
        try await settle(store)
    }

    // Waiting, running and failed stand for BatchQueue's answer through a job's life.
    func testRemovalIsRefusedWhileAJobNeedsTheModelAndAllowedOnceReleased() async throws {
        let store = makeStore()
        store.install(fromFolder: try source())
        try await settle(store)
        var jobNeedsModel = true   // waiting, then running
        store.jobsNeedModel = { jobNeedsModel }
        XCTAssertTrue(store.isInUse)
        XCTAssertThrowsError(try store.remove()) { XCTAssertEqual($0.localizedDescription, WhisperModelError.inUse.localizedDescription) }
        // Loaded, transcribing: the job is still unsettled.
        store.preparationStarted()
        store.preparationEnded(succeeded: true)
        XCTAssertThrowsError(try store.remove())
        XCTAssertEqual(store.state, .installed)
        XCTAssertTrue(exists(store.modelFolder))

        jobNeedsModel = false   // completed or failed
        XCTAssertFalse(store.isInUse)
        try store.remove()
        XCTAssertEqual(store.state, .notInstalled)
        XCTAssertFalse(exists(store.modelFolder))
    }

    // A partial ".download" from an interrupted attempt, or anything else unpinned,
    // never reaches the installed folder; verified files are still reused.
    func testStrayFilesInStagingAreNotPromoted() async throws {
        let store = makeStore()
        let good = try source()
        let model = good.appending(path: WhisperModelManifest.modelName)
        let staging = store.stagingFolder
        try FileManager.default.createDirectory(at: staging.appending(path: "Encoder.mlmodelc/weights"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: model.appending(path: "config.json"), to: staging.appending(path: "config.json"))
        try Data("partial".utf8).write(to: staging.appending(path: "Encoder.mlmodelc/weights/weight.bin.download"))
        try FileManager.default.createDirectory(at: staging.appending(path: "Stray.mlmodelc"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: staging.appending(path: "Stray.mlmodelc/x.bin"))

        let fetched = Fetched()
        store.install { file, destination, report in
            fetched.paths.append(file.path)
            try FileManager.default.copyItem(at: model.appending(path: file.path), to: destination)
            report(file.size)
        }
        try await settle(store)
        XCTAssertEqual(store.state, .installed)
        XCTAssertEqual(fetched.paths, ["Encoder.mlmodelc/metadata.json", "Encoder.mlmodelc/weights/weight.bin"])
        let installed = FileManager.default.enumerator(atPath: store.modelFolder.path)!.allObjects as! [String]
        XCTAssertEqual(Set(installed), Set(files.map(\.path) + ["Encoder.mlmodelc", "Encoder.mlmodelc/weights"]))
        XCTAssertFalse(exists(staging.deletingLastPathComponent()))
    }

    func testRemovalRefusesALinkedFolder() async throws {
        let elsewhere = root.appending(path: "elsewhere")
        let model = elsewhere.appending(path: WhisperModelManifest.modelName)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        let link = root.appending(path: "Whisper")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)
        XCTAssertThrowsError(try makeStore(link).remove())
        XCTAssertTrue(exists(model))
    }
}

private final class Fetched: @unchecked Sendable { var paths: [String] = [] }
