import Foundation

// Everything YouTube-specific lives here. The transcription engine only ever
// sees the local M4A that `YouTubeAcquirer.acquire` produces.

// Identity of an acquired source. Kept small and app-owned (never raw yt-dlp
// JSON) so later source-package output can build on it.
nonisolated struct SourceMetadata: Sendable {
    let sourceType: String
    let url: URL
    let videoID: String
    let title: String
    let channel: String?
    // ISO 8601 date (yyyy-MM-dd) when yt-dlp provides one.
    let uploadDate: String?
    let duration: TimeInterval?
    let acquiredAt: Date
    let audioFilename: String

    var detailText: String {
        var parts = ["YouTube"]
        if let channel { parts.append(channel) }
        if let duration, duration.isFinite, duration > 0 {
            let total = Int(duration.rounded())
            parts.append(total >= 3600
                ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
                : String(format: "%d:%02d", total / 60, total % 60))
        }
        return parts.joined(separator: " · ")
    }
}

nonisolated enum YouTubeURL {
    private static let hosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
        "youtu.be", "www.youtu.be"
    ]

    // Returns the canonical watch URL and video ID for a supported YouTube
    // link, or nil for anything else (including playlist-only links).
    static func parse(_ url: URL) -> (videoID: String, canonical: URL)? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), hosts.contains(host) else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        var candidate: String?
        if host.hasSuffix("youtu.be") {
            candidate = components.first
        } else if components.first == "watch" {
            candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "v" }?.value
        } else if let first = components.first, ["shorts", "live", "embed", "v"].contains(first) {
            candidate = components.dropFirst().first
        }

        guard let videoID = candidate, isValid(videoID),
              let canonical = URL(string: "https://www.youtube.com/watch?v=\(videoID)") else { return nil }
        return (videoID, canonical)
    }

    static func isValid(_ videoID: String) -> Bool {
        videoID.count == 11 && videoID.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

nonisolated struct AcquiredAudio: Sendable {
    let audioURL: URL
    // Per-job directory; the caller removes it once transcription is done.
    let directory: URL
    let metadata: SourceMetadata
}

nonisolated enum YouTubeError: LocalizedError {
    case helperMissing
    case couldNotStart(String)
    case timedOut(minutes: Int)
    case failed(String)
    case noAudio
    case noMetadata

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            "The bundled YouTube helper is missing from the app."
        case .couldNotStart(let reason):
            "The bundled YouTube helper could not start: \(reason)"
        case .timedOut(let minutes):
            "Downloading timed out after \(minutes) minutes."
        case .failed(let message):
            message
        case .noAudio:
            "yt-dlp finished but did not produce an audio file."
        case .noMetadata:
            "yt-dlp finished but did not report video details."
        }
    }
}

