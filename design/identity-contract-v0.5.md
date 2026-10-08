# Local Transcriber v0.5 Identity Contract

> Tracked copy of the approved contract. The authority remains Backlog document doc-2 ("Local Transcriber v0.5 Identity Contract"); update doc-2 first and refresh this copy from it. The four design references in this folder are the sources cited in section 1.

Design authority for LTR-28 (milestone m-3, "Wavesweb DNA, native Mac grammar"). Approved by the human on 2026-10-08 (visual direction: iteration-2 prototype; contract: draft 3 plus the final verification corrections). Engineering facts stay in doc-1; this document only defines how the app looks, reads and behaves at the surface.

## 1. Sources

| Tag | Source | Authority |
| --- | --- | --- |
| [W] | `design/design.md` (Wavesweb homepage design system) | Brand: palette roles, serif accent, matte surfaces, rules, plain links, voice |
| [L] | `design/design-ltr.md` (transcribe.wavesweb.nl design system) | Product: paper/card/rule tokens, wine CTA, mono for filenames, 7-bar mark |
| [N] | macOS / SwiftUI conventions | Controls, interaction, accessibility, window behavior |
| [P] | LTR-27 prototypes (scratch SwiftUI builds, measured) | Measurements and verified behavior |

`design/design-preview*.html` are visual previews of the same content. `docs/design-references/stele-ai.dev-DESIGN.md` is external inspiration only.

## 2. Change classes

- **Presentation (allowed):** dual-zone empty surface, recessed/raised zones, queue action bar, Transcribe N beside Record (same condition: idle with waiting jobs), Clear Queue shown disabled while running (previously hidden; same action and condition), recording status in place, language as text for non-waiting jobs, colors, type, radii, copy.
- **Approved interaction changes:** the Record popover is removed; recording is configured inline with an app-audio picker ("No app audio" or a running app) and a Mic checkbox bound directly to `Recorder.selectedAppID` and `Recorder.includesMicrophone`; Record starts from the visible selection; no Return/Esc shortcut acts on recording. Capabilities are unchanged: microphone only, app only, app + microphone.
- **Unchanged behavior (needs separate authorization to change):** inputs (Add Files, import zone) disabled while recording (window drops still accepted, as before); Transcribe N not offered while recording; Stop saves, enqueues and starts the queue; Clear Queue removes all jobs, only when idle, without confirmation, touching no files; permissions requested only by Record; the transcript output.

## 3. Color

Light/dark follow the system; no in-app theme control. Tokens live in the asset catalog (or one Swift color table) with light, dark and Increase Contrast variants. No other colors are introduced.

| Token | Light | Dark | Source | Use |
| --- | --- | --- | --- | --- |
| Paper | `#F3F0EA` | `#171214` | [L] | Window ground, continued under the title bar |
| Recessed | `#E8E2D9` | `#171214` | [L] | Import zone (empty surface and action bar) |
| Raised | `#FAF8F4` | `#251E20` | [L] / [W] resting card | Record zone, action-bar record segment, queue list |
| Rule | `#D4C9BD` (IC `#A89D96`) | `#3A3133` (IC `#605855`) | [L] / [W] | 1 px surface borders, zone and row dividers |
| Emphasis | `#762F3D` | `#D7A3AD` | [L] | The one italic brand word; underline of output links |
| WineFill | `#762F3D` | `#8F3D4E` | [L] / [W] CTA | Fill of the prominent button and checkboxes only |

- Text uses system `.primary/.secondary/.tertiary`. Status uses system green/red/orange; recording uses system red. Wine is never a status color.
- Accent (D1): the `AccentColor` asset stays empty. Wine is applied only with `.tint(WineFill)` on the prominent button and on checkboxes; focus rings and all other controls follow the user's system accent. Never apply `.tint` to a container: it tints ordinary button, picker and menu labels, and berry text on dark fails contrast (computed 1.7:1).
- Computed contrast: white on wine ≥ 8:1, white on berry 10.2:1, rose text on dark 8.3:1, secondary text on Raised about 6:1.

## 4. Typography

| Role | Style |
| --- | --- |
| Brand line | "Media in. *Markdown* out." `.title3` bold, tracking −0.3; "Markdown" Georgia Italic 18 pt in Emphasis |
| Zone heading | "Record audio" `.headline`, centered, accessibility header trait |
| Import zone | "Drop media" `.headline`; "or click to choose files", "⌘V pastes a YouTube link" `.caption` secondary |
| Job name | `.callout` medium, `.primary`, not underlined |
| Metadata | `.caption.monospacedDigit()` secondary (format · duration · size; YouTube · channel · duration) |
| Output file name | `.caption.monospaced()`, underlined in Emphasis at 55 % |
| Status, errors, summary | `.caption` |
| Footer | `.subheadline` secondary, plain text |
| Timer | `.monospacedDigit()`: `.title3` in the bar, `.title2` in the empty surface |

