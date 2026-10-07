import AppKit
import AVFoundation
import ScreenCaptureKit

enum RecorderError: LocalizedError {
    case microphoneDenied
    case screenCaptureDenied
    case appNotCapturable(String)
    case noDisplay
    case microphoneDidNotStart
    case microphoneFailed
    case writeFailed
    case noAudio
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Local Transcriber may not use the microphone. Allow it in System Settings › Privacy & Security › Microphone."
        case .screenCaptureDenied:
            "Local Transcriber may not record app audio. Allow it in System Settings › Privacy & Security › Screen & System Audio Recording."
        case .appNotCapturable(let name):
            "\(name) can’t be recorded right now. Make sure it is running and has a window open."
        case .noDisplay: "No display is available for capturing app audio."
        case .microphoneDidNotStart: "The microphone recording didn’t start."
        case .microphoneFailed: "The microphone recording failed."
        case .writeFailed: "Part of the recording couldn’t be written."
        case .noAudio: "No audio was received."
        case .exportFailed: "The recording couldn’t be converted to M4A."
        }
    }
}

// Recording is one more input source. Audio is captured into app-local
// staging; only a finalized, validated file that has been saved into the output
// folder is handed on (`onSaved`), and ContentView adds it to the queue like a
// dropped file. Nothing is captured or requested before Record.
@MainActor @Observable
final class Recorder {
    enum State {
        case idle
        case starting
        case recording(since: Date)
        case finishing
    }

    struct RunningApp: Identifiable, Hashable {
        let id: String // bundle identifier
        let name: String
    }

    // Mic only uses AVAudioRecorder, so it never needs the screen-recording
    // permission. App audio (with or without the mic) uses ScreenCaptureKit.
    private enum Capture {
        case microphone(AVAudioRecorder, MicrophoneOutcome)
        case app(SCStream, AudioTrackWriter)
    }

    private static let silenceWarningDelay: TimeInterval = 10

    private(set) var state: State = .idle
    private(set) var apps: [RunningApp] = []
    var selectedAppID: String?
    var includesMicrophone = true
    private(set) var error: String?
    private(set) var silenceWarning: String?
    // A finalized recording still in staging because it could not be saved
    // to the output folder. Kept for this session only.
    private(set) var unsavedRecording: URL?
    // What the current or last recording captures, for example "Safari + Microphone".
    private(set) var recordingLabel = ""

    private var capture: Capture?
    // Bumped by every Record and by cancel(), so an in-flight start or a late
    // callback of an earlier capture can tell it is stale.
    private var session = 0
    private var stagingDirectory: URL?
    private var baseName = ""
    private var lastSoundAt: Date?
    private var silenceTask: Task<Void, Never>?
    private var destination: OutputDestination?
    private var onSaved: (URL) -> Void = { _ in }

    var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    var canRecord: Bool {
        isIdle && unsavedRecording == nil && (selectedAppID != nil || includesMicrophone)
    }

    private var selectedApp: RunningApp? {
        apps.first { $0.id == selectedAppID }
    }

