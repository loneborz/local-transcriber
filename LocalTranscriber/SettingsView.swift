import AppKit
import SwiftUI

// A page of the Settings window. Which one shows is kept in memory only (MyApp), so
// the missing-model guidance can open Models; no preference is added for it.
enum SettingsPage: Hashable {
    case general, models, output
}

// The one Settings window (app menu Settings…, ⌘, and the footer entry): native tabs
// (doc-3 Addendum 9). Controls that would change something a running job or recording
// depends on are locked app-wide while it runs (see OutputDestination), with a note
// that says why.
struct SettingsView: View {
    let destination: OutputDestination
    @Binding var page: SettingsPage

    var body: some View {
        TabView(selection: $page) {
            Tab("General", systemImage: "gearshape", value: SettingsPage.general) {
                GeneralSettings()
            }
            Tab("Models", systemImage: "waveform", value: SettingsPage.models) {
                ModelsSettings()
            }
            Tab("Output", systemImage: "folder", value: SettingsPage.output) {
                OutputSettings(destination: destination)
            }
        }
        .frame(width: 480)
        .containerBackground(Theme.paper, for: .window)
        // Here and not on the Whisper section, so it runs when the window opens, as before.
        .onAppear { WhisperModelStore.shared.refresh() }
    }
}

private struct GeneralSettings: View {
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system

    var body: some View {
        VStack(spacing: 12) {
            SettingsCard {
                SettingRow(symbol: "circle.lefthalf.filled", title: "Appearance", labelsControl: true) {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: appearance) { AppAppearance.apply() }
                }
            }
        }
        .settingsPage()
    }
}

private struct ModelsSettings: View {
    // Never locked: a job keeps the engine it was enqueued with (LTR-82).
    @AppStorage(TranscriptionEngine.preferenceKey) private var engine = TranscriptionEngine.appleSpeech

    var body: some View {
        VStack(spacing: 12) {
            SettingsCard {
                SettingRow(symbol: "waveform", title: "Transcription Engine", labelsControl: true) {
                    Picker("Transcription Engine", selection: $engine) {
                        ForEach(TranscriptionEngine.allCases) { engine in
                            // The short name, as in Processing rows; the model card has the full one.
                            Text(engine == .whisper ? "Whisper" : engine.title).tag(engine)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    note("Engine changes apply when an input is added to the queue. Already queued or running jobs keep their assigned engine.")
                    note("Apple Speech is built into macOS. macOS manages its language files and may download one the first time a language is used.")
                }
                .cardNote()
            }

            WhisperSettings()
        }
        .settingsPage()
    }
}

private struct OutputSettings: View {
    let destination: OutputDestination
    @AppStorage(BatchQueue.sourcePackageModeKey) private var savesSourcePackages = false
    @AppStorage(BatchQueue.frontmatterKey) private var addsFrontmatter = false
    @FocusState private var isRevealFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            SettingsCard {
                // Read-only: the footer stays the one place to change the folder (LTR-64).
                folderRow
                note("Change the output folder in the footer of the main window.")
                    .cardNote()
            }

            SettingsCard {
                let youTube = "Save YouTube Links as Source Packages"
                SettingRow(symbol: "link", title: youTube, labelsControl: true) {
                    Toggle(youTube, isOn: $savesSourcePackages)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }
                .disabled(!destination.canChangeSourcePackage)

                rowDivider

                // Read when a transcript is saved, so it never needs a lock.
                let frontmatter = "Add YAML Frontmatter to New Transcripts"
                SettingRow(symbol: "doc.text", title: frontmatter, labelsControl: true) {
                    Toggle(frontmatter, isOn: $addsFrontmatter)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }

                if let lockNote {
                    note(lockNote)
                        .cardNote()
                }
            }
        }
        .settingsPage()
    }

