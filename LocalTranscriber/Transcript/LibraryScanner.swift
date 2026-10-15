import Foundation

// A completed transcript found in the output folder. It is a snapshot of what
// the files said at scan time; nothing about it is stored anywhere.
nonisolated struct LibraryTranscript: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case flat, package }

    var kind: Kind
    // The Markdown file: `<name>.md`, or `transcript.md` inside a source package.
    var markdownURL: URL
    var header: TranscriptHeader
    // When the Markdown was last written (the file's modification date).
    var savedAt: Date

    var id: String { markdownURL.standardizedFileURL.path }
    var title: String { header.title }

    // What the app's own save reports for the job: the Markdown file, or the
    // package folder.
    var artifactURL: URL {
        kind == .package ? markdownURL.deletingLastPathComponent() : markdownURL
    }

    // Beside the Markdown, named after it (see SidecarFile).
    var sidecarURL: URL { SidecarFile.url(besides: markdownURL) }
}

// Finds the transcripts in an output folder. Read-only and stateless: a scan
// opens the top level of the folder and one level of source packages, reads the
// first bytes of each Markdown file, and returns what it found. It never recurses
// further, never follows symbolic links and never writes.
nonisolated enum LibraryScanner {
    // The header of a transcript is a few hundred bytes; the file name caps the title.
    static let headerBytes = 16 * 1024
    // SourcePackageManifest.transcriptFilename; that file is app-only.
    static let packageTranscriptName = "transcript.md"

    static func scan(folder: URL) throws -> [LibraryTranscript] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey]
        // Rebuilt from the folder URL, not taken from the listing, which resolves
        // symbolic links in the path (/var -> /private/var). The app's own saved
        // URLs and its security-scoped access use the folder URL as given.
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ).map { folder.appendingPathComponent($0.lastPathComponent) }

        var items: [LibraryTranscript] = []
        for entry in entries {
            // A symbolic link reports neither isDirectory nor isRegularFile, so a
            // link is never followed or read (tested with links to a file and a folder).
            guard let values = try? entry.resourceValues(forKeys: Set(keys)) else { continue }

            if values.isDirectory == true {
                guard values.isPackage != true else { continue }
                let markdown = entry.appendingPathComponent(packageTranscriptName)
                if let item = item(at: markdown, kind: .package) { items.append(item) }
            } else if entry.pathExtension.lowercased() == "md" {
                if let item = item(at: entry, kind: .flat, modified: values.contentModificationDate) {
                    items.append(item)
                }
            }
        }

        // Newest saved first; the path settles equal dates so the order is reproducible.
        return items.sorted {
            $0.savedAt == $1.savedAt ? $0.markdownURL.path < $1.markdownURL.path : $0.savedAt > $1.savedAt
        }
    }

    private static func item(at markdown: URL, kind: LibraryTranscript.Kind, modified: Date? = nil) -> LibraryTranscript? {
        guard let values = try? markdown.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
              values.isRegularFile == true,
              let handle = try? FileHandle(forReadingFrom: markdown) else { return nil }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: headerBytes),
              let parsed = TranscriptMarkdown.parse(String(decoding: data, as: UTF8.self)) else { return nil }
        return LibraryTranscript(
            kind: kind,
            markdownURL: markdown,
            header: parsed.header,
            savedAt: modified ?? values.contentModificationDate ?? .distantPast
        )
    }
}

// The library entry for a job that was saved: the item whose artifact is the
// URL the job reports. A job that matches is shown as the library item, not
// as a second row. Build the index once per scan; lookups are then cheap.
nonisolated enum LibraryJoin {
    typealias Index = [String: LibraryTranscript]

    static func index(_ items: [LibraryTranscript]) -> Index {
        Dictionary(items.map { ($0.artifactURL.standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func item(forSavedURL url: URL, in index: Index) -> LibraryTranscript? {
        index[url.standardizedFileURL.path]
    }

    // A saved job stays in the In progress list only until its library entry
    // appears: it was saved into the folder being listed and the scan has not
    // listed it yet. Saved anywhere else (another output folder, a manual Save
    // Transcript), it is not part of this library and is not listed.
    static func isAwaitingEntry(savedURL url: URL, folder: URL?, in index: Index) -> Bool {
        guard let folder else { return false }
        let path = url.standardizedFileURL.path
        return path.hasPrefix(folder.standardizedFileURL.path + "/") && index[path] == nil
    }
}
