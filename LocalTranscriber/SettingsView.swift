import SwiftUI

// The one Settings window (app menu Settings…, ⌘, and the footer entry). Native
// look: a single Form today (the default language lives in the footer, next to
// where it is used); a second category would bring back a TabView. Controls that would change
// something a running job or recording depends on are locked app-wide while it
// runs (see OutputDestination), with a note that says why.
struct SettingsView: View {
    let destination: OutputDestination

    var body: some View {
        GeneralSettings(destination: destination)
            .frame(width: 480)
    }
}

private struct GeneralSettings: View {
    let destination: OutputDestination
    @AppStorage(BatchQueue.sourcePackageModeKey) private var savesSourcePackages = false

    var body: some View {
        Form {
            LabeledContent("Output folder") {
                VStack(alignment: .leading, spacing: 6) {
                    folder
                    Button(destination.isReady ? "Change…" : "Choose…") {
                        destination.choose()
                    }
                    .disabled(!destination.canChangeFolder)
                }
            }

            Toggle("Save YouTube Links as Source Packages", isOn: $savesSourcePackages)
                .disabled(!destination.canChangeSourcePackage)

            if let lockNote {
                Text(lockNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var folder: some View {
        switch destination.status {
        case .none:
            Text("None").foregroundStyle(.secondary)
        case .ready(let url):
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                Text(url.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        case .unavailable(let message):
            Text(message).foregroundStyle(.red)
        }
    }

    private var lockNote: String? {
        if destination.isTranscribing {
            "These settings can’t change while the queue is running."
        } else if destination.isRecording {
            "The output folder can’t change while recording."
        } else {
            nil
        }
    }
}
