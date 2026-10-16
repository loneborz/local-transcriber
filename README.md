# Local Transcriber

**Media in. Markdown out.**

Local Transcriber is a native macOS app that turns audio, video, YouTube links and your own recordings into timestamped Markdown transcripts. I built it because the media was already on my Mac and I didn't want to send it somewhere else to get text back. Speech recognition runs on your Mac with Apple's on-device speech stack. There is no cloud service, no account and no model picker.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://transcribe.wavesweb.nl/assets/queue-dark.webp">
  <img src="https://transcribe.wavesweb.nl/assets/queue-light.webp" alt="Local Transcriber showing a saved transcript while audio plays, with the current line highlighted.">
</picture>

*Reviewing a transcript: the sidebar lists what is in the output folder, and the line being played is highlighted.*

## Download

[Local Transcriber 0.6.1](https://github.com/loneborz/local-transcriber/releases/download/v0.6.1/LocalTranscriber-0.6.1.dmg) (DMG, 15.7 MB), from the [v0.6.1 release](https://github.com/loneborz/local-transcriber/releases/tag/v0.6.1).

It needs macOS 26 or later on a Mac with Apple silicon. There is no Intel or universal build. The DMG and the app are signed with Developer ID and notarized by Apple. Open the DMG, drag Local Transcriber to Applications and open it from there. The first time, macOS asks you to confirm opening an app downloaded from the Internet.

SHA-256: `dc2f6189533f3e8483354068cb43d489a2383e7b4e8c7cce5a6b24b82f60359a`. Check it with `shasum -a 256 LocalTranscriber-0.6.1.dmg`; the release also has a `.sha256` file.

## What it does

Drag media onto the window, paste a YouTube link with ⌘V, or press Record. Everything goes into one queue shared by all windows that runs one job at a time, listed in the sidebar's Processing section (start it with Start, keep working in the Library while it runs, and watch the recognized audio position), and each finished transcript is saved to the output folder you chose the first time. Dropping a link from a browser's address bar works after you select the URL first (I have only seen that in Safari).

- Local files: MP4, MOV, M4A, MP3 and WAV. For video, AVFoundation first extracts the audio to a temporary M4A.
- YouTube links: `youtube.com` (including `www.`, `m.` and `music.`) and `youtu.be` watch, shorts, live and embed links. A link transcribes one video, so playlist parameters are dropped.
- Recordings: the microphone, one running app's audio, or both. Nothing is captured until you press Record, and macOS asks for the microphone and Screen & System Audio Recording permissions the first time you need them, not at launch. Stop saves the M4A in its own folder, `Recording <date> <time> (<source>)/`, in the output folder and queues it like any dropped file; the transcript is written into the same folder. The recording stays there, and the app never deletes it by itself (Move to Trash in the sidebar moves the whole folder to the Trash, after asking). Whole-system audio is not offered, and the app keeps no video or screen recordings.

Each job has its own language: English (`en-US`), Dutch (`nl-NL`), German (`de-DE`), French (`fr-FR`), Russian (`ru-RU`), Spanish (`es-ES`), Italian (`it-IT`), Portuguese (`pt-BR`), Turkish (`tr-TR`) or Swedish (`sv-SE`). The language menu in the window's footer sets the default for new jobs, and Apply Language to All Waiting, above the queue, changes the jobs that haven't started. For the language you pick, the app uses whichever Apple speech module supports it, and macOS may download Apple's language assets the first time you use one.

A failed job never stops the others, and Retry puts it back in line (a rejected link can't be retried). If an automatic save fails, the job stays complete and offers Save Transcript… as a fallback.

## Output

The first time you transcribe, the app asks for an output folder and remembers it. It never overwrites anything: each transcript gets its own folder named after the media (`Weekly Meeting/`), and a name that already exists becomes `Weekly Meeting 2/`, `Weekly Meeting 3/` and so on.

Each transcript is one Markdown file, ordered by audio time and grouped by minute:

```markdown
# example

**Source:** `example.m4a`  
**Duration:** 00:05:00  
**Language:** en-US  
**Engine:** Apple SpeechAnalyzer  
**Transcriber:** SpeechTranscriber

## Transcript

### 00:00:00

Transcript text...
```

Every new transcript is a folder with the same name inside:

```text
<output folder>/
  Meetings/                      a folder you made in the app (a real folder, also in Finder)
    Weekly Meeting/
      Weekly Meeting.md          the timestamped transcript
      Weekly Meeting.timing.json timing data for playback
      entry.json                 when it was created, pinned, archived
```

A YouTube link is saved the same way, named after the video's title. In that form the `Source` line names the downloaded audio file, not the video URL, and the audio is not kept.

For research or archiving, turn on Save YouTube Links as Source Packages in Settings › General. The folder then also holds the audio and where it came from:

```text
<output folder>/
  Me at the zoo/
    Me at the zoo.md   the timestamped transcript, with the video's URL, channel and date
    audio.m4a          the downloaded audio
    source.json        where it came from
    entry.json
```

`source.json` is a small versioned file that the app defines itself (schema version 1). It holds the video's URL, ID, title, channel, publication date and duration, when it was fetched, the audio file name and the transcription language. `entry.json` (schema version 1) holds `createdAt` (the start of a recording, the moment a file was added, or the moment a link was fetched), and `pinned` and `archived` when set. An existing folder is never reused, and a folder that can't be completed isn't left half-written. Transcripts saved by v0.6 and earlier (a loose `.md`, or a source package with `transcript.md`) stay listed and readable and are never changed or moved; they can only be managed in Finder.

## Library and review

The sidebar lists what is in your output folder: Pinned, Folders (real folders you create with the folder button or ⇧⌘N), Recent (transcripts in no folder) and Archive, with the one in progress above them. Right-click a transcript (or use the Transcript menu) to rename it, pin it, archive it, move it to a folder, or move it to the Trash. Rename changes the folder and file name only; archive changes nothing on disk except `entry.json`; Move to Trash asks first and never deletes permanently. The app scans the output folder and the folders directly inside it, nothing deeper. Nothing is imported and no database or index is created, so changes made in Finder show up after a refresh (⌘R). Select a transcript to read it in the window. The Markdown file stays the source of truth, and Copy puts all of it on the clipboard.

Each new transcript also gets a `Name.timing.json` next to its Markdown (`transcript.timing.json` inside a source package) with the recognizer's timing. The Markdown itself doesn't change. The timing is used only when it belongs to that Markdown, by its checksum and the text of its lines. Otherwise the transcript opens as plain Markdown with a short note, which is also how transcripts made before 0.6 open.

When the recording sits next to its transcript, a player appears. Click a timestamp or any timed line to jump there and play. The current line is highlighted, the view follows it, and Jump to Playing takes you back if you scroll away. The audio is the file named by the transcript's `Source` line in the same folder (or `audio.m4a` in a source package folder), and its duration has to match the transcript's to within a second. Audio imported from somewhere else, and YouTube transcripts saved without their audio, open for reading without a player. Jump positions are only as exact as the recognizer's timing.

## Privacy

Transcription never leaves your Mac. So do extraction, recording, and reading and writing transcripts. The app uses the network in two places: to download a YouTube link's audio, and for Apple's language assets, which macOS manages. A YouTube download is temporary and is deleted when the job ends, and any leftovers are swept at the next launch. The exception is a source package: the audio is copied into the package folder first, and that `audio.m4a` stays next to the transcript on purpose.

YouTube audio is fetched by a small helper bundled in the app: a pinned [yt-dlp](https://github.com/yt-dlp/yt-dlp) release run by an arm64 build of Python 3.13. It runs as a child of the app inside the same App Sandbox with no entitlements of its own beyond inheriting the app's. It never updates itself, and ffmpeg and a JavaScript runtime are not bundled, so a change on YouTube's side can break downloads until the pinned yt-dlp is replaced. Versions, checksums and licence notes are in [`Vendor/YouTubeHelper/README.md`](Vendor/YouTubeHelper/README.md).

## Limitations

- Apple silicon only. The YouTube helper is arm64 and Intel Macs are untested.
- Recognition quality is Apple's. Dutch Dictation output can be sparse, and I haven't fixed that.
- YouTube is the only link source (no other sites, playlists or channels), and a single download is limited to 30 minutes.
- Retrying a job that fails for a lasting reason, such as an unavailable video, simply fails again. There is no retry limit or backoff.
- The microphone is the system default input. A recording that hasn't been saved yet, for example because the output folder was unavailable, is not recovered if the app quits or crashes.
- A failed write of a source package has been tested only for failure at folder creation, not later in the write.

The app does not summarize, search, edit or correct transcripts, and it has no cloud transcription, accounts or model picker.

## Build and run

You need a Mac running macOS 26 or later and Xcode. I have only used Apple silicon with Xcode 27.

```bash
git clone https://github.com/loneborz/local-transcriber.git
cd local-transcriber
scripts/dev.sh        # build only
scripts/dev.sh run    # build, install and launch the development app
```

`scripts/dev.sh` builds the Debug configuration, which is a separate app, Local Transcriber Dev (bundle id `nl.wavesweb.LocalTranscriberDev`, with a DEV icon). It never replaces or shares settings and permissions with an installed Local Transcriber. `run` installs the one development copy at `~/Applications/Local Transcriber Dev.app`, quits a running copy first and opens it. A build phase copies the YouTube helper into the app and signs it.

Debug is signed manually with an Apple Development certificate of the project's team (`JZ9667QFWA`). To build with a different team you need a matching Apple Development certificate and changes to the Debug signing settings (`DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY`). Distribution builds use `scripts/release.sh` and Developer ID. `swift test` at the repository root runs the automated tests for the transcript, timing, sidecar, library and review logic without building the app; the app itself, including the views and audio playback, is checked by running it.

The app is SwiftUI. It uses Apple's `SpeechAnalyzer` for recognition, AVFoundation for extraction and microphone recording, and ScreenCaptureKit for app audio. It runs in the App Sandbox with user-selected read/write access (the output folder), network client access (YouTube) and audio input.

## About the project

Local Transcriber is a free, open-source [Wavesweb](https://wavesweb.nl/) Labs project that I develop and maintain independently. It started with a practical need, turning media into local Markdown transcripts without unnecessary complexity, and that is still the point. It is an early, working project, and I work on it when I have time rather than to a roadmap or release schedule. The [Journal](https://transcribe.wavesweb.nl/journal/) tells how each release came about, and the [website](https://transcribe.wavesweb.nl/) has the screenshots.

Bug reports, ideas and feature requests are welcome, by email at [info@wavesweb.nl](mailto:info@wavesweb.nl) or as a [GitHub issue](https://github.com/loneborz/local-transcriber/issues). I read them as time allows, but I can't promise a reply or that a request will be built. New features are considered when they add real value and stay within what the app does: turn media or a link into a local transcript.

Local Transcriber is released under the [MIT License](LICENSE), without guaranteed support or service-level commitments. Bundled third-party components keep their own licences:

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) (Unlicense; the zipapp also contains ISC- and MIT-licensed code).
- [CPython](https://www.python.org/) 3.13 from [python-build-standalone](https://github.com/astral-sh/python-build-standalone) (Python Software Foundation licence), which statically links OpenSSL.

The exact versions and checksums are in [`Vendor/YouTubeHelper/README.md`](Vendor/YouTubeHelper/README.md). Their licence texts, including OpenSSL's, ship inside the app and appear in its About panel.
