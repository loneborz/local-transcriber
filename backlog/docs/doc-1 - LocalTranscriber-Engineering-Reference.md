---
id: doc-1
title: LocalTranscriber Engineering Reference
type: guide
created_date: '2026-10-01 00:53'
updated_date: '2026-10-01 00:55'
tags:
  - engineering
  - architecture
---
Durable engineering reference for LocalTranscriber: how the app is built and why. It is not a progress log (see the task records) and not a plan; the v0.2 state and known limitations are recorded at the end. Agent operating rules live in `CLAUDE.md` / `AGENTS.md`; user-facing behavior lives in `README.md`; helper versions, checksums and licences live in `Vendor/YouTubeHelper/README.md`.

## Product boundary

`media or URL -> local transcript package`. Transcription is on-device (Apple SpeechAnalyzer / DictationTranscriber). The network is used only to download a YouTube link's audio and for Apple language assets. See `CLAUDE.md` for what is out of scope.

## Data flow

```text
input: file drop / paste, YouTube link drop / paste / Cmd-V
  -> ContentView.addDroppedFiles        classifies each item into a JobSource
  -> BatchQueue (sequential)            Waiting -> Downloading -> Transcribing -> Complete | Failed
       .file     -> local media URL
       .youtube  -> YouTubeAcquirer.acquire -> temp "<Title> [<ID>].m4a" + SourceMetadata
       .invalid  -> job created already Failed (not retryable)
  -> TranscriptionService.transcribe(url:locale:) -> Transcript
  -> OutputDestination                  flat "<name>.md"  or  source package "<VIDEO_ID>/"
```

`TranscriptionService` only ever sees a local audio/video file URL and a locale. Keep YouTube logic out of it.

## Source files

| File | Responsibility |
| --- | --- |
| `MyApp.swift` | App entry. Sweeps stale acquisition directories at launch, terminates helper children on quit, replaces the Edit menu's Paste/Copy so Cmd-V adds links and files (the window has no text field, so the standard Paste is always disabled). |
| `ContentView.swift` | UI: drop and paste ingestion, link classification, language picker, output-folder and source-package controls, queue list (`JobRow`: Retry, Remove, Save Transcript), queue summary, `MetricsFormat` (shared duration/speed formatting). |
| `BatchQueue.swift` | `TranscriptionJob`, `JobSource`, job states; the sequential runner; `retry`, `remove`, `clear`, `summary`; the save step that chooses flat output or a package. |
| `YouTubeSource.swift` | `YouTubeURL` (host allowlist, canonical watch URL), `SourceMetadata`, `YouTubeAcquirer` (runs the helper, parses its output, names the audio file), `HelperProcess` (child process with timeout, cancellation and a quit-time registry). |
| `TranscriptionService.swift` | The transcription engine, the `Transcript` model and `TranscriptMarkdownRenderer`. `render(_:source:)` takes optional `SourceMetadata` so a package transcript describes the video; the flat output omits it. |
| `OutputDestination.swift` | The output folder (security-scoped bookmark) and the no-overwrite writers `write` and `writePackage`. |
| `SourcePackage.swift` | `SourcePackageManifest`, the schema of `source.json`. |
| `Vendor/YouTubeHelper/` | The vendored YouTube helper (below). Lives outside the synchronized app folder on purpose. |

## Queue semantics

- Jobs run one at a time. The runner rescans `jobs` after each job, so links added mid-run are picked up and removed Waiting jobs never run.
- Each job snapshots its locale when it starts; the language picker is editable only while Waiting. The default language is a persisted preference.
- Only Waiting jobs can be removed. Clear is available only when idle and never cancels an active job.
- Retry returns one Failed file or YouTube job to Waiting and restarts the queue. A rejected link (`.invalid`) is not retryable. Complete jobs are never touched.
- The summary counts Complete and Failed jobs. Total media duration and processing time come from Complete jobs only; downloading is not counted as processing time.
- A failed save never fails a job: it stays Complete, records `saveError`, and offers a manual Save Transcript fallback.

## Output and persistent state

- **Preferences** (`UserDefaults`): `defaultLanguage`, `outputDestinationBookmark`, `sourcePackageMode`. All builds share the bundle id `nl.wavesweb.LocalTranscriber`, so Debug, Release and any other copy share one preferences file, one sandbox container and one output-folder bookmark.
- **Output folder:** chosen with a folder-only open panel and remembered as a security-scoped bookmark. Status is none, ready or unavailable, and it never falls back to another folder. Starting with no folder asks once; cancelling starts nothing. The bookmarks entitlement is not needed: `user-selected.read-write` with an app-scoped bookmark works.
- **Flat output:** `<name>.md`, then `<name> 2.md`, `<name> 3.md`, ... Existing files are never overwritten. Local files use their file name; YouTube links use `<sanitized title> [<video ID>]` (invalid characters removed, title capped).
- **Source package** (optional mode, YouTube only): `<VIDEO_ID>/audio.m4a`, `source.json`, `transcript.md`. A folder that already exists is never reused (`<VIDEO_ID> 2/`). A folder created for a failed write is removed again. `source.json` is an app-owned, versioned schema (`schemaVersion` 1: source type, URL, video ID, title, channel, published date, duration, acquisition time, audio filename, transcription locale). Unknown optional fields are omitted. It is never a copy of yt-dlp's JSON.