    @ViewBuilder
    private var folderRow: some View {
        switch destination.status {
        case .none:
            SettingRow(symbol: "folder", title: "Output Folder") {
                Text("Not chosen")
            } trailing: {
                EmptyView()
            }
        case .ready(let url):
            let path = url.path(percentEncoded: false)
            // Reveal never changes the destination, so it stays available while locked.
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                SettingRow(symbol: "folder", title: "Output Folder") {
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } trailing: {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(RowButtonStyle())
            // The system ring is drawn on the rectangle and would stick out past the
            // card's rounded corners, so the row draws it on its own shape.
            .focusEffectDisabled()
            .focused($isRevealFocused)
            .overlay {
                if isRevealFocused {
                    RoundedRectangle(cornerRadius: 10)
                        .inset(by: 4)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
            .help(path)
            .accessibilityLabel("Reveal output folder in Finder")
            .accessibilityValue(path)
        case .unavailable(let message):
            SettingRow(symbol: "folder", title: "Output Folder") {
                Text(message)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } trailing: {
                EmptyView()
            }
        }
    }

    private var lockNote: String? {
        destination.isTranscribing ? "This setting can’t change while the queue is running." : nil
    }
}

// The optional Whisper Large V3 Turbo model (LTR-76, doc-3 Addendum 8 D2-D4, D8):
// status, the user-started download, disk use and removal.
private struct WhisperSettings: View {
    @State private var confirmsRemoval = false
    @State private var removalError: String?
    private var store: WhisperModelStore { .shared }

    var body: some View {
        SettingsCard {
            SettingRow(symbol: "square.stack.3d.up", title: "Whisper Large V3 Turbo", isHeading: true) {
                HStack(spacing: 5) {
                    if let statusColor {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    Text(summary)
                        .lineLimit(1)
                }
            } trailing: {
                switch store.state {
                case .downloading:
                    Button("Cancel Download") { store.cancel() }
                        .controlSize(.small)
                case .verifying:
                    ProgressView().controlSize(.small)
                case .installed:
                    Button("Remove Whisper Large V3 Turbo", systemImage: "trash") { confirmsRemoval = true }
                        .labelStyle(.iconOnly)
                        .help("Remove Whisper Large V3 Turbo…")
                        .disabled(store.isInUse)
                case .notInstalled, .failed:
                    Button("Download (\(store.totalBytes.formatted(.byteCount(style: .file))))") { store.download() }
                        .controlSize(.small)
                }
            }

            switch store.state {
            case .downloading(let received, let total):
                ProgressView(value: Double(received), total: Double(total)) {
                    Text("\(received.formatted(.byteCount(style: .file))) of \(total.formatted(.byteCount(style: .file)))")
                        .font(.caption)
                        .monospacedDigit()
                }
                .cardNote()
            case .verifying:
                EmptyView()
            case .installed:
                if store.isInUse {
                    note("The model can’t be removed while a Whisper job is waiting or running.")
                        .cardNote()
                }
            case .notInstalled, .failed:
                VStack(alignment: .leading, spacing: 4) {
                    // The whole reason, in full contrast (LTR-83); the row above keeps one line.
                    if case .failed(let reason) = store.state {
                        Text(reason)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    note("Downloaded from Hugging Face (argmaxinc/whisperkit-coreml, a fixed version) only when you choose Download, and checked file by file. Transcription itself never uses the network.")
                }
                .cardNote()
            }

            if let removalError {
                note(removalError)
                    .cardNote()
            }
        }
        .alert("Remove Whisper Large V3 Turbo?", isPresented: $confirmsRemoval) {
            Button("Remove", role: .destructive) {
                do { try store.remove() } catch { removalError = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The downloaded model files are deleted from this Mac. A compiled copy that macOS keeps in its own caches may remain. Transcripts and media stay as they are. You can download the model again later.")
        }
    }

    // The status, and the disk use once installed. The Core ML compile cache is the
    // system's; its size is not shown (LTR-76 F2).
    private var summary: String {
        guard let usage = store.diskUsage else { return status }
        return "\(status) · \(usage.formatted(.byteCount(style: .file)))"
    }

    private var statusColor: Color? {
        switch store.state {
        case .installed where !store.isPreparing: .green
        case .failed: .red
        default: nil
        }
    }

    private var status: String {
        switch store.state {
        case .notInstalled: "Not installed"
        case .downloading: "Downloading"
        case .verifying: "Verifying"
        case .installed where store.isPreparing: "Preparing"
        case .installed where store.isPrepared: "Ready"
        case .installed: "Installed, prepared at first use"
        case .failed: "Failed"
        }
    }
}

// A raised card on the Paper ground, the same surface as the main window's (doc-2).
private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised)
        .surface()
    }
}

// The one row of every page: a wine symbol, a title with an optional secondary line,
// and a trailing control. With `labelsControl` the control carries the title as its
// accessible name, so the visible title is not read a second time.
private struct SettingRow<Subtitle: View, Trailing: View>: View {
    let symbol: String
    let title: String
    var labelsControl = false
    var isHeading = false
    @ViewBuilder let subtitle: Subtitle
    @ViewBuilder let trailing: Trailing
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.emphasis)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                    .foregroundStyle(isEnabled ? .primary : .tertiary)
                    .accessibilityHidden(labelsControl)
                    .accessibilityAddTraits(isHeading ? .isHeader : [])
                subtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

extension SettingRow where Subtitle == EmptyView {
    init(symbol: String, title: String, labelsControl: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.init(symbol: symbol, title: title, labelsControl: labelsControl, subtitle: { EmptyView() }, trailing: trailing)
    }
}

// A whole row that acts as one button, with hover and press feedback.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .background(
                    Color.primary.opacity(configuration.isPressed ? 0.1 : isHovered ? 0.05 : 0),
                    in: RoundedRectangle(cornerRadius: 10).inset(by: 4)
                )
                .onHover { isHovered = $0 }
        }
    }
}

private var rowDivider: some View {
    Theme.rule
        .frame(height: 1)
        .padding(.leading, 44)
        .padding(.trailing, 14)
        .accessibilityHidden(true)
}

private extension View {
    // The one page margin, as tall as its content.
    func settingsPage() -> some View {
        padding(20)
            .fixedSize(horizontal: false, vertical: true)
    }

    // Secondary text or progress at the bottom of a card.
    func cardNote() -> some View {
        padding(.horizontal, 14)
            .padding(.bottom, 12)
    }
}

private func note(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
}
