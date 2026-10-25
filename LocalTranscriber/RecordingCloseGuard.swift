import AppKit
import SwiftUI

// A recording is never discarded silently. Closing the window that holds it and
// quitting both ask first; Stop and Save closes or quits only after the audio is
// seen in the output folder. If the save fails, the window stays and the
// existing "Choose Folder and Save Recording…" button is the way out.
//   - Window close: save, queue the recording (it keeps transcribing in the
//     app-wide queue after the window is gone), then close.
//   - Quit: save the audio only, say that it waits for its language, then quit.
//     The queue is session-only, so a started job would be lost at once.

// NSAlert binds Escape only to a button titled "Cancel". These alerts name their
// safe answer ("Keep Recording", "Keep Window Open"), so a one-point accessory
// view that answers the Escape key gives Escape that answer. A plain view, not a
// button, so VoiceOver does not see an extra control.
private final class EscapeAnswer: NSView {
    private let response: NSApplication.ModalResponse

    init(_ response: NSApplication.ModalResponse) {
        self.response = response
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    required init?(coder: NSCoder) { nil }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.keyCode == 53, let alert = window else { return super.performKeyEquivalent(with: event) }
        if let parent = alert.sheetParent {
            parent.endSheet(alert, returnCode: response)
        } else {
            NSApp.stopModal(withCode: response)
        }
        return true
    }
}

@MainActor
private enum CloseGuardAlert {
    static func escapeKeeps(_ alert: NSAlert, _ response: NSApplication.ModalResponse) {
        alert.accessoryView = EscapeAnswer(response)
    }

    static func make(_ title: String, _ text: String, _ buttons: [String]) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        for button in buttons { alert.addButton(withTitle: button) }
        return alert
    }

    // The first button is the default (Return); the first also answers Escape.
    static func keepOrStop(quitting: Bool) -> NSAlert {
        let alert = make(
            "Recording in progress",
            quitting
                ? "Quitting now would end the recording. Stop and Save saves the audio in your output folder and quits. It does not start transcription."
                : "Closing this window would end the recording. Stop and Save saves the audio and starts transcribing it; transcription continues in the background.",
            ["Keep Recording", "Stop and Save"])
        alert.buttons[0].keyEquivalent = "\r"
        escapeKeeps(alert, .alertFirstButtonReturn)
        return alert
    }

    static func busy(_ protection: Recorder.Protection, quitting: Bool) -> NSAlert {
        let what = protection == .starting ? "The recording is starting." : "The recording is being saved."
        return make(what, "Try again in a moment. \(quitting ? "Local Transcriber stays open" : "The window stays open") until it is done.", ["OK"])
    }

    static func unsaved(quitting: Bool) -> NSAlert {
        let alert = make(
            "The recording isn’t saved",
            quitting
                ? "Local Transcriber can’t quit until the recording is saved in your output folder. Choose a folder to save it; transcription will not start."
                : "This window can’t close until the recording is saved in your output folder. Choose a folder to save it.",
            ["Choose Folder and Save…", "Keep Window Open"])
        alert.buttons[0].keyEquivalent = "\r"
        escapeKeeps(alert, .alertSecondButtonReturn)
        return alert
    }

    // Nothing here can be saved: the capture failed before it could be finalized.
    // Keeping the window is the default and the Escape answer.
    static func failed(_ staging: URL, quitting: Bool) -> NSAlert {
        let path = (staging.path as NSString).abbreviatingWithTildeInPath
        let alert = make(
            "The recording failed",
            "Part of it may remain in \(path), but Local Transcriber can’t save it from here. \(quitting ? "Quitting" : "Closing the window") now leaves it there.",
            ["Keep Window Open", "Show in Finder", quitting ? "Quit Anyway" : "Close Anyway"])
        alert.buttons[0].keyEquivalent = "\r"
        escapeKeeps(alert, .alertFirstButtonReturn)
        return alert
    }

    static func notSaved(_ recorder: Recorder) -> NSAlert {
        make(
            "The recording wasn’t saved",
            "\(recorder.error ?? "The recording couldn’t be saved.") It stays in the window; use “Choose Folder and Save Recording…” there.",
            ["OK"])
    }

    static func savedOnQuit(_ audio: URL) -> NSAlert {
        let path = (audio.path as NSString).abbreviatingWithTildeInPath
        let alert = make(
            "Recording saved",
            "Saved to \(path). It was not transcribed; Local Transcriber asks for its language the next time it opens.",
            ["Quit", "Show in Finder and Quit"])
        alert.buttons[0].keyEquivalent = "\r"
        return alert
    }
}

// MARK: window close

// SwiftUI owns the window's delegate and SwiftUI cannot veto a close, so this
// puts a proxy in front of it: windowShouldClose is ours, every other delegate
// message is forwarded to SwiftUI's own delegate, and the original is put back
// when the proxy goes away.
struct RecordingCloseGuard: NSViewRepresentable {
    let recorder: Recorder

