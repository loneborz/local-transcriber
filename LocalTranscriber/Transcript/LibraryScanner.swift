import Foundation

// A completed transcript found in the output folder. It is a snapshot of what
// the files said at scan time; nothing about it is stored anywhere.
extension URL {
    // The path an entry or folder is identified by. `standardizedFileURL` drops the
    // `/private` of `/tmp`, `/var` and `/etc` only while the file exists, so the same
    // entry had two ids once it moved. This drops it always.
    nonisolated var libraryKey: String {
        let path = standardizedFileURL.path
        guard path.hasPrefix("/private/") else { return path }
        let rest = path.dropFirst("/private".count)
        return ["/tmp", "/var", "/etc"].contains { rest == $0 || rest.hasPrefix($0 + "/") } ? String(rest) : path
    }
}

nonisolated struct LibraryTranscript: Identifiable, Equatable, Sendable {
    // `flat` and `package` are the layouts of v0.6.x: listed and readable, never
    // changed by the app. `entry` is the managed layout: a folder named after
    // the transcript, holding `<name>.md`, its sidecar and `entry.json`.
    enum Kind: Sendable { case flat, package, entry }

    var kind: Kind
    // The Markdown file: `<name>.md`, or `transcript.md` inside a source package.
    var markdownURL: URL
    var header: TranscriptHeader
    // When the Markdown was last written (the file's modification date).
    var savedAt: Date
    // The organization folder this transcript is in; nil at the top level.
    var group: URL? = nil
    // What `entry.json` said (entries only).
    var metadata: EntryMetadata.State = .missing

    var id: String { markdownURL.libraryKey }

    // An entry is named by its folder, so an in-app or Finder rename shows at once.
    var title: String { kind == .entry ? entryFolderURL.lastPathComponent : header.title }

    // What the app's own save reports for the job: the Markdown file, or the
    // package folder.
    var artifactURL: URL {
        kind == .package ? markdownURL.deletingLastPathComponent() : markdownURL
    }

    var entryFolderURL: URL { markdownURL.deletingLastPathComponent() }

    // Beside the Markdown, named after it (see SidecarFile).
    var sidecarURL: URL { SidecarFile.url(besides: markdownURL) }

    // Only managed entries can be renamed, pinned, archived, moved or deleted.
    var isManaged: Bool { kind == .entry }
    var isPinned: Bool { metadata.metadata?.pinned ?? false }
    var isArchived: Bool { metadata.metadata?.archived ?? false }
    // Saved by a transcription and not opened yet.
    var isNew: Bool { metadata.metadata?.unopened ?? false }
    // The recorded creation time, if there is one.
    var createdAt: Date? { metadata.metadata?.createdAt }
    // What lists are ordered by: the creation time, else the save date.
    var sortDate: Date { createdAt ?? savedAt }
}

// An organization folder: a real folder directly inside the output folder that is
// not itself an entry. Empty folders are listed too.
nonisolated struct LibraryFolder: Identifiable, Equatable, Sendable {
    var url: URL
    // The folder's identity on disk when it was listed. An action the user confirmed
    // later is refused if another folder has taken that path since.
    var fileNumber: UInt64?
    var id: String { url.libraryKey }
    var name: String { url.lastPathComponent }

    init(url: URL, fileNumber: UInt64? = nil) {
        self.url = url
        self.fileNumber = fileNumber
    }

    // The folder at `url` as it is now.
    static func current(at url: URL) -> LibraryFolder {
        let number = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? UInt64
        return LibraryFolder(url: url, fileNumber: number)
    }

    // Whether the folder at this path is still the one that was listed.
    var isUnchanged: Bool {
        guard let fileNumber else { return true }
        let now = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? UInt64
        return now == fileNumber
    }
}

nonisolated struct LibraryListing: Equatable, Sendable {
    var items: [LibraryTranscript] = []
    var folders: [LibraryFolder] = []
}