No uppercase tracked labels.

## 5. Spacing, surfaces, radii

- Rhythm 4 / 8 / 12 / 16 / 24 / 40. Window inset 16; empty-state inset 40; 8 between bar, header and list.
- Surfaces: radius 16, 1 px Rule border, clipped. Zones separated by 1 px Rule dividers. No shadows inside the window, no hover effects on surfaces.
- Measured at 640 × 420 [P]: footer 640 × 36; empty surface 560 × 148 (import about 299, record 260); action bar 608 × 44 (two-row 608 × 89); queue header fixed minimum 24; queue list 288 (one-row bar), 243 (two-row), 267 (recording with a warning line); rows 61 (complete) / 46 (waiting).

## 6. Layouts

### Empty workspace
- Mark (66 × 52) and brand line above one surface: recessed import zone (one Button: file picker; drop target; label "Choose files", hint "Or drop media, or press Command V to paste a YouTube link") | divider | raised Record zone (260 wide).
- Record zone, one centered group: "Record audio" (header), app picker (max 200), Mic checkbox, Record (large).
- Errors and notices full width below the surface.

### Queue action bar
- One row: `[Add Files]` on Recessed | divider | on Raised: app picker (max 150, middle-truncating, full name in tooltip and menu), Mic, Record, Transcribe N (prominent, WineFill, only when idle with waiting jobs).
- No waveform in the bar.
- Fit [P]: ideal one-row width 539 of 608 pt with long app names and Transcribe 12.
- Two-row fallback via `ViewThatFits(in: .horizontal)`: row 1 Add Files and "⌘V pastes a YouTube link" (Recessed); row 2 picker (max 260), Mic, Record, Transcribe N (Raised).

### Queue header
- Summary (tail-truncating) left; **Clear Queue** right, `.bordered`, `.small`; disabled while a job runs; tooltip "Remove all items from the queue. Saved transcripts and media stay in place." Fixed height 24.

### Recording
- Bar: the record segment becomes `● Recording · <source>`, timer, **Stop Recording**, on Raised with a 7 % system-red overlay; Add Files disabled; height unchanged.
- Empty surface: the Record zone shows `● Recording`, the source, the `.title2` timer and Stop Recording.
- Starting: spinner and "Starting…". Finishing: spinner and "Saving recording…". Silence (orange) and errors (red) below the bar or surface.

## 7. Waveform, icons, app icon

- Mark: website geometry, 7 symmetric bars (14, 26, 38, 52, 38, 26, 14), width 6, gap 4, `.primary`, static, hidden from accessibility. Used in the empty state and the About credits only. It never animates during recording and never imitates a level meter.
- SF Symbols only, the existing set. Status icons are hidden from accessibility (the status text carries the state).
- App icon unchanged in v0.5.

## 8. Queue rows and progress

- Row: status icon · name (plain) · metadata · status line · "Saved · `file.md`" (the only underline; reveals in Finder) or red "Not saved: …" · trailing controls (language picker and Remove when Waiting; language as caption text otherwise; Retry when retryable, never for an invalid link; Save Transcript… after a failed save).
- Names keep their actions (reveal file, open YouTube) with `.help` and a pointing-hand cursor.
- Truthful progress: Waiting / Downloading… / Preparing video… / Preparing language… / Transcribing… / Complete · metrics / Failed · reason. Indeterminate spinners only. All failure and save reasons stay complete and selectable.

## 9. Window and title bar

- `.containerBackground(Paper, for: .window)` continues the paper under the title bar in light and dark (verified [P] in a bundled WindowGroup). No AppKit title-bar workarounds.
- Window stays resizable with the 640 × 420 minimum.

## 10. About

Standard About panel. Credits start with "Media in. *Markdown* out." and "A Wavesweb Labs project · transcribe.wavesweb.nl", followed by the existing third-party notices. No new copyright declaration (D3).

## 11. Microcopy