    // NSWorkspace needs no permission, so the list can be shown before Record.
    func refreshApps() {
        var seen = Set<String>()
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0 != .current }
            .compactMap { app in
                guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return RunningApp(id: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if selectedApp == nil {
            selectedAppID = nil
        }
    }

    func record(to destination: OutputDestination, onSaved: @escaping (URL) -> Void) async {
        guard canRecord else { return }
        error = nil
        silenceWarning = nil

        // A recording only starts with an output folder that accepts a file;
        // cancelling the panel starts nothing and creates nothing.
        destination.refresh()
        guard destination.isReady || destination.choose() else { return }
        do {
            try destination.checkWritable()
        } catch {
            self.error = "The output folder can’t be written to (\(error.localizedDescription)). Choose another folder."
            return
        }
        session += 1
        let id = session

        let app = selectedApp
        let withMicrophone = includesMicrophone
        recordingLabel = [app?.name, withMicrophone ? "Microphone" : nil]
            .compactMap { $0 }
            .joined(separator: " + ")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        baseName = "Recording \(formatter.string(from: .now)) (\(recordingLabel))"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        state = .starting

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalTranscriber-recording", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        // A capture that ends by itself goes through stop(), which finds the
        // failure the capture recorded and keeps the recording out of the queue.
        let onFailure: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self, id == self.session else { return }
                await self.stop()
            }
        }
        let started: Capture
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            if withMicrophone, !(await AVCaptureDevice.requestAccess(for: .audio)) {
                throw RecorderError.microphoneDenied
            }
            guard id == session else { throw CancellationError() }
            if let app {
                started = try await startAppCapture(
                    of: app,
                    withMicrophone: withMicrophone,
                    in: staging,
                    session: id,
                    onFailure: onFailure
                )
            } else {
                started = try startMicrophoneCapture(in: staging, onFailure: onFailure)
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            guard id == session else { return }
            state = .idle
            self.error = error.localizedDescription
            return
        }
        guard id == session else {
            // The window closed while this was starting.
            _ = try? await finalize(started)
            try? FileManager.default.removeItem(at: staging)
            return
        }

