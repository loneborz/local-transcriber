import AppKit
import SwiftUI

// What the sidebar has selected. New Transcription and an In progress job both
// show the queue; a transcript shows the Review view. A pinned transcript is
// listed twice (Pinned and its folder): the two rows are one transcript, and
// `.pinned` only says which row carries the highlight.
enum SidebarSelection: Hashable {
    case newTranscription
    case transcript(LibraryTranscript.ID)
    case pinned(LibraryTranscript.ID)

    var transcriptID: LibraryTranscript.ID? {
        switch self {
        case .transcript(let id), .pinned(let id): id
        case .newTranscription: nil
        }
    }

    // The same kind of row for another transcript (after a rename or move).
    func replacingTranscript(with id: LibraryTranscript.ID) -> SidebarSelection {
        if case .pinned = self { .pinned(id) } else { .transcript(id) }
    }
}

// What a menu, a key or the Transcript menu asks the library to do. The window
// carries it out (it owns the prompts, the selection and the player).
enum LibraryRequest {
    case rename(LibraryTranscript)
    case togglePin(LibraryTranscript)
    case toggleArchive(LibraryTranscript)
    // `nil` moves the entry out of its folder, to the top level.
    case move(LibraryTranscript, to: LibraryFolder?)
    case newFolder(moving: LibraryTranscript?)
    case trash(LibraryTranscript)
    case renameFolder(LibraryFolder)
    case trashFolder(LibraryFolder)
}

// What the Transcript menu can act on: the open transcript, if any. Equal when the
// menu would show the same, from the same window; `request` is left out, like
// WindowAction's closure (LTR-68).
struct LibraryCommands: Equatable {
    var window: UUID
    var selected: LibraryTranscript?
    var canCreateFolder: Bool
    var request: (LibraryRequest) -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.window == b.window && a.selected == b.selected && a.canCreateFolder == b.canCreateFolder
    }
}

// One sidebar for the live queue and the saved transcripts (doc-3). Native list
// and sidebar styling; sentence-case section headers; no custom selection colour.
// Library: Pinned, Folders (real folders), Recent (not in a folder), Archive.
struct WorkspaceSidebar: View {
    let queue: BatchQueue
    let jobs: [TranscriptionJob]
    let processing: ProcessingActions
    // While this window records: the recording's status and Stop, wherever the user is.
    let recordingBanner: AnyView?
    let library: LibraryStore
    let destination: OutputDestination.Status
    @Binding var selection: SidebarSelection?
    let onNewTranscription: () -> Void
    let onRefresh: () -> Void
    let onRequest: (LibraryRequest) -> Void

    @State private var collapsedFolders: Set<String> = []
    @State private var archiveExpanded = false
    // The folder a drag is currently over, for the quiet highlight.
    @State private var dropTarget: String?

    var body: some View {
        let sections = library.sections
        List(selection: $selection) {
            if let recordingBanner {
                Section("Recording") {
                    recordingBanner.selectionDisabled()
                }
            }

            if !jobs.isEmpty {
                ProcessingSection(queue: queue, jobs: jobs, actions: processing)
            }

            if !sections.pinned.isEmpty {
                Section("Pinned") {
                    ForEach(sections.pinned) { item in
                        row(item, showsFolder: true, tag: .pinned(item.id))
                    }
                }
            }

            if !sections.recent.isEmpty || library.items.isEmpty && sections.folders.isEmpty {
                Section {
                    if library.items.isEmpty {
                        Text(emptyMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .selectionDisabled()
                            .contextMenu { refreshMenu }
                    } else {
                        ForEach(sections.recent) { row($0, showsFolder: false, tag: .transcript($0.id)) }
                    }
                } header: {
                    // A header's menu covers only the header, so the rows carry it too.
                    Text("Recent")
                        .contextMenu { refreshMenu }
                }
            }

            if !sections.folders.isEmpty {
                Section("Folders") {
                    ForEach(sections.folders, id: \.folder.id) { folderRow($0) }
                }
            }

            if !sections.archived.isEmpty {
                Section("Archive", isExpanded: $archiveExpanded) {
                    ForEach(sections.archived) { row($0, showsFolder: true, tag: .transcript($0.id)) }
                }
            }
        }
        .listStyle(.sidebar)
        // One warm ground for both appearances (see Theme.sidebar).
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { newButton }
        .accessibilityLabel("Transcription sidebar")
        // isTargeted is not always told when a drag ends away from its target (a drop beside
        // the row, a cancel), so the highlight also ends once no mouse button is down.
        .task(id: dropTarget) {
            while dropTarget != nil, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                if NSEvent.pressedMouseButtons == 0 { dropTarget = nil }
            }
        }
        // The Delete key asks to move the selected transcript to the Trash.
        .onDeleteCommand {
            if let id = selection?.transcriptID,
               let item = library.items.first(where: { $0.id == id }), item.isManaged {
                onRequest(.trash(item))
            }
        }
    }

