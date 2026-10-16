import Foundation

// Everything the app does to the files of the library, as plain Foundation so it
// is tested as it is. Nothing here rewrites a Markdown file or a timing sidecar:
// writing a new entry creates files, every other operation only renames or moves
// whole files and folders, or edits `entry.json`. Nothing deletes permanently.
nonisolated enum LibraryOperations {
    // MARK: writing a new entry

    struct WrittenEntry: Equatable, Sendable {
        var folder: URL
        var markdown: URL
        // Set when only `entry.json` could not be written; the transcript is saved.
        var metadataWarning: String?
    }

    // Creates `<parent>/<Name>/`, or `<Name> 2`, `<Name> 3`, … when the name is
    // taken. An existing file or folder is never reused or overwritten.
    static func createFolder(named baseName: String, in parent: URL) throws -> URL {
        let name = EntryName.sanitized(baseName)
        for attempt in 1...9999 {
            let url = parent.appendingPathComponent(attempt == 1 ? name : "\(name) \(attempt)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                return url
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw LibraryError.tooManyCollisions
    }

    // Writes a finished transcript as an entry: `<Name>/<Name>.md` (the sidecar is
    // written beside it by the caller) plus `entry.json`, and for a source package
    // the video's `audio.m4a` and `source.json`. Into a new folder, or into the
    // folder of a recording (`existingFolder`), which already holds its audio.
    // If a step before the Markdown fails, a folder created here is removed again,
    // so no half-written entry is left behind. A failed `entry.json` is only a
    // warning: the transcript is saved and still listed.
    static func writeEntry(
        baseName: String,
        in parent: URL,
        existingFolder: URL? = nil,
        markdown: String,
        createdAt: Date,
        audio: URL? = nil,
        manifest: Data? = nil,
        writeMetadata: (EntryMetadata, URL) throws -> Void = EntryMetadata.create
    ) throws -> WrittenEntry {
        let folder = try existingFolder ?? createFolder(named: baseName, in: parent)
        let markdownURL = folder.appendingPathComponent(folder.lastPathComponent + ".md")
        do {
            if let audio {
                try FileManager.default.copyItem(
                    at: audio, to: folder.appendingPathComponent(AudioResolution.packageAudioName))
            }
            if let manifest {
                try manifest.write(
                    to: folder.appendingPathComponent(SourcePackageFile.manifestName), options: .withoutOverwriting)
            }
            // Foundation traps if .withoutOverwriting is combined with .atomic.
            try Data(markdown.utf8).write(to: markdownURL, options: .withoutOverwriting)
        } catch {
            if existingFolder == nil { try? FileManager.default.removeItem(at: folder) }
            throw error
        }

        var warning: String?
        if EntryMetadata.read(in: folder) == .missing {
            do {
                try writeMetadata(EntryMetadata(createdAt: createdAt), folder)
            } catch {
                warning = "Library details weren’t saved (\(EntryMetadata.fileName): \(error.localizedDescription)) "
                    + "The transcript is saved; it is listed without a creation date until it is pinned or archived."
            }
        }
        return WrittenEntry(folder: folder, markdown: markdownURL, metadataWarning: warning)
    }

    // A finished recording becomes an entry folder holding its audio and
    // `entry.json` (created before the file is moved in, so a failure leaves the
    // staged recording where it is). The transcript is added to the same folder
    // when the recording has been transcribed. Returns the audio file's new URL.
    static func saveRecording(_ staged: URL, baseName: String, in parent: URL, startedAt: Date) throws -> URL {
        let folder = try createFolder(named: baseName, in: parent)
        do {
            try EntryMetadata.create(EntryMetadata(createdAt: startedAt), folder)
            let audio = folder.appendingPathComponent(folder.lastPathComponent + "." + staged.pathExtension)
            try FileManager.default.moveItem(at: staged, to: audio)
            return audio
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    // MARK: organization folders

    static func createOrganizationFolder(named raw: String, in root: URL) throws -> LibraryFolder {
        let name = try EntryName.validated(raw).get()
        let url = root.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            throw LibraryError.nameTaken(name)
        }
        return LibraryFolder(url: url)
    }

    // MARK: managing an organization folder

    // What is inside a folder: transcripts the app manages (entry folders) and
    // anything else. Hidden Finder housekeeping files are not "anything else".
    struct FolderContents: Equatable, Sendable {
        var entryCount = 0
        // Names of items the app did not create (loose files, legacy transcripts, subfolders).
        var unmanaged: [String] = []
        var isSafeToTrash: Bool { unmanaged.isEmpty }
    }

    static func inspect(_ folder: LibraryFolder) -> FolderContents {
        var found = FolderContents()
        let children = (try? FileManager.default.contentsOfDirectory(
            at: folder.url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        for child in children {
            let name = child.lastPathComponent
            if name == ".DS_Store" { continue }
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isEntry = values?.isDirectory == true && values?.isSymbolicLink != true
                && (try? child.appendingPathComponent(EntryMetadata.fileName).checkResourceIsReachable()) == true
            if isEntry { found.entryCount += 1 } else { found.unmanaged.append(name) }
        }
        found.unmanaged.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        return found
    }

    // Renames the folder; its contents are untouched. Refused (nothing changes)
    // for an invalid name or a name that is taken in the output folder.
    static func renameFolder(_ folder: LibraryFolder, to raw: String) throws -> LibraryFolder {
        let name = try EntryName.validated(raw).get()
        guard isDirectory(folder.url) else { throw LibraryError.missing(folder.name) }
        let target = folder.url.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        if folder.name == name { return folder }
        if exists(target), !isSame(target, folder.url) { throw LibraryError.nameTaken(name) }
        try rename(folder.url, to: target)
        return LibraryFolder(url: target)
    }

    // Moves the folder and everything in it to the Trash, only when it holds
    // nothing but managed transcripts. A failure deletes nothing.
    static func trashFolder(
        _ folder: LibraryFolder,
        using trasher: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws {
        guard isDirectory(folder.url) else { throw LibraryError.missing(folder.name) }
        guard inspect(folder).isSafeToTrash else { throw LibraryError.folderHasOtherFiles(folder.name) }
        try trasher(folder.url)
    }

    // MARK: managing an entry

    static func setPinned(_ item: LibraryTranscript, _ pinned: Bool) throws -> LibraryTranscript {
        try updateMetadata(item) { $0.pinned = pinned }
    }

    static func setArchived(_ item: LibraryTranscript, _ archived: Bool) throws -> LibraryTranscript {
        try updateMetadata(item) { $0.archived = archived }
    }

    private static func updateMetadata(_ item: LibraryTranscript, _ change: (inout EntryMetadata) -> Void) throws -> LibraryTranscript {
        try requireManaged(item)
        try EntryMetadata.update(in: item.entryFolderURL, change)
        var updated = item
        updated.metadata = EntryMetadata.read(in: item.entryFolderURL)
        return updated
    }

    // Renames the entry folder, its Markdown file and its timing sidecar to the
    // same name. Contents are untouched, so the Markdown and sidecar keep their
    // bytes and `entry.json` keeps the creation time. A name that is invalid or
    // taken is refused before anything changes; a step that fails is rolled back.
    static func rename(_ item: LibraryTranscript, to raw: String) throws -> LibraryTranscript {
        try requireManaged(item)
        let name = try EntryName.validated(raw).get()
        let folder = item.entryFolderURL
        let parent = folder.deletingLastPathComponent()
        let newFolder = parent.appendingPathComponent(name, isDirectory: true)
        let newMarkdown = newFolder.appendingPathComponent(name + ".md")
        let sidecar = item.sidecarURL
        let hasSidecar = FileManager.default.fileExists(atPath: sidecar.path)

        guard FileManager.default.fileExists(atPath: item.markdownURL.path) else {
            throw LibraryError.missing(item.title)
        }
        if folder.lastPathComponent == name, item.markdownURL.lastPathComponent == name + ".md" { return item }

        // Names are checked against what is on disk now, before anything moves.
        if exists(newFolder), !isSame(newFolder, folder) { throw LibraryError.nameTaken(name) }
        let markdownTarget = folder.appendingPathComponent(name + ".md")
        if exists(markdownTarget), !isSame(markdownTarget, item.markdownURL) { throw LibraryError.nameTaken(name + ".md") }
        let sidecarTarget = SidecarFile.url(besides: markdownTarget)
        if hasSidecar, exists(sidecarTarget), !isSame(sidecarTarget, sidecar) {
            throw LibraryError.nameTaken(sidecarTarget.lastPathComponent)
        }

        var steps: [(from: URL, to: URL)] = []
        if item.markdownURL.lastPathComponent != name + ".md" { steps.append((item.markdownURL, markdownTarget)) }
        if hasSidecar, sidecar.lastPathComponent != sidecarTarget.lastPathComponent { steps.append((sidecar, sidecarTarget)) }
        if folder.lastPathComponent != name { steps.append((folder, newFolder)) }
        try perform(steps)

        var renamed = item
        renamed.markdownURL = newMarkdown
        return renamed
    }

    // Moves the whole entry folder into the top level (`root`) or into an
    // organization folder directly below it. Nothing inside it changes.
    static func move(_ item: LibraryTranscript, to destination: URL, root: URL) throws -> LibraryTranscript {
        try requireManaged(item)
        let isRoot = isSame(destination, root)
        let isFolder = isSame(destination.deletingLastPathComponent(), root)
        guard isRoot || isFolder, isDirectory(destination) else { throw LibraryError.outsideLibrary }

        let folder = item.entryFolderURL
        guard exists(folder) else { throw LibraryError.missing(item.title) }
        if isSame(folder.deletingLastPathComponent(), destination) { return item }

        let target = destination.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
        if exists(target) { throw LibraryError.nameTaken(folder.lastPathComponent) }
        try FileManager.default.moveItem(at: folder, to: target)

        var moved = item
        moved.markdownURL = target.appendingPathComponent(item.markdownURL.lastPathComponent)
        moved.group = isRoot ? nil : destination
        return moved
    }

    // MARK: delete

    // What the confirmation names: every file in the entry folder, with its size.
    static func contents(of item: LibraryTranscript) -> [(name: String, bytes: Int64)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: item.entryFolderURL, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            return (url.lastPathComponent, Int64(values.fileSize ?? 0))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // Moves the whole entry folder to the Trash. If that fails the entry stays
    // where it is: there is no permanent-deletion fallback.
    static func trash(
        _ item: LibraryTranscript,
        using trasher: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws {
        try requireManaged(item)
        guard exists(item.entryFolderURL) else { throw LibraryError.missing(item.title) }
        try trasher(item.entryFolderURL)
    }

    // MARK: helpers

    // The item is a snapshot: refuse when the files on disk are no longer the ones
    // it describes (moved or replaced in Finder since), rather than act on whatever
    // now sits at the path.
    private static func requireManaged(_ item: LibraryTranscript) throws {
        guard item.isManaged else { throw LibraryError.notManaged }
        guard exists(item.markdownURL), isDirectory(item.entryFolderURL) else { throw LibraryError.missing(item.title) }
    }

    private static func exists(_ url: URL) -> Bool {
        (try? url.checkResourceIsReachable()) == true || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    // Asks the file system each time: a URL caches the resource values it has read.
    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard let type = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType,
              type == .typeDirectory,
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }

    // The same file or folder, also when only the case of the name differs on a
    // case-insensitive volume.
    private static func isSame(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let x = try? a.resourceValues(forKeys: key).fileResourceIdentifier as? NSObject,
              let y = try? b.resourceValues(forKeys: key).fileResourceIdentifier as? NSObject else {
            return a.standardizedFileURL.path == b.standardizedFileURL.path
        }
        return x.isEqual(y)
    }

    // Moves each file in turn; if one fails, the ones already moved go back.
    private static func perform(_ steps: [(from: URL, to: URL)]) throws {
        var done: [(from: URL, to: URL)] = []
        do {
            for step in steps {
                try rename(step.from, to: step.to)
                done.append(step)
            }
        } catch {
            for step in done.reversed() { try? rename(step.to, to: step.from) }
            throw error
        }
    }

    // A case-only change is two moves, because the target "exists" as the source.
    private static func rename(_ from: URL, to: URL) throws {
        if exists(to), isSame(from, to) {
            let temporary = from.deletingLastPathComponent()
                .appendingPathComponent(".LocalTranscriber-\(UUID().uuidString).tmp")
            try FileManager.default.moveItem(at: from, to: temporary)
            do {
                try FileManager.default.moveItem(at: temporary, to: to)
            } catch {
                try? FileManager.default.moveItem(at: temporary, to: from)
                throw error
            }
        } else {
            try FileManager.default.moveItem(at: from, to: to)
        }
    }
}

// SourcePackageManifest.manifestFilename; that type is app-only.
nonisolated enum SourcePackageFile {
    static let manifestName = "source.json"
}
