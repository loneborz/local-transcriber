# Local Transcriber

**Media in. Markdown out.**

Local Transcriber is a native macOS app that turns audio, video, YouTube links and your own recordings into timestamped Markdown transcripts. Speech recognition runs on your Mac with Apple's on-device speech stack; there is no cloud transcription service, no account and no model picker.

![Local Transcriber after a run: an action bar with Add Files, an app-audio picker, a Mic checkbox and Record, a summary line with Clear Queue, and three completed jobs (a local audio file, a YouTube link and an app-audio recording) with their saved Markdown files](https://transcribe.wavesweb.nl/assets/queue.png)

*A finished queue: one local file, one YouTube link and one recording, transcribed in sequence and saved to the output folder.*

## What it does

Drop in media files, paste YouTube links or record audio. Everything goes into one queue that runs one job at a time. Each finished transcript is written straight to a folder you chose once.

```text
media file, YouTube link or recording
        │
        ▼
   one queue  ──  per-job language, run sequentially
        │
        ▼
 on-device transcription (Apple speech stack)
        │
        ▼
 timestamped Markdown in your output folder
```

The product boundary is deliberate: `media or URL -> local transcript package`. The transcript is the artifact. The app does not summarize, index, search, rewrite or "clean up" what was said.

## Inputs

![Local Transcriber's empty workspace: a waveform mark and the tagline "Media in. Markdown out." above one surface with two zones: on the left a drop target that also opens the file picker and accepts a pasted YouTube link, on the right "Record audio" with an app-audio picker, a Mic checkbox and a Record button](https://transcribe.wavesweb.nl/assets/empty-state.png)

- **Local files:** MP4, MOV, M4A, MP3 and WAV. Audio files are transcribed directly; for video, AVFoundation first extracts the audio to a temporary M4A.
- **YouTube links:** `youtube.com` (including `www.`, `m.` and `music.`) and `youtu.be` watch, shorts, live and embed links. Playlist parameters are dropped, so a link transcribes one video.
- **Recordings:** **Record** captures the microphone, one running app's audio, or that app plus the microphone. Nothing is captured until you start it. Stop saves one M4A named `Recording <date> <time> (<source>).m4a` to the output folder and adds it to the queue like any dropped file, so its transcript is saved next to it. The recording is kept as source media and never deleted automatically. The microphone permission and, for app audio, Screen & System Audio Recording are requested at the first recording, not at launch. Whole-system audio is not offered, and Local Transcriber does not save or retain video or screen recordings.
- **How to add them:** drag onto anywhere in the window, or copy and press ⌘V. Dropping a link from a browser's address bar works after selecting the URL first (observed in Safari only).

Files with other extensions are ignored. A link that is not a supported YouTube link, or a video that cannot be fetched, fails only its own row and never stops the others.

## The queue

- Jobs run sequentially: `Waiting → Downloading → Transcribing → Complete | Failed`. Downloading applies to YouTube links only.
- **Language** is set per job. **Language** in the **Options** menu sets the default for new jobs, and **Apply Language to All Waiting** changes every job that is still waiting. A job's language is fixed once it starts.
- Waiting jobs can be removed, **Clear Queue** empties an idle queue, and **Retry** puts a failed job back in line. A rejected link cannot be retried, and completed jobs are never touched.
- A summary line shows succeeded and failed counts, total media duration, processing time and realtime speed.
- If an automatic save fails, the job stays complete and offers **Save Transcript…** as a manual fallback.

### Languages

English (`en-US`), Dutch (`nl-NL`), German (`de-DE`), French (`fr-FR`), Russian (`ru-RU`), Spanish (`es-ES`), Italian (`it-IT`), Portuguese (`pt-BR`), Turkish (`tr-TR`) and Swedish (`sv-SE`).

For the chosen language the app looks for an exact match in Apple's speech modules and uses whichever one supports it. Availability depends on what macOS offers for that language, and macOS may download Apple's language assets the first time a language is used.

## Output

The first time you transcribe, the app asks for an output folder and remembers it (as a security-scoped bookmark). Files are never overwritten: a name that exists becomes `name 2.md`, `name 3.md` and so on.

Each transcript is one Markdown file, ordered by audio time and grouped by minute under a timestamp heading:

```markdown
# example

**Source:** `example.m4a`  
**Duration:** 00:05:00  
**Language:** en-US  
**Engine:** Apple SpeechAnalyzer

## Transcript

### 00:00:00

Transcript text...
```

YouTube links are saved as `<video title> [<video ID>].md`. In this flat form the `Source` line names the downloaded audio file rather than the video URL.

### Source packages

Turn on **Save YouTube Links as Source Packages** in the **Options** menu (shown only while the queue contains a YouTube link) and each link is saved as a folder named after its video ID instead of a single file:

```text
<output folder>/
  jNQXAC9IVRw/
    audio.m4a        the downloaded audio
    source.json      where it came from
    transcript.md    the timestamped transcript, with the video's URL, channel and date
```

An existing folder is never reused (a repeat becomes `jNQXAC9IVRw 2/`), and a package that cannot be completed is not left half-written. Local files are always saved as a single `.md`.

`source.json` is a small, versioned schema owned by this app, not a copy of what the downloader reports. Unknown fields are omitted:

```json
{
  "acquiredAt" : "2026-10-01T00:13:47Z",
  "audioFilename" : "audio.m4a",
  "channel" : "jawed",
  "durationSeconds" : 19,
  "publishedDate" : "2005-04-24",
  "schemaVersion" : 1,
  "sourceType" : "youtube",
  "sourceURL" : "https://www.youtube.com/watch?v=jNQXAC9IVRw",
  "title" : "Me at the zoo",
  "transcriptionLocale" : "en-US",
  "videoID" : "jNQXAC9IVRw"
}
```

## Local versus network

| Step | Where it happens |
| --- | --- |
| Transcription (local files and YouTube audio alike) | On your Mac, with Apple's speech stack |
| Audio extraction from video | On your Mac, with AVFoundation |
| Recording (microphone or app audio) | On your Mac, saved to your output folder |
| Reading and writing transcripts | On your Mac |
| Downloading a YouTube link's audio | **Over the network**, from YouTube |
| Apple language assets for a language you have not used yet | **Over the network**, managed by macOS |

Transcription never leaves the machine, but the app is not fully offline when you give it links: a YouTube link cannot be transcribed without downloading its audio first. The download is temporary and is deleted when the job ends, and any leftovers are swept at the next launch.

## YouTube helper

YouTube audio is fetched by a small helper bundled in the app: a pinned [yt-dlp](https://github.com/yt-dlp/yt-dlp) release (a pure-Python zipapp) run by an arm64 build of Python 3.13. The helper runs as a child of the app inside the same App Sandbox, with no entitlements of its own beyond inheriting the app's, and it is stopped when the app quits. There is no runtime self-update, and ffmpeg and a JavaScript runtime are deliberately not bundled, so a change on YouTube's side can break downloads until the pinned yt-dlp is replaced. Versions, checksums and licence notes are in [`Vendor/YouTubeHelper/README.md`](Vendor/YouTubeHelper/README.md).

## Download

[Download Local Transcriber 0.5.0](https://github.com/loneborz/local-transcriber/releases/download/v0.5.0/LocalTranscriber-0.5.0.dmg) (DMG, 15 MB) from the [v0.5.0 release](https://github.com/loneborz/local-transcriber/releases/tag/v0.5.0).

- Requires macOS 26 or later on a Mac with Apple silicon. There is no Intel or universal build.
- The DMG and the app are signed with Developer ID and notarized by Apple.
- Open the DMG, drag Local Transcriber to Applications and open it from there. On first launch macOS asks you to confirm opening an app downloaded from the Internet.
- SHA-256: `98e7d3a24fcc90794c73f0b64bdd8c1338b389e4356e8a380a0e278d2b4ca07e`. Check it with `shasum -a 256 LocalTranscriber-0.5.0.dmg`; the release also has a `.sha256` file.

## Build and run

To build the app from source instead:

Requirements: a Mac running macOS 26 or later (the deployment target) and Xcode. Development and testing so far used Apple silicon with Xcode 27.

```bash
git clone https://github.com/loneborz/local-transcriber.git
cd local-transcriber
scripts/dev.sh        # build only
scripts/dev.sh run    # build, install and launch the development app
```

`scripts/dev.sh` is the development workflow. It builds the Debug configuration, which is a separate app: **Local Transcriber Dev** (bundle id `nl.wavesweb.LocalTranscriberDev`, with a DEV icon), so it never replaces or shares settings and permissions with an installed Local Transcriber. The build goes to a per-checkout DerivedData folder ending in `.noindex` and is removed from Launch Services again, so builds don't pile up as duplicate apps. `run` installs the one development copy at `~/Applications/Local Transcriber Dev.app`, quits a running copy of it first and opens it. A build phase copies the YouTube helper into the app and signs it.

Debug is signed manually with an Apple Development certificate of the project's team (`JZ9667QFWA`). Building it with a different team needs a matching Apple Development certificate and changes to the Debug signing settings (`DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY`). Release builds for distribution use `scripts/release.sh` and Developer ID.

## How it is built

- **SwiftUI** app with an observable, sequential `BatchQueue`; the transcription engine only ever sees a local file and a locale.
- **Apple Speech** (`SpeechAnalyzer`) for transcription, **AVFoundation** for audio extraction and microphone recording, and **ScreenCaptureKit** for app audio.
- **App Sandbox** with user-selected read/write access (the output folder), network client access (YouTube) and audio input (the microphone).
- The YouTube helper is an isolated, sandbox-inheriting child process, kept separate from the transcription code.
- Output folder, default language and the source-package option are remembered in `UserDefaults`.

## Current limitations

- Requires macOS 26 or later.
- The YouTube helper is Apple silicon only. Intel Macs are untested, and YouTube links are not expected to work there.
- Releases are built for Apple silicon only; there is no Intel or universal download.
- YouTube extraction depends on a pinned yt-dlp that never updates itself and can stop working as YouTube changes.
- Only YouTube is supported as a link source: no other sites, playlists or channels. A single download is limited to 30 minutes.
- Retrying a job that fails for a lasting reason (for example an unavailable video) simply fails again; there is no retry limit or backoff.
- A failed write of a source package has been tested only for failure at folder creation, not later in the write.
- Recording uses the system default microphone input. App audio is chosen per running app; recording the whole system is not offered. A recording that has not been saved yet (for example because the output folder was unavailable) is not recovered if the app quits or crashes.
- There are no automated tests; behavior is checked by running the real app.

## Not in scope

Cloud transcription, accounts, summarization, search or retrieval over transcripts, a knowledge-base layer, automatic correction or rewriting of transcript text, a model picker, a transcript editor, and downloads from sites other than YouTube.

## Project philosophy

Local Transcriber is a free, open-source Wavesweb Labs project, independently developed and maintained.

It started with a practical need: turning media into local Markdown transcripts without unnecessary complexity. That remains its purpose.

Development follows practical needs and available time, rather than a fixed roadmap or release schedule. The project deliberately stays focused on what it does well.

## Feedback and feature requests

Bug reports, ideas, and feature requests are always welcome. I do my best to review them as time allows, but I can't guarantee response times or that every request will be implemented.

New features are considered only when they add meaningful value and fit the project's existing scope. For the project's current boundaries, see [Not in scope](#not-in-scope).

Local Transcriber is provided under the MIT License, without guaranteed support or service-level commitments.

## Status

An early, working macOS project. The queue, language handling, automatic output, source packages, retry, recording and the current interface are implemented and were verified by running the app. Version 0.5.0 is the current release, distributed as a notarized DMG. It gives the app its own visual identity and changes nothing about what it does; 0.4.0 added recording and 0.3.0 was the first public release.

## Third-party components

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) (Unlicense; the zipapp also contains ISC- and MIT-licensed code).
- [CPython](https://www.python.org/) 3.13 from [python-build-standalone](https://github.com/astral-sh/python-build-standalone) (Python Software Foundation licence), which statically links OpenSSL.

The exact versions and checksums are listed in [`Vendor/YouTubeHelper/README.md`](Vendor/YouTubeHelper/README.md). Their licence texts, including OpenSSL's, ship inside the app and appear in its About panel.

## License

[MIT License](LICENSE). Bundled third-party components keep their own licences, as noted above.