nonisolated enum YouTubeAcquirer {
    static let timeout: TimeInterval = 30 * 60

    // Sandbox-local (inside the app container's temporary directory).
    static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LocalTranscriber-acquisition", isDirectory: true)
    }

    // Called once at launch, before any job exists: anything left behind by a
    // crashed or killed run is stale.
    static func sweepStaleDirectories() {
        try? FileManager.default.removeItem(at: root)
    }

    static func acquire(videoID: String, url: URL) async throws -> AcquiredAudio {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try await download(videoID: videoID, url: url, into: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func download(videoID: String, url: URL, into directory: URL) async throws -> AcquiredAudio {
        guard let resources = Bundle.main.resourceURL else { throw YouTubeError.helperMissing }
        let python = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/python3.13")
        let launcher = resources.appendingPathComponent("ytdlp_launcher.py")
        let ytdlp = resources.appendingPathComponent("yt-dlp")
        let pythonHome = resources.appendingPathComponent("python-home")
        let fileManager = FileManager.default
        guard [python, launcher, ytdlp, pythonHome].allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            throw YouTubeError.helperMissing
        }

        let environment = [
            "PYTHONHOME": pythonHome.path,
            "PYTHONNOUSERSITE": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONUTF8": "1",
            "LANG": "en_US.UTF-8",
            "PATH": "/usr/bin:/bin",
            "HOME": NSHomeDirectory()
        ]
        let arguments = [
            launcher.path, ytdlp.path,
            "--ignore-config", "--no-playlist", "--no-cache-dir",
            "--quiet", "--no-warnings", "--no-progress",
            "--socket-timeout", "30", "--retries", "3", "--extractor-retries", "2",
            "-f", "bestaudio[ext=m4a]",
            "-o", directory.appendingPathComponent("audio.%(ext)s").path,
            "--print", "after_move:%(.{id,title,channel,upload_date,duration})j",
            url.absoluteString
        ]

        let output: HelperProcess.Output
        do {
            output = try await HelperProcess().run(
                executable: python,
                arguments: arguments,
                environment: environment,
                timeout: timeout
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw YouTubeError.couldNotStart(error.localizedDescription)
        }

        if output.timedOut { throw YouTubeError.timedOut(minutes: Int(timeout / 60)) }
        guard output.status == 0 else { throw YouTubeError.failed(errorMessage(from: output)) }

        let audio = directory.appendingPathComponent("audio.m4a")
        guard fileManager.fileExists(atPath: audio.path) else { throw YouTubeError.noAudio }
        guard let details = parseDetails(output.standardOutput) else { throw YouTubeError.noMetadata }

        let title = (details["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let namedAudio = directory
            .appendingPathComponent(fileBaseName(title: title, videoID: videoID))
            .appendingPathExtension("m4a")
        try fileManager.moveItem(at: audio, to: namedAudio)

        let metadata = SourceMetadata(
            sourceType: "youtube",
            url: url,
            videoID: videoID,
            title: title.isEmpty ? "YouTube video" : title,
            channel: (details["channel"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            uploadDate: (details["upload_date"] as? String).flatMap(isoDate),
            duration: (details["duration"] as? NSNumber)?.doubleValue,
            acquiredAt: Date(),
            audioFilename: namedAudio.lastPathComponent
        )
        return AcquiredAudio(audioURL: namedAudio, directory: directory, metadata: metadata)
    }

    // "<Title> [<video ID>]" without filesystem-invalid characters, capped so
    // the name and the ".m4a"/".md" suffixes stay well under 255 bytes.
    static func fileBaseName(title: String, videoID: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        var cleaned = String(String.UnicodeScalarView(title.unicodeScalars.map {
            invalid.contains($0) ? " " : $0
        }))
        cleaned = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        while cleaned.count > 100 || cleaned.utf8.count > 160 { cleaned.removeLast() }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { cleaned = "YouTube video" }
        return "\(cleaned) [\(videoID)]"
    }

    private static func parseDetails(_ data: Data) -> [String: Any]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline).reversed() where line.hasPrefix("{") {
            if let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] {
                return object
            }
        }
        return nil
    }

    private static func isoDate(_ yyyymmdd: String) -> String? {
        guard yyyymmdd.count == 8, yyyymmdd.allSatisfy(\.isNumber) else { return nil }
        let digits = Array(yyyymmdd)
        return "\(String(digits[0..<4]))-\(String(digits[4..<6]))-\(String(digits[6..<8]))"
    }

    private static func errorMessage(from output: HelperProcess.Output) -> String {
        let stderr = String(data: output.standardError, encoding: .utf8) ?? ""
        let lines = stderr.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        if let line = lines.last(where: { $0.hasPrefix("ERROR:") }) {
            return String(line.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces)
        }
        if let last = lines.last, !last.isEmpty {
            return "yt-dlp failed: \(last)"
        }
        return "yt-dlp exited with status \(output.status)."
    }
}

// Runs one child process with captured output, a hard timeout and
// cancellation. Every running child is registered so it can be terminated when
// the app quits; the launcher script additionally makes the child exit if the
// app disappears without a chance to do so.
nonisolated final class HelperProcess: @unchecked Sendable {
    struct Output: Sendable {
        let status: Int32
        let standardOutput: Data
        let standardError: Data
        let timedOut: Bool
    }

    private final class Buffer: @unchecked Sendable {
        var data = Data()
    }

    private let process = Process()
    private let lock = NSLock()
    private var didTimeOut = false

    private static let registryLock = NSLock()
    private static var running: [ObjectIdentifier: Process] = [:]

    static func terminateAll() {
        registryLock.lock()
        let processes = Array(running.values)
        registryLock.unlock()
        for process in processes where process.isRunning {
            process.terminate()
        }
        // Give them a moment, then make sure nothing is left.
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, processes.contains(where: \.isRunning) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        for process in processes where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> Output {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try self.process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    Self.register(self.process)

                    let outBuffer = Buffer()
                    let errBuffer = Buffer()
                    let readers = DispatchGroup()
                    readers.enter()
                    DispatchQueue.global().async {
                        outBuffer.data = outPipe.fileHandleForReading.readDataToEndOfFile()
                        readers.leave()
                    }
                    readers.enter()
                    DispatchQueue.global().async {
                        errBuffer.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                        readers.leave()
                    }

                    let timer = DispatchWorkItem {
                        self.lock.lock()
                        self.didTimeOut = true
                        self.lock.unlock()
                        self.terminate()
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

                    self.process.waitUntilExit()
                    timer.cancel()
                    readers.wait()
                    Self.unregister(self.process)

                    self.lock.lock()
                    let timedOut = self.didTimeOut
                    self.lock.unlock()
                    continuation.resume(returning: Output(
                        status: self.process.terminationStatus,
                        standardOutput: outBuffer.data,
                        standardError: errBuffer.data,
                        timedOut: timedOut
                    ))
                }
            }
        } onCancel: {
            self.terminate()
        }
    }

    // SIGTERM, then SIGKILL if it is still running a few seconds later.
    private func terminate() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private static func register(_ process: Process) {
        registryLock.lock()
        running[ObjectIdentifier(process)] = process
        registryLock.unlock()
    }

    private static func unregister(_ process: Process) {
        registryLock.lock()
        running[ObjectIdentifier(process)] = nil
        registryLock.unlock()
    }
}
