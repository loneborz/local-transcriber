import AppKit
import SwiftUI

// A saved transcript, read-only, in the detail pane. The Markdown file is the
// authority for the text; timestamps appear only when its timing sidecar is
// valid for these exact bytes (see TranscriptReview). Nothing here writes.
struct TranscriptReviewView: View {
    let item: LibraryTranscript
    // The window's one player; it shows state for this transcript only while it
    // is the one that was prepared (`player.itemID == item.id`).
    let player: AudioReviewPlayer

    private enum Phase {
        case loading
        case loaded(TranscriptReview)
        case failed(String)
    }

    @State private var phase = Phase.loading
    // Confirmation lives in this view only; every click restarts the reset task.
    @State private var copied = false
    @State private var copyClicks = 0
    @State private var copyFailed = false
    // Follow-along: on while playback should keep the active line in view; the
    // user scrolling away turns it off, Jump to Playing (or a new play) turns it on.
    @State private var following = true
    @State private var activeLineVisible = true
    @State private var visibleLines = VisibleLines()
    @State private var scrubbing = false
    @State private var scrubTime = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if copyFailed {
                Text("Could not copy the transcript to the clipboard.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }

            audioStatus

            if let notice {
                Label {
                    Text(notice)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                        .accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }

            transcript
        }
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        // Reloads when another transcript is chosen or the file changed on disk, not
        // when only its library state (pinned, archived) changed: that must not stop playback.
        .task(id: ReloadKey(url: item.markdownURL, savedAt: item.savedAt)) { await load() }
    }

    private var loaded: TranscriptReview? {
        if case .loaded(let review) = phase { review } else { nil }
    }

    private var notice: String? { loaded?.state.notice }

    // MARK: header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                Text(metadata)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                copy()
            } label: {
                // The hidden "Copied" reserves its width so the button does not shift.
                ZStack {
                    Text("Copied").hidden()
                    Text(copied ? "Copied" : "Copy")
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("Copy the transcript as Markdown (⇧⌘C)")
            .accessibilityLabel("Copy transcript as Markdown")
            .accessibilityValue(copied ? "Copied" : "")
            .task(id: copyClicks) {
                guard copied else { return }
                try? await Task.sleep(for: .milliseconds(1500))
                if !Task.isCancelled { copied = false }
            }

            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.markdownURL])
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("Show the Markdown file in Finder (⇧⌘R)")
            .accessibilityLabel("Reveal transcript in Finder")
        }
        .padding(.horizontal, 4)
    }

    // "Created <date>" when the entry records one; otherwise "Saved <date>" with the
    // file's save date. Then length, language and transcriber, from the header.
    private var metadata: String {
        let header = loaded?.header ?? item.header
        var parts = [item.createdAt.map { "Created \($0.formatted(date: .abbreviated, time: .shortened))" }
                     ?? "Saved \(item.savedAt.formatted(date: .abbreviated, time: .shortened))"]
        if let duration = header.duration { parts.append(TimestampFormat.string(duration)) }
        if let language = header.language {
            parts.append(Locale.current.localizedString(forIdentifier: language) ?? language)
        }
        if let transcriber = header.transcriber { parts.append(transcriber) }
        return parts.joined(separator: " · ")
    }

    // MARK: body

    @ViewBuilder
    private var transcript: some View {
        switch phase {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
        case .loaded(let review):
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        switch review.body {
                        case .timed(let lines):
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                TimedLineRow(
                                    line: line,
                                    isActive: ownsPlayer && player.activeLine == index,
                                    canSeek: canSeek && line.start != nil,
                                    onSeek: { seek(to: line, proxy: proxy) }
                                )
                                .id(index)
                                .onScrollVisibilityChange(threshold: 0.5) { visible in
                                    noteVisibility(of: index, visible)
                                }
                            }
                        case .markdown(let blocks):
                            if blocks.isEmpty {
                                emptyTranscript
                            }
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                MarkdownBlockRow(block: block)
                            }
                        }
                    }
                    .padding(12)
                }
                // A phase of .interacting or .decelerating is the user's own scrolling;
                // scrollTo from here reports .animating (or nothing), so it never
                // turns follow-along off by mistake.
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting || phase == .decelerating { following = false }
                }
                .onChange(of: player.activeLine) { _, line in
                    visibilityChanged()
                    if following, player.isPlaying, let line { scroll(to: line, proxy: proxy) }
                }
                .onChange(of: player.isPlaying) { _, playing in
                    if playing { following = true }
                }
                .background(Theme.raised)
                .surface()
                .overlay(alignment: .bottom) {
                    if showsJump {
                        Button {
                            following = true
                            if let line = player.activeLine { scroll(to: line, proxy: proxy) }
                        } label: {
                            Label("Jump to Playing", systemImage: "arrow.down.to.line")
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 10)
                        .help("Scroll to the line being played and follow it again")
                    }
                }
            }
        }
    }

    // MARK: audio

    private var ownsPlayer: Bool { player.itemID == item.id }
    private var canSeek: Bool { ownsPlayer && player.isReady }

    // Visible only when the user has left the playing line behind.
    private var showsJump: Bool {
        ownsPlayer && player.isReady && !following && player.activeLine != nil && !activeLineVisible
    }

    @ViewBuilder
    private var audioStatus: some View {
        if loaded != nil, ownsPlayer {
            switch player.phase {
            case .none:
                EmptyView()
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading audio…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            case .unavailable(let availability):
                if let statement = availability.statement {
                    Label {
                        Text(statement).textSelection(.enabled)
                    } icon: {
                        Image(systemName: "speaker.slash").accessibilityHidden(true)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                }
            case .ready:
                playerBar
            }
            if let error = player.playbackError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var playerBar: some View {
        HStack(spacing: 10) {
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : (player.hasFinished ? "arrow.counterclockwise" : "play.fill"))
                    .frame(width: 16, height: 16)
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .help(player.isPlaying ? "Pause (⌥⌘P)" : "Play (⌥⌘P)")
            .accessibilityLabel(player.isPlaying ? "Pause" : (player.hasFinished ? "Play from start" : "Play"))

            Text(TimestampFormat.string(scrubbing ? scrubTime : player.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)

            Slider(
                // While the mouse drags, only the thumb moves and the seek happens on release.
                // Any other change (VoiceOver, keyboard arrows) is a finished gesture: seek now.
                value: Binding(
                    get: { scrubbing ? scrubTime : player.currentTime },
                    set: { value in
                        if scrubbing { scrubTime = value } else { player.seek(to: value) }
                    }),
                in: 0...max(player.duration, 0.1)
            ) { editing in
                if editing { scrubTime = player.currentTime }
                scrubbing = editing
                if !editing { player.seek(to: scrubTime) }
            }
            .controlSize(.small)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(TimestampFormat.string(scrubbing ? scrubTime : player.currentTime)) of \(TimestampFormat.string(player.duration))")

            Text(TimestampFormat.string(player.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.raised)
        .surface()
    }

    // A click on a timestamp: seek there and play, and follow again.
    private func seek(to line: ReviewLine, proxy: ScrollViewProxy) {
        guard player.play(from: line) else { return }
        following = true
        if let active = player.activeLine { scroll(to: active, proxy: proxy) }
    }

    private func scroll(to line: Int, proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(line, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(line, anchor: .center) }
        }
    }

    // Which rows are on screen, kept outside observation so scrolling does not
    // re-render the list; only the "active line visible" flag is published.
    private func noteVisibility(of index: Int, _ visible: Bool) {
        if visible { visibleLines.rows.insert(index) } else { visibleLines.rows.remove(index) }
        visibilityChanged()
    }

    private func visibilityChanged() {
        let visible = player.activeLine.map { visibleLines.rows.contains($0) } ?? true
        if visible != activeLineVisible { activeLineVisible = visible }
    }

    private var emptyTranscript: some View {
        Text("No speech was recognized in this recording.")
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }

    // MARK: actions

    // Reads the file again so the clipboard gets what is on disk now, byte for
    // byte as text without a leading YAML block (LTR-37); nothing is regenerated
    // from the parsed transcript.
    private func copy() {
        copyClicks += 1
        guard let data = try? Data(contentsOf: item.markdownURL),
              let text = String(data: data, encoding: .utf8) else {
            copied = false
            copyFailed = true
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        copied = pasteboard.setString(TranscriptMarkdown.withoutFrontmatter(text), forType: .string)
        copyFailed = !copied
    }

    private func load() async {
        phase = .loading
        copied = false
        copyFailed = false
        let item = item
        // File reads and the sidecar decode stay off the main thread.
        let result = await Task.detached(priority: .userInitiated) {
            Result { try TranscriptReview.load(item) }
        }.value
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let review):
            phase = .loaded(review)
            following = true
            visibleLines.rows.removeAll()
            // Only valid, matching timing makes lines seekable; otherwise audio (if any)
            // plays but no line is a seek target.
            var lines: [ReviewLine] = []
            if case .timed(let timed) = review.body { lines = timed }
            await player.prepare(for: item, transcriptDuration: review.header.duration, lines: lines)
        case .failure(let error):
            phase = .failed("This transcript can’t be opened: \(error.localizedDescription)")
        }
    }
}

// A sidecar-derived line: its start time (a button when the audio can be played
// from there), then the text. The active line is marked with the system accent.
private struct TimedLineRow: View {
    let line: ReviewLine
    let isActive: Bool
    let canSeek: Bool
    let onSeek: () -> Void

    private var time: String? { line.start.map(TimestampFormat.string) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if canSeek, let time {
                Button(action: onSeek) {
                    Text(time)
                        .font(.caption.monospacedDigit())
                        .underline(true, color: .secondary.opacity(0.5))
                        .frame(width: 52, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .foregroundStyle(.secondary)
                .help("Play from \(time)")
                .accessibilityLabel("Play from \(time)")
            } else {
                Text(time ?? "")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
                    .accessibilityHidden(time == nil)
            }
            Text(line.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        // A click anywhere on a seekable line plays from it. Dragging to select
        // text is not a tap, so selection is left alone; the extra clicks of a
        // double or triple click (word or line selection) do not seek again.
        // Simultaneous because selectable text swallows a plain onTapGesture.
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            if canSeek, (NSApp.currentEvent?.clickCount ?? 1) <= 1 { onSeek() }
        })
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 3)
                    }
            }
        }
        .accessibilityElement(children: canSeek ? .contain : .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// Rows on screen. A reference type held in @State: mutating it publishes nothing.
private final class VisibleLines {
    var rows = Set<Int>()
}

// The Markdown as saved. A minute heading is shown as a heading, never as a
// sentence time.
private struct MarkdownBlockRow: View {
    let block: TranscriptMarkdown.Block

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let heading = block.heading {
                Text(heading)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
            }
            if !block.text.isEmpty {
                Text(block.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ReloadKey: Equatable {
    var url: URL
    var savedAt: Date
}
