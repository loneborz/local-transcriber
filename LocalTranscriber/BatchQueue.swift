import Foundation
import Observation
import os

struct MediaInfo {
    let type: String
    let duration: String
    let fileSize: String
}

// What a job was created from.
enum JobSource {
    case file(URL)
    case youtube(videoID: String, url: URL)
}

@MainActor @Observable
final class TranscriptionJob: Identifiable {
    enum State {
        case waiting
        case downloading
        case transcribing(TranscriptionPhase?)
        case complete(Transcript, processingDuration: Duration)
        case failed(String)
    }

    let id = UUID()
    let source: JobSource
    // Editable only while Waiting; read once when the job starts.
    var locale: Locale
    var mediaInfo: MediaInfo?
    // Set once a YouTube source has been resolved and downloaded.
    var metadata: SourceMetadata?
    var state: State = .waiting
    var savedTranscriptURL: URL?
    // Set when transcription succeeded but the automatic save did not.
    var saveError: String?
    // Set when the Markdown was saved but its timing sidecar was not. The job
    // and the Markdown are unaffected; this is only a notice.
    var sidecarWarning: String?
    // Whether the automatic save used the source-package presentation. Fixed
    // when the save is attempted, so later changes to the preference cannot
    // change what Copy or the manual Save writes for this job.
    var exportedAsPackage = false
    // Set for a recording: the entry folder that already holds its audio, and
    // when the recording started (the entry's creation time).
    var recording: (folder: URL, startedAt: Date)?
    // When processing began (elapsed time is shown from this).
    var startedAt: Date?
    // How far into the audio the recognizer has delivered results (nil until the
    // first result). Coverage of the audio only: no estimate of the work left.
    var progress: RecognitionProgress?

    init(source: JobSource, locale: Locale) {
        self.source = source
        self.locale = locale
    }

    var displayName: String {
        switch source {
        case .file(let url): url.lastPathComponent
        case .youtube(let videoID, _): metadata?.title ?? "YouTube · \(videoID)"
        }
    }

    // The entry folder's name: the media file's name, or a video's title.
    func entryName(mediaURL: URL) -> String {
        if case .youtube = source, let title = metadata?.title, !title.isEmpty { return title }
        return mediaURL.deletingPathExtension().lastPathComponent
    }

    // When the entry was created: the recording's start, a video's acquisition,
    // or, for an imported file, now (the save).
    var createdAt: Date {
        if let recording { return recording.startedAt }
        if case .youtube = source, let acquired = metadata?.acquiredAt { return acquired }
        return .now
    }

    var isWaiting: Bool {
        if case .waiting = state { return true }
        return false
    }

    // The one place that decides how this job's transcript is presented:
    // automatic save, manual Save and Copy all use it.
    func markdown(for transcript: Transcript) -> String {
        TranscriptMarkdownRenderer.render(transcript, source: exportedAsPackage ? metadata : nil)
    }

    var canRetry: Bool {
        if case .failed = state { true } else { false }
    }
}

// The app's one transcription slot. At most one job exists at any time: it is
// accepted only into an empty slot, starts at once, and leaves the slot when it
// has been saved (or when the user dismisses a failed or unsaved one). There is no
// waiting list. Owned by the app (MyApp), shared by every window.
@MainActor @Observable
final class BatchQueue {
    private(set) var jobs: [TranscriptionJob] = []
    // UserDefaults key of the "save YouTube links as source packages" mode.
    static let sourcePackageModeKey = "sourcePackageMode"

    let destination: OutputDestination

    init(destination: OutputDestination) {
        self.destination = destination
    }
    private var isRunning = false
    private static let log = Logger(subsystem: "nl.wavesweb.LocalTranscriber", category: "progress")

    var isProcessing: Bool { isRunning }
    // The slot is taken: running, failed, or finished but not saved.
    var isBusy: Bool { !jobs.isEmpty }

    // Takes the input into the empty slot and starts it. Returns nil, and changes
    // nothing, when the slot is taken. The language is the one given here.
    func accept(
        _ source: JobSource,
        locale: Locale,
        recording: (folder: URL, startedAt: Date)? = nil
    ) -> TranscriptionJob? {
        guard jobs.isEmpty else { return nil }
        let job = TranscriptionJob(source: source, locale: locale)
        job.recording = recording
        jobs = [job]
        startRunner()
        return job
    }

    // Frees the slot of a failed job, or of one whose transcript was not saved (the
    // caller asks first: the unsaved transcript is lost). A running job cannot be dismissed.
    func dismiss(_ job: TranscriptionJob) {
        switch job.state {
        case .failed, .complete: jobs.removeAll { $0.id == job.id }
        default: break
        }
    }