        capture = started
        self.destination = destination
        self.onSaved = onSaved
        stagingDirectory = staging
        let startedAt = Date.now
        lastSoundAt = nil
        state = .recording(since: startedAt)
        silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.checkForSound(since: startedAt)
            }
        }
        // A failure before this point found nothing to stop.
        if case .app(_, let writer) = started, writer.hasFailed {
            await stop()
        }
    }

    // Explicit Stop, and the end of a capture that failed. Only a capture that
    // recorded no failure can come out of finalize() as a file.
    func stop() async {
        guard case .recording = state, let capture else { return }
        let id = session
        state = .finishing
        silenceTask?.cancel()
        silenceTask = nil
        silenceWarning = nil
        self.capture = nil

        do {
            let file = try await finalize(capture)
            guard id == session else { return }
            // Only a file that opens as audio and has content goes any further.
            let audio = try AVAudioFile(forReading: file)
            guard audio.length > 0 else { throw RecorderError.noAudio }
            unsavedRecording = file
        } catch {
            guard id == session else { return }
            // The staged files are left alone, never enqueued.
            self.error = "The recording failed and was not added to the queue: \(error.localizedDescription)"
        }
        state = .idle
        if unsavedRecording == nil {
            release()
        } else {
            saveUnsavedRecording()
        }
    }

    // The owning window closed: stop capturing now and make sure an in-flight
    // start or a late callback changes nothing. Anything captured stays in
    // staging and is not saved or queued.
    func cancel() {
        session += 1
        silenceTask?.cancel()
        silenceTask = nil
        if let capture {
            self.capture = nil
            // With the window gone there is nowhere to show an error.
            Task { _ = try? await finalize(capture) }
        }
        state = .idle
        release()
    }

    // Drops what only a pending recording needs.
    private func release() {
        destination = nil
        onSaved = { _ in }
    }

    // Saves the staged recording into the output folder, then hands it on.
    // If the folder is unavailable it stays in staging and nothing is enqueued.
    func saveUnsavedRecording() {
        guard let file = unsavedRecording, let destination else { return }
        destination.refresh()
        do {
            guard destination.isReady else { throw OutputError.notConfigured }
            let saved = try destination.saveRecording(file, baseName: baseName)
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            unsavedRecording = nil
            error = nil
            onSaved(saved)
            release()
        } catch OutputError.notConfigured {
            self.error = "The output folder is unavailable, so the recording was not saved or queued yet. It is kept until you quit. Choose a folder to save it."
        } catch {
            self.error = "The recording couldn’t be saved to the output folder (\(error.localizedDescription)), so it was not queued yet. It is kept until you quit. Choose a folder to save it."
        }
    }

    func chooseFolderAndSave() {
        guard let destination, destination.choose() else { return }
        saveUnsavedRecording()
    }

    private func startMicrophoneCapture(in staging: URL, onFailure: @escaping @Sendable () -> Void) throws -> Capture {
        let recorder = try AVAudioRecorder(
            url: staging.appendingPathComponent("recording.m4a"),
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000
            ]
        )
        let outcome = MicrophoneOutcome(onFailure: onFailure)
        recorder.delegate = outcome
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.microphoneDidNotStart }
        return .microphone(recorder, outcome)
    }

    private func startAppCapture(
        of app: RunningApp,
        withMicrophone: Bool,
        in staging: URL,
        session id: Int,
        onFailure: @escaping @Sendable () -> Void
    ) async throws -> Capture {
        // This is the call that asks for the screen-recording permission.
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch let error as SCStreamError where error.code == .userDeclined {
            throw RecorderError.screenCaptureDenied
        }
        // The window may have closed during the lookup: create no capture.
        guard id == session else { throw CancellationError() }
        // Helper apps such as "<bundle id>.helper" belong to the selected app.
        let targets = content.applications.filter {
            $0.bundleIdentifier == app.id || $0.bundleIdentifier.hasPrefix(app.id + ".")
        }
        guard !targets.isEmpty else { throw RecorderError.appNotCapturable(app.name) }
        guard let display = content.displays.first else { throw RecorderError.noDisplay }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = withMicrophone
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        // Audio only: no screen output is added, so no frame is delivered or
        // written. The smallest, slowest video keeps the unused path cheap.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let writer = try AudioTrackWriter(
            url: staging.appendingPathComponent("capture.mov"),
            includesMicrophone: withMicrophone,
            onFailure: onFailure
        )
        let stream = SCStream(
            filter: SCContentFilter(display: display, including: targets, exceptingWindows: []),
            configuration: configuration,
            delegate: writer
        )
        try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: writer.queue)
        if withMicrophone {
            try stream.addStreamOutput(writer, type: .microphone, sampleHandlerQueue: writer.queue)
        }
        do {
            try await stream.startCapture()
        } catch let error as SCStreamError where error.code == .userDeclined {
            throw RecorderError.screenCaptureDenied
        }
        return .app(stream, writer)
    }

    // Returns the single staged M4A. App capture is written as one track per
    // source and mixed down into one track here.
    private func finalize(_ capture: Capture) async throws -> URL {
        switch capture {
        case .microphone(let recorder, let outcome):
            recorder.stop()
            try await outcome.ended()
            return recorder.url
        case .app(let stream, let writer):
            do {
                try await stream.stopCapture()
            } catch let error as SCStreamError where error.code == .attemptToStopStreamState {
                // Already stopped by the stream failure the writer recorded.
            } catch {
                writer.fail(error)
            }
            // A failed capture is still finished, so what was written stays
            // readable in staging, and then throws.
            let capturedFile = try await writer.finish()
            let file = capturedFile.deletingLastPathComponent().appendingPathComponent("recording.m4a")
            guard let export = AVAssetExportSession(
                asset: AVURLAsset(url: capturedFile),
                presetName: AVAssetExportPresetAppleM4A
            ) else { throw RecorderError.exportFailed }
            try await export.export(to: file, as: .m4a)
            try? FileManager.default.removeItem(at: capturedFile)
            return file
        }
    }

    // Silence is only reported as silence: it can be a quiet app, a muted
    // microphone or a capture problem, and none of these proves a denial.
    private func checkForSound(since startedAt: Date) {
        switch capture {
        case .microphone(let recorder, _):
            recorder.updateMeters()
            if recorder.peakPower(forChannel: 0) > -100 { lastSoundAt = .now }
        case .app(_, let writer):
            if let date = writer.lastSoundAt { lastSoundAt = date }
        case nil:
            return
        }
        let silentFor = Date.now.timeIntervalSince(lastSoundAt ?? startedAt)
        silenceWarning = silentFor >= Self.silenceWarningDelay
            ? "No sound has been received for \(Int(silentFor)) seconds. Recording continues; check that \(recordingLabel) is producing sound."
            : nil
    }
}

