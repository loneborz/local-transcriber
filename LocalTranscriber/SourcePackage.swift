import Foundation

// The schema of `source.json` in a source package. This is a LocalTranscriber-
// owned, versioned format and never a dump of yt-dlp's own JSON, so changing
// the acquisition tool cannot change it. Fields that are unknown are omitted.
struct SourcePackageManifest: Encodable {
    static let currentSchemaVersion = 1
    static let audioFilename = "audio.m4a"
    static let transcriptFilename = "transcript.md"
    static let manifestFilename = "source.json"

    let schemaVersion: Int
    let sourceType: String
    let sourceURL: String
    let videoID: String
    let title: String
    let channel: String?
    // yyyy-MM-dd, as published by the source.
    let publishedDate: String?
    let durationSeconds: Double?
    // ISO 8601, UTC.
    let acquiredAt: String
    // Name of the audio file inside the package.
    let audioFilename: String
    // Locale the transcript was produced with, e.g. "en-US".
    let transcriptionLocale: String

    init(metadata: SourceMetadata, transcriptionLocale: String) {
        schemaVersion = Self.currentSchemaVersion
        sourceType = metadata.sourceType
        sourceURL = metadata.url.absoluteString
        videoID = metadata.videoID
        title = metadata.title
        channel = metadata.channel
        publishedDate = metadata.uploadDate
        durationSeconds = metadata.duration
        acquiredAt = ISO8601DateFormatter().string(from: metadata.acquiredAt)
        audioFilename = Self.audioFilename
        self.transcriptionLocale = transcriptionLocale
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }
}
