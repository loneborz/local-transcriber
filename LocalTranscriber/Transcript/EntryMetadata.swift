import Foundation
import UniformTypeIdentifiers

// The small metadata file inside an entry folder: `entry.json`. It is the only
// library metadata there is: no database, no index. It lives in the folder, so a
// rename, move or copy in Finder carries it along. Schema version 1:
//
// {
//   "schemaVersion": 1,
//   "createdAt": "2026-10-16T12:00:00Z",   (omitted when unknown)
//   "pinned": true,                        (omitted when false)
//   "archived": true,                      (omitted when false)
//   "unopened": true                       (omitted when false)
// }
//
// `createdAt` is written once, at creation: the start of a recording, the moment
// an imported file's entry was created, or the moment a YouTube link was
// acquired. It is never the file modification date. The title is the folder
// name and is not stored. `unopened` marks a transcript the app saved and nobody has
// opened yet (the "New" badge): set when a transcription is saved, cleared when the
// transcript is opened. An entry without it was never new.
nonisolated struct EntryMetadata: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let fileName = "entry.json"
    // A real file is a few hundred bytes; anything bigger is not ours.
    static let maxBytes = 64 * 1024

    var schemaVersion: Int
    var createdAt: Date?
    var pinned: Bool
    var archived: Bool
    var unopened: Bool

    init(createdAt: Date?, pinned: Bool = false, archived: Bool = false, unopened: Bool = false) {
        schemaVersion = Self.currentSchemaVersion
        self.createdAt = createdAt
        self.pinned = pinned
        self.archived = archived
        self.unopened = unopened
    }

    private enum Keys: String, CodingKey { case schemaVersion, createdAt, pinned, archived, unopened }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        unopened = try c.decodeIfPresent(Bool.self, forKey: .unopened) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        if pinned { try c.encode(true, forKey: .pinned) }
        if archived { try c.encode(true, forKey: .archived) }
        if unopened { try c.encode(true, forKey: .unopened) }
    }

    // Deterministic: sorted keys, trailing newline.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self) + Data("\n".utf8)
    }

    // Reads the version first, so a file from a newer app reports an unsupported
    // version instead of a confusing decoding error.
    static func decode(_ data: Data) -> State {
        struct Probe: Decodable { var schemaVersion: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let version = try decoder.decode(Probe.self, from: data).schemaVersion
            guard version == currentSchemaVersion else { return .unsupported(version) }
            return .valid(try decoder.decode(EntryMetadata.self, from: data))
        } catch {
            return .unreadable
        }
    }

    // What the folder's `entry.json` says. Anything but `valid` leaves the
    // transcript listed and readable; the library then relies on the files alone.
    enum State: Equatable, Sendable {
        case missing
        case valid(EntryMetadata)
        case unreadable
        case unsupported(Int)

        var metadata: EntryMetadata? {
            if case .valid(let metadata) = self { metadata } else { nil }
        }
    }

    static func read(in folder: URL) -> State {
        let url = folder.appendingPathComponent(fileName)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return .missing }
        guard values.isRegularFile == true, let size = values.fileSize, size <= maxBytes,
              let data = try? Data(contentsOf: url) else { return .unreadable }
        return decode(data)
    }

    // A new entry's file: never replaces an existing one.
    static func create(_ metadata: EntryMetadata, _ folder: URL) throws {
        try metadata.encoded().write(to: folder.appendingPathComponent(fileName), options: .withoutOverwriting)
    }

    // Replaces an existing, readable file in one atomic step. A file that is
    // malformed or from a newer app is never replaced.
    static func update(in folder: URL, _ change: (inout EntryMetadata) -> Void) throws {
        switch read(in: folder) {
        case .valid(var metadata):
            change(&metadata)
            try metadata.encoded().write(to: folder.appendingPathComponent(fileName), options: .atomic)
        case .missing:
            // Entries made without one (its write failed) get one now; the
            // creation time stays unknown rather than invented.
            var metadata = EntryMetadata(createdAt: nil)
            change(&metadata)
            try create(metadata, folder)
        case .unreadable:
            throw LibraryError.metadataUnreadable
        case .unsupported:
            throw LibraryError.metadataUnsupported
        }
    }
}

// Names the app gives to entry folders, Markdown files and organization folders.
nonisolated enum EntryName {
    // APFS allows 255 UTF-8 bytes; "<name> 9999.timing.json" has to fit too.
    static let maxBytes = 120

    // A name derived from something else (a media file, a video title): always
    // produces a safe name, never an error.
    static func sanitized(_ raw: String, fallback: String = "Untitled") -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            switch scalar {
            case "/", ":": scalars.append("-")
            case _ where scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .format:
                scalars.append(" ")
            default: scalars.append(scalar)
            }
        }
        var name = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.utf8.count > maxBytes { name.removeLast() }
        name = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        // "Talk.app" would be a package to macOS, and the scan skips packages.
        if isPackageName(name), let dot = name.lastIndex(of: ".") { name.replaceSubrange(dot...dot, with: "-") }
        return name.isEmpty ? fallback : name
    }

    // The usual ones, in case the type database does not know an extension.
    private static let knownPackageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "xpc", "appex", "rtfd", "pkg", "mpkg", "photoslibrary",
        "xcodeproj", "xcworkspace", "playground", "docset", "prefpane", "saver", "workflow", "sparsebundle",
        "pages", "numbers", "key", "band", "logicx", "dsym", "lproj",
    ]

    // A folder with this extension is shown as one file (an app, a bundle…).
    static func isPackageName(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        if knownPackageExtensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .package) || type.conforms(to: .bundle)
    }

    // A name the user typed: accepted as is (trimmed) or refused with a reason.
    static func validated(_ raw: String) -> Result<String, LibraryError> {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .failure(.invalidName("The name is empty.")) }
        if name.hasPrefix(".") { return .failure(.invalidName("A name can’t start with a dot.")) }
        if name.contains("/") || name.contains(":") {
            return .failure(.invalidName("A name can’t contain “/” or “:”."))
        }
        if name.unicodeScalars.contains(where: {
            $0.properties.generalCategory == .control || $0.properties.generalCategory == .format
        }) {
            return .failure(.invalidName("A name can’t contain control characters."))
        }
        if name.utf8.count > maxBytes { return .failure(.invalidName("The name is too long.")) }
        if isPackageName(name) {
            return .failure(.invalidName("A name can’t end in “.\((name as NSString).pathExtension)”: macOS shows such folders as a single file."))
        }
        return .success(name)
    }
}

nonisolated enum LibraryError: LocalizedError, Equatable {
    case invalidName(String)
    case nameTaken(String)
    case notManaged
    case outsideLibrary
    case metadataUnreadable
    case metadataUnsupported
    case missing(String)
    case tooManyCollisions
    case folderHasOtherFiles(String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let reason): reason
        case .nameTaken(let name): "“\(name)” already exists there. Nothing was changed."
        case .notManaged: "This transcript was saved by an earlier version and can only be managed in Finder."
        case .outsideLibrary: "That location is not in the library."
        case .metadataUnreadable: "The entry’s entry.json can’t be read, so it was left as it is."
        case .metadataUnsupported: "The entry’s entry.json is from a newer version, so it was left as it is."
        case .folderHasOtherFiles(let name): "“\(name)” holds files that Local Transcriber didn’t create, so it wasn’t moved to the Trash."
        case .tooManyCollisions: "Too many items with this name already exist."
        case .missing(let name): "“\(name)” is no longer there. Refresh the library."
        }
    }
}