## YouTube acquisition

- A link is resolved and downloaded only when its job starts, never when it is added.
- Accepted: `http(s)` links on `youtube.com` (also `www.`, `m.`, `music.`) and `youtu.be`, as watch, shorts, live or embed URLs. The link is rewritten to `https://www.youtube.com/watch?v=<ID>`, which drops playlist parameters. Anything else becomes a Failed job.
- The audio is fetched with `bestaudio[ext=m4a]`, `--no-playlist` and a JSON `--print`. ffmpeg and a JavaScript runtime are not bundled and not needed for this format.
- Working files live in `<sandbox temp>/LocalTranscriber-acquisition/<uuid>/`. They are deleted when the job ends, and the whole directory is swept at launch.
- A download is limited to 30 minutes. The child gets SIGTERM, then SIGKILL; all children are terminated on quit; and the launcher script makes the child exit within about half a second if the app disappears (including SIGKILL of the app).

## YouTube helper: layout, sandbox and signing

```text
LocalTranscriber.app/Contents/
  Helpers/python3.13                 the only Mach-O; signed with app-sandbox + inherit
  Resources/python-home/             Python standard library (data), used as PYTHONHOME
  Resources/yt-dlp                   pinned yt-dlp zipimport file (data)
  Resources/ytdlp_launcher.py        runs yt-dlp; exits if the parent process is gone
```

- The app has `app-sandbox`, `user-selected.read-write` and `network.client`. The helper is a direct child that inherits the app's sandbox and network. Its entitlements are exactly `app-sandbox` + `inherit` (`Vendor/YouTubeHelper/helper-inherit.entitlements`).
- The Xcode run-script phase "Embed YouTube helper" copies the files into the product and signs the helper before Xcode signs the app. `ENABLE_USER_SCRIPT_SANDBOXING` is `NO` for the app target only. The app must pass `codesign --verify --deep --strict`.
- Measured facts behind this design:
  - A helper with `inherit` plus any other sandbox entitlement (for example `network.client`) aborts at launch. A separately sandboxed bare executable also aborts.
  - An `inherit` helper cannot run outside a sandboxed parent (it exits with status 133).
  - The directory `python3.13` inside `Contents/Helpers` breaks codesign, hence the Mach-O in `Helpers` and the data in `Resources`.
  - yt-dlp's PyInstaller onefile build fails in the sandbox (SysV semaphore denied). The onedir build works but is about 124 MB and its licence is GPLv3+. The zipimport build with a standalone Python is about 30 MB and has no GPL component.
  - The sandbox hides `/opt/homebrew`, so a Homebrew-installed yt-dlp can never be used.
- The helper is arm64 only. There is no runtime self-update; yt-dlp is pinned.

## Constraints and fragile conventions

- Never pass both `.withoutOverwriting` and `.atomic` to `Data.write`: Foundation traps instead of throwing.
- Files added under `LocalTranscriber/` are included in the app automatically (synchronized folder group). Vendored helper files are outside it and are installed only by the build phase.
- The build phase entry in `project.pbxproj` was written by hand. Xcode may rewrite its formatting on a build; that is noise, not a change to keep.
- The module default actor isolation is MainActor. Types that must run off the main thread (the acquirer, the process wrapper, `SourceMetadata`) are marked `nonisolated`.
- Do not add entitlements to the helper, put the Mach-O under `Resources`, or move the Python data into `Helpers`.
- Do not run the vendored Python without `PYTHONDONTWRITEBYTECODE=1`; it writes `__pycache__` into `Vendor/`.
- No automated tests exist. Behavior is verified by building and running the real app (see `CLAUDE.md`).

## v0.2 status

v0.2 is implemented. LTR-1 through LTR-6 are Done; their task records hold the plans, evidence and final summaries. The `v0.2` milestone (`m-0`) is intentionally minimal and does not describe this state.

What v0.2 provides: local MP4, MOV, M4A, MP3 and WAV files and YouTube links share one sequential queue with a per-job language, a remembered default language and a remembered output folder. Finished transcripts are saved automatically as timestamped Markdown. YouTube links can instead be saved as source packages. The queue supports removal of waiting jobs, Clear and per-job Retry, and shows a summary (counts, media duration, processing time, realtime speed, output folder).

## Known limitations (not future work)

These are facts about the current build that were observed or left untested, not planned changes:

- The YouTube helper is arm64 only; Intel behavior is untested. Notarization is untested.
- No third-party notice is shown to users. Python's `LICENSE.txt` sits inside the bundled standard library, but no OpenSSL licence text is included (see `Vendor/YouTubeHelper/README.md`).
- yt-dlp is pinned and never updates itself, and no JavaScript runtime is bundled. YouTube changes can break extraction until the pinned version is replaced.
- For a flat (non-package) YouTube transcript, the Markdown `Source` line names the downloaded audio file, not the video URL. Source packages describe the video properly.
- If a package write fails after its folder was created, the folder is removed again; that cleanup path has not been exercised, only failure at folder creation.
- A browser address-bar drag was observed from Safari only. Chrome was not observed.
- A failed job that fails again on Retry (for example a permanently unavailable video) simply fails again; there is no retry limit or backoff.
- There are no automated tests.