// Finds the transcripts in an output folder. Read-only and stateless: a scan
// lists the top level, the organization folders directly below it and each entry
// folder, reads the first bytes of each Markdown file and `entry.json`, and
// returns what it found. It never goes deeper, never follows symbolic links and
// never writes.
//
// A folder is an entry when it holds `entry.json` and a valid Markdown, when it
// holds a v0.6.x `transcript.md`, or when it holds a valid `<folder>.md`. A folder
// with `entry.json` but no valid Markdown is an incomplete entry (a recording that
// is not transcribed yet) and is skipped. Every other folder is an organization
// folder.
nonisolated enum LibraryScanner {
    // The header of a transcript is a few hundred bytes; the file name caps the title.
    static let headerBytes = 16 * 1024
    // SourcePackageManifest.transcriptFilename; that file is app-only.
    static let packageTranscriptName = "transcript.md"

    // Every transcript, newest first.
    static func scan(folder: URL) throws -> [LibraryTranscript] {
        try scanLibrary(folder: folder).items
    }

    static func scanLibrary(folder: URL) throws -> LibraryListing {
        var listing = LibraryListing()
        for entry in try children(of: folder) {
            visit(entry, group: nil, into: &listing)
        }

        listing.items.sort(by: isOrderedBefore)
        listing.folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return listing
    }

    // Newest first; the path settles equal dates so the order is reproducible.
    static func isOrderedBefore(_ a: LibraryTranscript, _ b: LibraryTranscript) -> Bool {
        a.sortDate == b.sortDate ? a.markdownURL.path < b.markdownURL.path : a.sortDate > b.sortDate
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isRegularFileKey, .contentModificationDateKey,
    ]

    // Rebuilt from the folder URL, not taken from the listing, which resolves
    // symbolic links in the path (/var -> /private/var). The app's own saved
    // URLs and its security-scoped access use the folder URL as given.
    private static func children(of folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ).map { folder.appendingPathComponent($0.lastPathComponent) }
    }

    // `group` is the organization folder being listed; nil at the top level, where
    // an unknown folder becomes an organization folder. Inside one, it is ignored:
    // folders are one level deep.
    private static func visit(_ url: URL, group: URL?, into listing: inout LibraryListing) {
        // A symbolic link is never followed or read, whatever it points to.
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
              values.isSymbolicLink != true else { return }

        if values.isDirectory == true {
            guard values.isPackage != true else { return }
            switch entryFolder(at: url, group: group) {
            case .entry(let item): listing.items.append(item)
            case .incomplete: break
            case .notAnEntry:
                guard group == nil else { return }
                listing.folders.append(LibraryFolder.current(at: url))
                for child in (try? children(of: url)) ?? [] {
                    visit(child, group: url, into: &listing)
                }
            }
        } else if values.isRegularFile == true, url.pathExtension.lowercased() == "md" {
            if var item = item(at: url, kind: .flat, modified: values.contentModificationDate) {
                item.group = group
                listing.items.append(item)
            }
        }
    }

    enum EntryFolder {
        case entry(LibraryTranscript)
        case incomplete
        case notAnEntry
    }

    static func entryFolder(at folder: URL, group: URL?) -> EntryFolder {
        let names = ((try? children(of: folder)) ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]))?.isRegularFile == true
        }.map(\.lastPathComponent)
        let own = folder.lastPathComponent + ".md"

        func entry(_ name: String, kind: LibraryTranscript.Kind) -> LibraryTranscript? {
            guard names.contains(name), var found = item(at: folder.appendingPathComponent(name), kind: kind) else { return nil }
            found.group = group
            if kind == .entry { found.metadata = EntryMetadata.read(in: folder) }
            return found
        }

        if names.contains(EntryMetadata.fileName) {
            let others = names.filter { $0.lowercased().hasSuffix(".md") && $0 != own && $0 != packageTranscriptName }.sorted()
            for name in [own, packageTranscriptName] + others {
                if let found = entry(name, kind: .entry) { return .entry(found) }
            }
            return .incomplete
        }
        if let found = entry(packageTranscriptName, kind: .package) { return .entry(found) }
        // Without entry.json (its write failed), `<folder>.md` is an entry only when it
        // is all the folder holds: an organization folder that happens to hold a
        // legacy transcript of its own name must not turn into one entry.
        let markdowns = names.filter { $0.lowercased().hasSuffix(".md") }
        if markdowns == [own], !hasSubfolders(folder), let found = entry(own, kind: .entry) { return .entry(found) }
        return .notAnEntry
    }

    private static func hasSubfolders(_ folder: URL) -> Bool {
        ((try? children(of: folder)) ?? []).contains {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]))
                .map { $0.isDirectory == true && $0.isSymbolicLink != true } ?? false
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

// How the sidebar groups the listing. Archived entries are only in Archive. A
// pinned entry is listed in Pinned and also where it lives (its folder); the
// two rows are one transcript. Loose entries that are not pinned are Recent.
// Every list keeps the listing's order (newest first).
nonisolated struct LibrarySections: Equatable, Sendable {
    struct Group: Equatable, Sendable {
        var folder: LibraryFolder
        var entries: [LibraryTranscript]
    }

    var pinned: [LibraryTranscript] = []
    var folders: [Group] = []
    var recent: [LibraryTranscript] = []
    var archived: [LibraryTranscript] = []

    init(_ listing: LibraryListing) {
        folders = listing.folders.map { Group(folder: $0, entries: []) }
        let index = Dictionary(uniqueKeysWithValues: folders.enumerated().map { ($1.folder.id, $0) })
        for item in listing.items {
            if item.isArchived {
                archived.append(item)
                continue
            }
            if item.isPinned { pinned.append(item) }
            if let group = item.group, let slot = index[group.libraryKey] {
                folders[slot].entries.append(item)
            } else if !item.isPinned {
                recent.append(item)
            }
        }
    }
}
