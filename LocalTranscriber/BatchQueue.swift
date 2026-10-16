import Foundation
import Observation
import os

struct MediaInfo {
    let type: String
    let duration: String
    let fileSize: String
}

// What a job was created from. An invalid source is a job that has already
// failed, so it stays visible in the queue instead of silently disappearing.
enum JobSource {
    case file(URL)
    case youtube(videoID: String, url: URL)
    case invalid(input: String, reason: String)
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
    // Which batch added this job (see BatchQueue.enqueue). Only the queue view
    // uses it, to keep earlier finished work out of the way.
    var batch = 0
    // Whether the automatic save used the source-package presentation. Fixed
    // when the save is attempted, so later changes to the preference cannot
    // change what Copy or the manual Save writes for this job.
    var exportedAsPackage = false
    // Set for a recording: the entry folder that already holds its audio, and
    // when the recording started (the entry's creation time).
    var recording: (folder: URL, startedAt: Date)?
    // Whether the user has started this job. A job added while the queue is
    // running waits until the user starts it too, so its language can still be
    // checked; the runner only takes started jobs.
    var isStarted = false
    // The window that added the job. Only that window opens its transcript on its own.
    var originWindow: UUID?
    // When processing began (elapsed time is shown from this).
    var startedAt: Date?
    // How far into the audio the recognizer has delivered results (nil until the
    // first result). Coverage of the audio only: no estimate of the work left.
    var progress: RecognitionProgress?

    init(source: JobSource, locale: Locale) {
        self.source = source
        self.locale = locale
        if case .invalid(_, let reason) = source {
            state = .failed(reason)
        }
    }

    var displayName: String {
        switch source {
        case .file(let url): url.lastPathComponent
        case .youtube(let videoID, _): metadata?.title ?? "YouTube · \(videoID)"
        case .invalid(let input, _): input
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

    // Waiting and not started yet: the user can still review and change it.
    var isUnstarted: Bool { isWaiting && !isStarted }

    var isWaiting: Bool {
        if case .waiting = state { return true }
        return false
    }

    // Waiting, downloading or transcribing.
    var isUnfinished: Bool {
        switch state {
        case .waiting, .downloading, .transcribing: true
        case .complete, .failed: false
        }
    }

    // The one place that decides how this job's transcript is presented:
    // automatic save, manual Save and Copy all use it.
    func markdown(for transcript: Transcript) -> String {
        TranscriptMarkdownRenderer.render(transcript, source: exportedAsPackage ? metadata : nil)
    }

    // A rejected link fails the same way every time, so only failures of a
    // real source are worth retrying.
    var canRetry: Bool {
        guard case .failed = state else { return false }
        if case .invalid = source { return false }
        return true
    }
}

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
    private var batchCounter = 0
    // How many jobs each batch was given. Clearing finished jobs does not change it,
    // so a multi-file batch is never taken for a single file.
    private var batchSizes: [Int: Int] = [:]
    private static let log = Logger(subsystem: "nl.wavesweb.LocalTranscriber", category: "progress")

    var isProcessing: Bool { isRunning }
    var hasWaitingJobs: Bool { jobs.contains(where: \.isWaiting) }
    var waitingCount: Int { jobs.filter(\.isWaiting).count }
    func batchSize(of job: TranscriptionJob) -> Int { batchSizes[job.batch] ?? 1 }

    // Waiting jobs the user has not started yet.
    var unstartedCount: Int { jobs.count(where: \.isUnstarted) }

    // Only Waiting jobs are editable; active, Complete and Failed jobs keep
    // the language they started with.
    func applyLocale(_ locale: Locale) {
        for job in jobs where job.isWaiting {
            job.locale = locale
        }
    }

    // Adds jobs in the Waiting state (invalid sources start Failed), each
    // owning the given locale. Nothing runs until `start` is called, also while
    // another job is running; the running batch does not take them.
    func enqueue(_ sources: [JobSource], locale: Locale, originWindow: UUID? = nil) -> [TranscriptionJob] {
        let newJobs = sources.map { TranscriptionJob(source: $0, locale: locale) }
        for job in newJobs { job.originWindow = originWindow }
        // Files added while nothing is waiting or running begin a new batch; files
        // added to unfinished work join it.
        if !jobs.contains(where: \.isUnfinished) { batchCounter += 1 }
        for job in newJobs { job.batch = batchCounter }
        batchSizes[batchCounter, default: 0] += newJobs.count
        jobs.append(contentsOf: newJobs)
        return newJobs
    }

    // Only a Waiting job can be removed; the runner re-scans `jobs` on every
    // pass, so a removed job never runs. Source media is never touched.
    func remove(_ job: TranscriptionJob) {
        guard job.isWaiting else { return }
        jobs.removeAll { $0.id == job.id }
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
        // Retry is the user's explicit start of this one job.
        job.isStarted = true
        job.state = .waiting
    }

    // The library renamed or moved a saved transcript: the jobs that saved it
    // follow the file.
    func relocate(from old: URL, to new: URL) {
        let oldPath = old.standardizedFileURL.path
        for job in jobs where job.savedTranscriptURL?.standardizedFileURL.path == oldPath {
            job.savedTranscriptURL = new
        }
    }

    // Failed jobs and Complete jobs that were saved are finished and can be cleared;
    // Waiting and active jobs, and jobs whose save failed, are not touched.
    private func isClearable(_ job: TranscriptionJob) -> Bool {
        switch job.state {
        case .failed: true
        case .complete: job.savedTranscriptURL != nil
        default: false
        }
    }

    var canClear: Bool { jobs.contains(where: isClearable) }

    func clearFinished() {
        jobs.removeAll(where: isClearable)
    }

    // Starts the given Waiting jobs, or every Waiting job. Jobs added later wait for
    // their own start, also while this batch runs.
    func start(_ only: [TranscriptionJob]? = nil) {
        for job in only ?? jobs where job.isWaiting { job.isStarted = true }
        startRunner()
    }

    // Used by Retry: only the retried job was started.
    func startRunner() {
        guard !isRunning, jobs.contains(where: { $0.isWaiting && $0.isStarted }) else { return }
        isRunning = true
        Task { await run() }
    }

    // Re-checks for started jobs on every pass; `isRunning` is cleared with no
    // suspension point after the last check.
    private func run() async {
        while let job = jobs.first(where: { $0.isWaiting && $0.isStarted }) {
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
            // Resolved and downloaded only now, at job start. A failure here
            // fails this job alone; the runner moves on to the next one.
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
        case .invalid(_, let reason):
            job.state = .failed(reason)
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
