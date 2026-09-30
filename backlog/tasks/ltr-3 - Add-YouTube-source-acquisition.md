---
id: LTR-3
title: Add YouTube source acquisition
status: Done
assignee:
  - '@claude'
created_date: '2026-09-30 20:03'
updated_date: '2026-09-30 23:57'
labels: []
milestone: m-0
dependencies: []
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Allow a YouTube URL to become local audio plus source metadata and then enter the existing transcription pipeline.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 URL can enter the same queue as local media
- [x] #2 Queue exposes Downloading state
- [x] #3 yt-dlp integration is isolated from the transcription engine
- [x] #4 Source metadata is captured
- [x] #5 Resulting local audio enters the existing transcription service
- [x] #6 Acquisition failure affects only that job
- [x] #7 Remaining jobs continue
- [x] #8 Determine the smallest robust yt-dlp/ffmpeg runtime strategy before implementation
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Vendor the accepted Option C helper outside the synchronized source group: Vendor/ with arm64 python3.13 (Mach-O), stdlib data, pinned yt-dlp zipimport, and a small launcher that exits when the parent dies; Vendor/README documents versions, sources, checksums, licences.
2. Xcode: network.client via ENABLE_OUTGOING_NETWORK_CONNECTIONS; target-level script sandboxing off; a Run Script phase copies the Mach-O to Contents/Helpers, data to Resources, and signs the helper with app-sandbox+inherit only (helper-inherit.entitlements).
3. YouTubeSource.swift (new, isolated from TranscriptionService): URL canonicalisation/rejection, SourceMetadata, sanitised Title [ID] naming, Process wrapper with timeout/termination/registry, per-job temp dir under the sandbox temp directory, launch-time sweep.
4. BatchQueue: JobSource (file | youtube | invalid), new Downloading state, acquire at job start then feed the local M4A (renamed to the sanitised name so no temp name leaks) to the unchanged TranscriptionService; failure only fails that job; temp dir always removed.
5. ContentView: accept http(s) URLs in existing drop destinations and Cmd-V paste; invalid/non-YouTube become Failed jobs; Downloading row state; hint text.
6. README privacy/non-goals rewritten to match real behaviour.
7. Verify: xcodebuild, codesign structure/entitlements, real-app human runtime checks (15-point list), then finalize only after user acceptance.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented per accepted spike (Option C, direct inherit child, pinned yt-dlp 2026.08.19, arm64 Python 3.13.15, no ffmpeg/deno, no self-update). Changed locally, NOT committed. Verified locally by me in the real app (Debug + Release, UI via macos-use + clipboard paste): Cmd-V adds YouTube/non-YouTube links and file URLs; playlist param stripped to canonical URL; non-YouTube -> Failed row; bad video ID -> Failed, queue continues; mixed file+YouTube batch ran sequentially (YouTube -> failed -> failed -> local alpha.m4a -> duplicate YouTube) ; Downloading state shown; Markdown auto-saved as 'Me at the zoo [jNQXAC9IVRw].md' then '... 2.md' then '... 3.md' (collision handling intact); Waiting YouTube row removed; Clear works; acquisition temp dir empty after success/failure; quit mid-download (12h video) terminated the helper and left .part, swept on next launch; SIGKILL of the app mid-download made the helper exit in ~500ms (launcher parent watchdog). codesign --verify --deep --strict passes (Debug and Release); parent: app-sandbox, user-selected.read-write, network.client (+get-task-allow from local signing); helper: app-sandbox + inherit only. Not yet done: human-run acceptance. Known gaps: Intel/x86_64 and notarization untested; helper is arm64-only; Markdown 'Source' line names the local m4a, not the URL (source packages are LTR-4); ⌘V required replacing the Edit-menu Paste/Copy group (onPasteCommand did not fire without a focused responder).

Browser drag investigation (scratch probe + real app, no product code change needed): a real Safari address-bar drag carries public.url, public.utf8-plain-text, NSStringPboardType, CorePasteboardFlavorType 0x75726C20, Apple URL pasteboard type, com.apple.linkpresentation.metadata; readObjects(NSURL) resolves it. Dropping it on the running app via the existing dropDestination(for: URL.self) created the YouTube job (canonical path via linkSource/YouTubeURL.parse). Local-file drag from Finder onto the app also still works (gamma.m4a queued with media info). NOT observed: Chrome drag (AppleScript automation prompt and extra windows; stopped under bounded-retry rule) and a non-YouTube URL drag from a browser (two attempts missed; the non-YouTube path was verified earlier via Cmd-V through the same addDroppedFiles/linkSource code). Plain-text fallback not added: not shown necessary.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
YouTube links now enter the same queue as local media (drop, browser address-bar drag, or Cmd-V), are canonicalised (playlist params dropped, non-YouTube rejected as a Failed row), and are resolved and downloaded only when their job starts, with a new Downloading state, then the resulting M4A goes to the unchanged TranscriptionService and LTR-2 auto-save. Acquisition lives in YouTubeSource.swift (SourceMetadata: type, URL, video ID, title, channel, upload date, duration, acquisition time, audio filename); the engine file is untouched. Runtime strategy (AC8) was settled by a measured spike: a bundled arm64 Python 3.13.15 + pinned yt-dlp 2026.08.19 zipimport file run as a direct sandbox-inheriting child (parent: network.client; helper: app-sandbox + inherit only); no ffmpeg/deno; no self-update; official PyInstaller builds rejected (onefile fails in the sandbox on a SysV semaphore; onedir is 124 MB and GPLv3+). Verified locally in the real app (Debug and Release, macos-use + clipboard/drag): link paste and Safari address-bar drag create YouTube jobs; Downloading -> Transcribing -> Complete; 'Me at the zoo [jNQXAC9IVRw].md' auto-saved with correct title/channel/duration and transcript; non-YouTube link and bad video ID become Failed rows and later jobs still run; mixed file + YouTube batch ran sequentially; duplicate saved as '... 2.md' and '... 3.md'; Waiting row removal and Clear work; Finder file drag still works; temp dir empty after success/failure; graceful quit mid-download terminated the helper; SIGKILL of the app ended the helper in ~500ms; stale partial download swept at next launch; 16 URL-parsing cases and filename sanitising/capping checked via a scratch harness; xcodebuild Debug and Release succeed; codesign --verify --deep --strict passes for both, helper entitlements are app-sandbox + inherit only. Acceptance: user instructed finalization on this evidence. Not verified: Chrome drag, a non-YouTube URL dragged from a browser (only via Cmd-V), upload-date/acquisition-timestamp values at runtime (fields are populated but only title/channel/duration were observed), Intel/x86_64 (helper is arm64-only), notarization, and shipping Python/OpenSSL licence texts.
<!-- SECTION:FINAL_SUMMARY:END -->
