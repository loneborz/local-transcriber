# Local Transcriber

**Media in. Markdown out.**

Local Transcriber is a small native macOS utility for turning local audio and video into timestamped Markdown transcripts with Apple's on-device speech stack.

Drop in a file or a YouTube link, choose the language, and let the app handle the rest.

No accounts. No cloud transcription service. No model picker.

<p align="center">
  <img
    src="docs/screenshots/empty-state.png"
    alt="Local Transcriber empty state"
    width="900"
  >
</p>

## What it does

Drop a local MP4, MOV, M4A, MP3, or WAV file. Audio files are transcribed directly. For video, AVFoundation extracts the audio to a temporary M4A before transcription.

You can also drop or paste (⌘V) a YouTube link. The app downloads that video's audio to a temporary M4A inside its sandbox, transcribes it, and deletes the download. Local files and YouTube links share one queue and run one at a time; a link that cannot be fetched fails only its own row. The saved Markdown is named `<video title> [<video ID>].md`.

## Languages

| Language | Locale |
| --- | --- |
| English | `en-US` |
| Dutch | `nl-NL` |
| German | `de-DE` |
| French | `fr-FR` |
| Russian | `ru-RU` |
| Spanish | `es-ES` |
| Italian | `it-IT` |
| Portuguese | `pt-BR` |
| Turkish | `tr-TR` |
| Swedish | `sv-SE` |

The app checks Apple's native speech modules for an exact locale match and automatically selects a path when one is available. Locale availability depends on macOS support for that language. Apple speech modules are used internally; there is no engine picker. macOS may download and install Apple language assets before transcription when a selected language needs them.

## How it works

```text
Drop media
    ↓
Choose language
    ↓
Normalize video audio if needed
    ↓
Prepare native language assets if needed
    ↓
Transcribe on-device
    ↓
Timestamped Markdown
```

| Choose language | Transcribe | Save Markdown |
| --- | --- | --- |
| <img src="docs/screenshots/language-selection.png" alt="Selected media with the language picker open" width="300"> | <img src="docs/screenshots/transcribing.png" alt="Transcription in progress with selected media and language" width="300"> | <img src="docs/screenshots/completed.png" alt="Completed transcript with metrics, saved Markdown filename, and clickable waveform to start a new transcript" width="300"> |

## Output

Finished transcripts are saved automatically to the output folder you choose once. **Save Transcript…** appears only if an automatic save fails. The document title comes from the source filename, or for a YouTube link the video title and ID. Transcript segments are ordered by audio time, grouped by minute, and headed with the first segment's timestamp in each group.

The saved Markdown includes the source, duration when available, selected locale, and Apple engine metadata:

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

## Performance

After a run, the app reports media duration, processing time, and realtime speed, calculated as media duration divided by processing time. These are per-run measurements. Results vary by hardware, language, source media, and the native transcription path selected for the locale.

## Privacy

The app uses the network for two things only: downloading the audio of a YouTube link you give it, and the Apple-provided language assets that macOS may download when a language needs them. Transcription itself never leaves your Mac: media is processed locally with AVFoundation and Apple's on-device speech stack. There is no media upload, cloud transcription, account, or external model API.

YouTube audio is fetched with a pinned copy of [yt-dlp](https://github.com/yt-dlp/yt-dlp) and a small bundled Python runtime, run as a sandboxed helper inside the app (see `Vendor/YouTubeHelper/README.md`). The helper runs inside the app's sandbox with no entitlements of its own, is stopped when the app quits, and only supports YouTube links. Downloaded audio is temporary and is removed when a job finishes, fails, or at the next launch.

## Non-goals

Downloading from sites other than YouTube, playlists or channels, cloud transcription, accounts, summarization, knowledge base, AI transcript cleanup, user-facing model picker, or transcript editor.

## Status

Requires macOS 26.0 or later. The bundled YouTube helper is Apple silicon only; YouTube links are not supported on Intel Macs.

Early-stage macOS project focused on local transcription and Markdown export.

## License

[MIT License](LICENSE).