// Receives ScreenCaptureKit audio on its own queue and writes app audio and
// microphone as separate tracks of one staging movie.
nonisolated final class AudioTrackWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "nl.wavesweb.LocalTranscriber.recording")
    private let writer: AVAssetWriter
    private let inputs: [SCStreamOutputType: AVAssetWriterInput]
    private let onFailure: @Sendable () -> Void
    // Touched only on `queue`.
    private var isStarted = false
    private var isFinishing = false
    private var failure: Error?
    private var lastSound: Date?

    init(url: URL, includesMicrophone: Bool, onFailure: @escaping @Sendable () -> Void) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var inputs = [SCStreamOutputType.audio: Self.makeInput(channels: 2)]
        if includesMicrophone {
            inputs[.microphone] = Self.makeInput(channels: 1)
        }
        for input in inputs.values {
            writer.add(input)
        }
        self.inputs = inputs
        self.onFailure = onFailure
    }

    var lastSoundAt: Date? { queue.sync { lastSound } }
    var hasFailed: Bool { queue.sync { failure != nil } }

    // Records the first failure; the recording is then incomplete, ends, and
    // is never handed on.
    func fail(_ error: Error) {
        queue.async { [self] in latch(error) }
    }

    private func latch(_ error: Error) {
        guard failure == nil else { return }
        failure = error
        onFailure()
    }

    private static func makeInput(channels: Int) -> AVAssetWriterInput {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 64_000 * channels
        ])
        input.expectsMediaDataInRealTime = true
        return input
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !isFinishing, failure == nil, sampleBuffer.isValid, let input = inputs[type] else { return }
        if !isStarted {
            guard writer.startWriting() else { return latch(writer.error ?? RecorderError.writeFailed) }
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            isStarted = true
        }
        // A sample that is not written leaves a gap: the recording is incomplete.
        guard input.isReadyForMoreMediaData, input.append(sampleBuffer) else {
            return latch(writer.error ?? RecorderError.writeFailed)
        }
        if Self.containsSound(sampleBuffer) {
            lastSound = .now
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fail(error)
    }

    // Digital silence is all-zero samples whatever the sample format.
    private static func containsSound(_ sampleBuffer: CMSampleBuffer) -> Bool {
        (try? sampleBuffer.withAudioBufferList { buffers, _ in
            buffers.contains { buffer in
                guard let data = buffer.mData else { return false }
                return UnsafeRawBufferPointer(start: data, count: Int(buffer.mDataByteSize)).contains { $0 != 0 }
            }
        }) ?? false
    }

    func finish() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                isFinishing = true
                guard isStarted, writer.status == .writing else {
                    continuation.resume(throwing: failure ?? writer.error ?? RecorderError.noAudio)
                    return
                }
                for input in inputs.values {
                    input.markAsFinished()
                }
                writer.finishWriting { [self] in
                    queue.async { [self] in
                        if let failure {
                            continuation.resume(throwing: failure)
                        } else if writer.status == .completed {
                            continuation.resume(returning: writer.outputURL)
                        } else {
                            continuation.resume(throwing: writer.error ?? RecorderError.writeFailed)
                        }
                    }
                }
            }
        }
    }
}

// AVAudioRecorder reports how a recording ended only to its delegate, on the
// main thread, after stop() has returned.
final class MicrophoneOutcome: NSObject, AVAudioRecorderDelegate {
    private let onFailure: () -> Void
    private var failure: Error?
    private var hasEnded = false
    private var waiter: CheckedContinuation<Void, Never>?

    init(onFailure: @escaping () -> Void) {
        self.onFailure = onFailure
    }

    // Waits for the delegate after stop(), then throws if the recording failed.
    // A known failure is final: it does not wait for the finish callback.
    func ended() async throws {
        if !hasEnded, failure == nil {
            await withCheckedContinuation { waiter = $0 }
        }
        if let failure { throw failure }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        fail(error ?? RecorderError.microphoneFailed)
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag { fail(RecorderError.microphoneFailed) }
        hasEnded = true
        resumeWaiter()
    }

    private func fail(_ error: Error) {
        guard failure == nil else { return }
        failure = error
        resumeWaiter()
        onFailure()
    }

    private func resumeWaiter() {
        waiter?.resume()
        waiter = nil
    }
}