    private var newButton: some View {
        NewControl(
            onNewTranscription: onNewTranscription,
            onNewFolder: { onRequest(.newFolder(moving: nil)) })
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.sidebar)
    }

    @ViewBuilder
    private func row(_ item: LibraryTranscript, showsFolder: Bool, tag: SidebarSelection) -> some View {
        let base = SidebarTranscriptRow(item: item, showsFolder: showsFolder)
            .tag(tag)
            .contextMenu { entryMenu(item) }
        // The entry's id (its path) is the payload. Legacy v0.6 layouts are never
        // changed by the app, so they are not draggable.
        // A small title-only preview: the default one is the whole row (selection blue
        // included), which covers the folders it is being dragged over.
        if item.isManaged {
            base.draggable(item.id) {
                Text(item.title)
                    .font(.callout)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        } else { base }
    }

    private func folderRow(_ group: LibrarySections.Group) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { !collapsedFolders.contains(group.folder.id) },
            set: { open in
                if open { collapsedFolders.remove(group.folder.id) } else { collapsedFolders.insert(group.folder.id) }
            })
        ) {
            ForEach(group.entries) { row($0, showsFolder: false, tag: .transcript($0.id)) }
        } label: {
            folderLabel(group.folder)
        }
    }

    private func folderLabel(_ folder: LibraryFolder) -> some View {
        Label(folder.name, systemImage: "folder")
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)
            // The whole row, not just the icon and the name, is the drop target.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.accentColor.opacity(dropTarget == folder.id ? 0.18 : 0), in: RoundedRectangle(cornerRadius: 6))
            // Organization folders are the only drop targets. The drop is the same
            // request as Move to, so its guards, collision rule and errors apply.
            .dropDestination(for: String.self) { ids, _ in
                // A drop ends the targeting whatever the outcome (isTargeted may not report
                // the end when the move raises a prompt right away).
                dropTarget = nil
                guard ids.count == 1,
                      let item = library.items.first(where: { $0.id == ids[0] }), item.isManaged else { return false }
                // Already there: nothing to change on disk.
                if item.group?.standardizedFileURL == folder.url.standardizedFileURL { return false }
                onRequest(.move(item, to: folder))
                return true
            } isTargeted: { targeted in
                if targeted { dropTarget = folder.id } else if dropTarget == folder.id { dropTarget = nil }
            }
            .contextMenu {
                Button("Rename Folder…") { onRequest(.renameFolder(folder)) }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                }
                Divider()
                Button("Move to Trash…", role: .destructive) { onRequest(.trashFolder(folder)) }
            }
    }

    @ViewBuilder
    private func entryMenu(_ item: LibraryTranscript) -> some View {
        if item.isManaged {
            Button("Rename…") { onRequest(.rename(item)) }
            Button(item.isPinned ? "Unpin" : "Pin") { onRequest(.togglePin(item)) }
            Button(item.isArchived ? "Unarchive" : "Archive") { onRequest(.toggleArchive(item)) }
            Menu("Move to") {
                if item.group != nil {
                    Button("No Folder") { onRequest(.move(item, to: nil)) }
                }
                ForEach(library.folders.filter { $0.url.standardizedFileURL != item.group?.standardizedFileURL }) { folder in
                    Button(folder.name) { onRequest(.move(item, to: folder)) }
                }
                Divider()
                Button("New Folder…") { onRequest(.newFolder(moving: item)) }
            }
            Divider()
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([item.markdownURL])
        }
        if item.isManaged {
            Button("Move to Trash…", role: .destructive) { onRequest(.trash(item)) }
        }
        Divider()
        refreshMenu
    }

    // The same refresh as View › Refresh Transcripts (⌘R).
    private var refreshMenu: some View {
        Button("Refresh Transcripts", action: onRefresh)
    }

    // Quiet and specific: it says why the list is empty, and what fills it.
    private var emptyMessage: String {
        switch destination {
        case .none:
            "Choose an output folder to see saved transcripts here."
        case .unavailable:
            "The output folder is unavailable, so its transcripts can’t be listed."
        case .ready:
            if let error = library.loadError {
                "Couldn’t read the output folder: \(error)"
            } else if library.isLoading {
                "Looking for transcripts…"
            } else {
                "Transcripts saved in this folder appear here."
            }
        }
    }
}

