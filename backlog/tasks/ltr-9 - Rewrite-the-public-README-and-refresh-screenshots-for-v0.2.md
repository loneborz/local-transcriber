---
id: LTR-9
title: Rewrite the public README and refresh screenshots for v0.2
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-01 16:58'
updated_date: '2026-10-01 17:11'
labels: []
dependencies:
  - LTR-8
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The public README still describes the v0.1 single-file app: its screenshots show the removed plus badge, the old empty-state copy and the single-job completion screen, and it says nothing about the batch queue, queue-level language, Retry or the current empty state. A first-time visitor cannot tell what the app does today. This is a documentation and repository-presentation pass only: no product code, behaviour or project settings change, and no GitHub repository settings are changed without separate approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 README.md opens with the title, one-sentence product statement (media or URL -> local transcript package) and a current screenshot of the running app
- [ ] #2 README answers what it is, the workflow, supported inputs, what it produces, what is local versus network-dependent, how to build and run, key technical decisions and current limitations
- [ ] #3 The YouTube path is described accurately: transcription is local; the media is downloaded over the network; the helper is arm64 Python 3.13 plus pinned yt-dlp with no runtime self-update; Intel support, notarization and a public release artifact are not claimed
- [ ] #4 The README does not claim summarization, RAG, knowledge management, cloud transcription or silent transcript rewriting, and does not claim the whole app works offline when URLs are used
- [ ] #5 Sample Markdown and source.json in the README match what the current build actually writes
- [ ] #6 Screenshots in docs/screenshots are captured from the real current build (refined empty state and a representative queue state), contain no personal data, and replace the outdated v0.1 images; no UI is altered for the screenshots
- [ ] #7 Backlog mechanics and agent operating rules are not part of the main product story; any development notes are short and link to existing docs instead of duplicating them
- [ ] #8 GitHub About metadata (description, topics, homepage) is reviewed and recommendations are reported but not applied
- [ ] #9 Only documentation and screenshot assets (and this task file) change; no file under LocalTranscriber/, Vendor/ or LocalTranscriber.xcodeproj changes
- [ ] #10 All README links and relative image paths resolve, and the screenshots render at the README size
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Audit: old README, helper README, doc-1, gh metadata (description present, no topics, no homepage, no release/tags). Diagnosis: README is v0.1-era and stale.
2. Capture real screenshots from the current Debug build with screencapture -l on the app window: empty state, and a queue state (Complete jobs plus summary using the 2-second test audio). Remove old v0.1 screenshots. Restore prefs/window frame and delete test output afterwards.
3. Rewrite README.md: product statement, screenshots, what it does, workflow, inputs, output (verified against TranscriptMarkdownRenderer and SourcePackageManifest), local vs network, languages, build/run, technical notes, limitations, status, licences.
4. Verify links/paths and that only docs/assets/task file changed; stop before commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Screenshots: captured from the Debug build (Xcode 27, macOS 27, 1x display) with screencapture -l on the app window: empty state (LTR-8 layout) and a queue state after two 2-5 s test M4A jobs completed (summary line, destination, Complete rows). Old v0.1 images (completed, language-selection, transcribing) removed; no UI altered. Test outputs on the Desktop deleted, prefs/window frame restored, app quit.
README facts checked against source: language list (TranscriptionLanguage), renderer metadata lines and the flat-vs-package Source line (TranscriptMarkdownRenderer.render), 30-minute download limit and limitations (doc-1), deployment target 26.0 (project.pbxproj), unsupported-extension behaviour (addDroppedFiles ignores them silently). Not verified: a clean-clone build on another Mac, other signing teams, Intel, notarization. No GitHub settings changed. Awaiting human review; criteria left unchecked.

Queue screenshot replaced (docs/screenshots/queue.png, 640x491 PNG) with a window-only capture (screencapture -l, title bar included, no cursor/desktop) of the real completed queue open in the running Debug build: summary '2 succeeded · 0 failed · 2h 55m of media · processed in 1m 52s · 94× realtime'; hello.m4a (M4A · 2:05:39, 91× realtime, saved hello.md); YouTube job 'Python Machine Learning Tutorial (Data Science)' (49:43, 102× realtime); English selected, Desktop output folder, source-package checkbox visible. App brought to front for an active-window capture; queue, prefs, outputs untouched, app left running. Reviewed for personal information: only the approved filenames, public YouTube title/channel and 'Desktop' label are visible. Legibility checked on a 440 px downscale (sips): headings, summary and row titles clear, the small per-row detail text is readable but small. Not verified: rendering in an actual GitHub README preview. README alt text unchanged (still accurate). Status and criteria unchanged.
<!-- SECTION:NOTES:END -->