    // Returns one Failed job to Waiting. Complete jobs are never touched, so
    // a retry cannot repeat finished work. The caller starts the queue.
    func retry(_ job: TranscriptionJob) {
        guard job.canRetry else { return }
        job.metadata = nil
        job.saveError = nil
        job.sidecarWarning = nil
        job.exportedAsPackage = false
        job.startedAt = nil
        job.progress = nil
        job.state = .waiting
        startRunner()
    }

    private func startRunner() {
        guard !isRunning, jobs.contains(where: \.isWaiting) else { return }
        isRunning = true
        Task { await run() }
    }

    // `isRunning` is cleared with no suspension point after the last check.
    private func run() async {
        while let job = jobs.first(where: \.isWaiting) {
            await process(job)
        }
        isRunning = false
    }

    private func process(_ job: TranscriptionJob) async {
        job.startedAt = .now
        job.progress = nil
        switch job.source {
        case .file(let url):
            await transcribeAndSave(job, mediaURL: url)
        case .youtube(let videoID, let url):
            // Resolved and downloaded only now, at job start.
            job.state = .downloading
            let acquired: AcquiredAudio
            do {
                acquired = try await YouTubeAcquirer.acquire(videoID: videoID, url: url)
            } catch {
                job.state = .failed(error.localizedDescription)
                return
            }
            defer { try? FileManager.default.removeItem(at: acquired.directory) }
            job.metadata = acquired.metadata
            await transcribeAndSave(job, mediaURL: acquired.audioURL)
        }
    }

    private func transcribeAndSave(_ job: TranscriptionJob, mediaURL: URL) async {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let locale = job.locale
        job.state = .transcribing(nil)

        do {
            let transcript = try await TranscriptionService.transcribe(
                url: mediaURL,
                locale: locale,
                onPhaseChange: { job.state = .transcribing($0) },
                onProgress: { position, total in
                    // Late or overlapping results never move the position back.
                    if job.progress == nil {
                        job.progress = RecognitionProgress(position: position, total: total)
                    } else {
                        job.progress?.report(position: position, total: total)
                    }
                    Self.log.info("recognized \(position, format: .fixed(precision: 1)) of \(total, format: .fixed(precision: 1)) s")
                }
            )
            job.state = .complete(transcript, processingDuration: startedAt.duration(to: clock.now))
            save(transcript, for: job, mediaURL: mediaURL)
            // Saved without a warning: nothing is left to do, the slot is free. The
            // new transcript reaches every window's library by notification.
            if job.saveError == nil, job.sidecarWarning == nil {
                jobs.removeAll { $0.id == job.id }
            }
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            job.state = .failed(error.localizedDescription)
        }
    }

    // A failed save never fails the job: it stays Complete with its transcript
    // in memory, and the error is recorded for the manual Save fallback.
    private func save(_ transcript: Transcript, for job: TranscriptionJob, mediaURL: URL) {
        // Decided before the write, so it is also set when the write fails.
        var package: SourceMetadata?
        if UserDefaults.standard.bool(forKey: Self.sourcePackageModeKey),
           case .youtube = job.source,
           let metadata = job.metadata {
            package = metadata
        }
        job.exportedAsPackage = package != nil

        job.sidecarWarning = nil
        var metadataWarning: String?

        do {
            let saved = try TranscriptSidecar.saveWithSidecar(
                transcript,
                markdown: job.markdown(for: transcript),
                writeMarkdown: { markdown in
                    // One folder per job, named after the media (or the video's
                    // title). A source package also keeps the audio, copied out of
                    // the temporary directory before the caller removes it.
                    let written = try destination.writeEntry(
                        baseName: job.entryName(mediaURL: mediaURL),
                        existingFolder: job.recording?.folder,
                        markdown: markdown,
                        createdAt: job.createdAt,
                        audio: package == nil ? nil : mediaURL,
                        manifest: try package.map {
                            try SourcePackageManifest(
                                metadata: $0, transcriptionLocale: transcript.localeIdentifier
                            ).encoded()
                        }
                    )
                    metadataWarning = written.metadataWarning
                    job.savedTranscriptURL = written.markdown
                    return written.markdown
                },
                // The sidecar goes next to the file actually written.
                writeSidecar: { try destination.writeSidecar($0, besides: $1) }
            )
            job.saveError = nil
            job.sidecarWarning = [saved.sidecarWarning, metadataWarning].compactMap { $0 }.joined(separator: "\n")
            if job.sidecarWarning?.isEmpty == true { job.sidecarWarning = nil }
        } catch {
            job.saveError = error.localizedDescription
        }
    }
}