    func makeNSView(context: Context) -> NSView {
        let view = WindowObserver()
        view.onWindow = { [coordinator = context.coordinator] window in coordinator.attach(to: window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.recorder = recorder
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(recorder: recorder) }

    final class WindowObserver: NSView {
        var onWindow: (NSWindow) -> Void = { _ in }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }

    @MainActor
    final class Coordinator {
        var recorder: Recorder
        private var proxy: CloseProxy?

        init(recorder: Recorder) { self.recorder = recorder }

        func attach(to window: NSWindow) {
            guard proxy == nil || proxy?.window !== window else { return }
            detach()
            let proxy = CloseProxy(window: window, original: window.delegate) { [weak self] in self?.recorder }
            window.delegate = proxy
            self.proxy = proxy
        }

        func detach() {
            guard let proxy else { return }
            // Only undo what is still ours; SwiftUI may have set its own since.
            if proxy.window?.delegate === proxy { proxy.window?.delegate = proxy.original }
            self.proxy = nil
        }
    }
}

@MainActor
private final class CloseProxy: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    weak var original: NSWindowDelegate?
    private let recorder: () -> Recorder?
    private var isAsking = false

    init(window: NSWindow, original: NSWindowDelegate?, recorder: @escaping () -> Recorder?) {
        self.window = window
        self.original = original
        self.recorder = recorder
    }

    // Everything but windowShouldClose belongs to SwiftUI's delegate.
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let recorder = recorder(), let protection = recorder.protection else {
            return original?.windowShouldClose?(sender) ?? true
        }
        guard !isAsking else { return false }
        isAsking = true
        Task {
            await ask(recorder, protection, in: sender)
            isAsking = false
        }
        return false
    }

    private func ask(_ recorder: Recorder, _ protection: Recorder.Protection, in window: NSWindow) async {
        switch protection {
        case .starting, .finishing:
            _ = await CloseGuardAlert.busy(protection, quitting: false).beginSheetModal(for: window)
        case .recording:
            guard await CloseGuardAlert.keepOrStop(quitting: false).beginSheetModal(for: window) == .alertSecondButtonReturn else { return }
            if await recorder.stopAndSave(handOff: true) == nil {
                _ = await CloseGuardAlert.notSaved(recorder).beginSheetModal(for: window)
            } else {
                window.performClose(nil)
            }
        case .unsaved:
            guard await CloseGuardAlert.unsaved(quitting: false).beginSheetModal(for: window) == .alertFirstButtonReturn else { return }
            recorder.chooseFolderAndSave()
            if recorder.protection == nil { window.performClose(nil) }
        case .failed:
            guard let staging = recorder.failedStaging else { return }
            switch await CloseGuardAlert.failed(staging, quitting: false).beginSheetModal(for: window) {
            case .alertSecondButtonReturn: NSWorkspace.shared.activateFileViewerSelecting([staging])
            case .alertThirdButtonReturn:
                recorder.acknowledgeFailure()
                window.performClose(nil)
            default: break
            }
        }
    }
}

// MARK: quit

@MainActor
final class QuitGuard: NSObject, NSApplicationDelegate {
    // Set by MyApp: the output folder and the recorders of every window.
    static var destination: OutputDestination?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let recorder = Self.destination?.protectedRecorders.first, let protection = recorder.protection else {
            return .terminateNow
        }
        switch protection {
        case .starting, .finishing:
            _ = CloseGuardAlert.busy(protection, quitting: true).runModal()
            return .terminateCancel
        case .recording:
            guard CloseGuardAlert.keepOrStop(quitting: true).runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        case .unsaved:
            guard CloseGuardAlert.unsaved(quitting: true).runModal() == .alertFirstButtonReturn else { return .terminateCancel }
            recorder.chooseFolderAndSave(handOff: false)
        case .failed:
            guard let staging = recorder.failedStaging else { return .terminateCancel }
            switch CloseGuardAlert.failed(staging, quitting: true).runModal() {
            case .alertSecondButtonReturn: NSWorkspace.shared.activateFileViewerSelecting([staging])
            case .alertThirdButtonReturn:
                recorder.acknowledgeFailure()
                // Another window may still hold a recording that needs the same care.
                return applicationShouldTerminate(sender)
            default: break
            }
            return .terminateCancel
        }
        Task { await finish(recorder) }
        return .terminateLater
    }

    // Quits only after the audio is seen in the output folder; any other
    // recording that still needs protection gets the same treatment first.
    private func finish(_ recorder: Recorder) async {
        guard let audio = await recorder.stopAndSave(handOff: false) else {
            _ = CloseGuardAlert.notSaved(recorder).runModal()
            NSApp.reply(toApplicationShouldTerminate: false)
            return
        }
        if CloseGuardAlert.savedOnQuit(audio).runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([audio])
        }
        // Another window may hold a recording too: ask again before quitting.
        NSApp.reply(toApplicationShouldTerminate: Self.destination?.protectedRecorders.isEmpty ?? true)
    }
}