private struct SidebarTranscriptRow: View {
    let item: LibraryTranscript
    // Pinned and archived entries are listed away from their folder, so they say where it is.
    let showsFolder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(item.title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.isNew { NewBadge() }
            }
            Text(detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(item.createdAt.map { "Created \($0.formatted(date: .long, time: .shortened))" }
            ?? "Saved \(item.savedAt.formatted(date: .long, time: .shortened))")
        .accessibilityElement(children: .combine)
    }

    // Folder (when away from it), the creation date (else the save date), then the length.
    private var detail: String {
        var parts: [String] = []
        if showsFolder, let group = item.group { parts.append(group.lastPathComponent) }
        parts.append(item.sortDate.formatted(date: .abbreviated, time: .shortened))
        if let duration = item.header.duration { parts.append(TimestampFormat.string(duration)) }
        return parts.joined(separator: " · ")
    }
}

// The creation control at the top of the sidebar: one full-width "New" button that
// expands, inline, into the things that can be created. More actions can be added
// to the panel later.
private struct NewControl: View {
    let onNewTranscription: () -> Void
    let onNewFolder: () -> Void

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let radius: CGFloat = 10

    var body: some View {
        VStack(spacing: 6) {
            Button { set(!isExpanded) } label: {
                Label("New", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .accessibilityHidden(true)
                    }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: Self.radius))
            .controlSize(.large)
            .accessibilityLabel("New")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows New Transcription and New Folder")

            if isExpanded {
                VStack(spacing: 2) {
                    PanelRow(title: "New Transcription", symbol: "waveform") { choose(onNewTranscription) }
                    PanelRow(title: "New Folder…", symbol: "folder.badge.plus") { choose(onNewFolder) }
                }
                .padding(4)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Self.radius))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.radius)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onExitCommand { set(false) }
    }

    private func set(_ expanded: Bool) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { isExpanded = expanded }
    }

    // Does the action, and folds the panel away.
    private func choose(_ action: () -> Void) {
        set(false)
        action()
    }
}

private struct PanelRow: View {
    let title: String
    let symbol: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // A fixed icon column keeps the titles aligned.
                Image(systemName: symbol)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(title)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.accentColor.opacity(isHovered ? 0.18 : 0), in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
    }
}

// "New": saved by a transcription and not opened yet. Small and quiet; on a selected
// row it turns white so it stays readable on the selection colour.
private struct NewBadge: View {
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text("New")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(prominence == .increased ? Color.white : Color.accentColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                (prominence == .increased ? Color.white : Color.accentColor).opacity(0.18),
                in: Capsule())
            .fixedSize()
    }
}
