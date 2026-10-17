import SwiftUI

// The one Settings window (app menu Settings…, ⌘, and the footer entry). Native
// look: a single Form today (the default language and the output folder live in the footer, next to
// where they are used); a second category would bring back a TabView. Controls that would change
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
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .onChange(of: appearance) { AppAppearance.apply() }

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

    private var lockNote: String? {
        destination.isTranscribing ? "This setting can’t change while the queue is running." : nil
    }
}