Rules: say what happened, then what to do; keep every fact (queued or not, kept or not, the system's reason); keep distinct causes distinct; no "please", no hedging; ellipses only on controls that open a panel; technical terms only when they help act.

| Where | Text |
| --- | --- |
| Import zone | "Drop media" / "or click to choose files" / "⌘V pastes a YouTube link" |
| Record zone | "Record audio" / "No app audio" / "Mic" (accessibility label "Include microphone") / "Record" / "Stop Recording" / "Recording · <source>" |
| Queue | "Transcribe N" / "Clear Queue" |
| Microphone denied | "Local Transcriber isn’t allowed to use the microphone. Turn it on in System Settings › Privacy & Security › Microphone." |
| App audio denied | "Local Transcriber isn’t allowed to record app audio. Turn it on in System Settings › Privacy & Security › Screen & System Audio Recording." |
| App not capturable | "<App> can’t be recorded right now. Make sure it is running and has a window open." (kept) |
| Silence | "No sound from <source> for N seconds. Recording continues; check that <source> is playing sound." |
| Recording failed | "Recording failed and wasn’t queued: <reason>" |
| Folder unavailable at Stop | "The output folder is unavailable. The recording wasn’t saved or queued; it is kept until you quit." + "Choose Folder and Save Recording…" |
| Save failed at Stop | "The recording couldn’t be saved to the output folder (<reason>). It wasn’t queued; it is kept until you quit." + same button |
| Unwritable folder at Record | "The output folder can’t be written to (<reason>). Choose another folder." (kept) |
| Unsupported drop | "Not supported. Drop an MP4, MOV, M4A, MP3 or WAV file, or a YouTube link." |
| Video audio errors | Three distinct messages, "AVFoundation" removed from the wording, reasons kept |
| Kept | Paste notice, "Output folder is unavailable. Choose it again.", "Choose where transcripts are saved." |

Before → after examples: "Drop media here / or choose files… · ⌘V to paste a YouTube link" → "Drop media / or click to choose files / ⌘V pastes a YouTube link"; "Local Transcriber may not use the microphone. Allow it in …" → "Local Transcriber isn’t allowed to use the microphone. Turn it on in …"; "No sound has been received for 10 seconds. Recording continues; check that Safari is producing sound." → "No sound from Safari for 10 seconds. Recording continues; check that Safari is playing sound."; "The recording failed and was not added to the queue: X" → "Recording failed and wasn’t queued: X"; "Clear" → "Clear Queue"; "Start Recording" (popover) → "Record".

## 12. Native and accessibility (protected)

- Native controls throughout; drag and drop, ⌘V, Finder reveal, Options menu, panels, window chrome unchanged.
- Full Keyboard Access order [P]: Add Files → App audio → Mic → Record → Transcribe N → Clear Queue → rows → footer; native focus rings (system accent).
- VoiceOver: groups "Record audio" and "Recording"; picker exposed by its own title "App audio" (no duplicate label); Mic "Include microphone"; import zone "Choose files" with hint; status icons, mark, dot and dividers hidden; no `.help` that only repeats a label.
- Increase Contrast uses the IC Rule variants; Reduce Motion: no custom motion exists.

## 13. Anti-patterns

Card soup; boxes that all look like drop targets; container-wide `.tint`; wine as status; berry text on dark; underlining every name; mono for general metadata; uppercase eyebrows; web hover lifts; shadows inside the window; theme toggle or accent picker; morphing hero wave; animated waveform during recording; fake progress; Return/Esc acting on recording; feature changes or new recording modes.

## 14. Verification record (LTR-27)

Verified in prototypes [P]: title bar via `.containerBackground`, light/dark, scoped accent (Multicolor system accent), 640 × 420 layout and bar fit, Increase Contrast rendering, Reduce Motion environment, Full Keyboard Access order and focus rings, accessibility tree labels and grouping.

Not verified: VoiceOver speech and rotor (accessibility tree only); focus ring shape of the import zone; non-Multicolor user accents; on-screen contrast measurement under Increase Contrast; live v0.4 inspection of the recording popover, active recording, Options menu, an error state and About (human accepted the existing evidence as sufficient on 2026-10-08).

## 15. Implementation notes (LTR-28)

Recorded during implementation; the human reviews them with the LTR-28 result.

- The app picker is a native menu `Picker` (NSPopUpButton), which truncates long names at the end, not in the middle (section 6). The full name is in the tooltip and the menu.
- The About attribution is two lines ("A Wavesweb Labs project" / "transcribe.wavesweb.nl"): the credits column is too narrow for one line.
- The import zone draws its keyboard focus ring itself, in the system keyboard-focus color, on its own rounded shape: the default ring is drawn on the button's rectangle and sticks out past the surface's corners. All other controls use the native ring.
- The empty-surface record zone has a minimum height of 148 pt so the surface keeps its size while starting, recording and saving.
- Clear Queue keeps one tooltip (section 6 text) in both enabled and disabled states.
