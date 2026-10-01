---
id: LTR-7
title: Make the empty state input-only and move configuration into the queue
status: Done
assignee:
  - '@claude'
created_date: '2026-10-01 09:58'
updated_date: '2026-10-01 13:19'
labels:
  - ux
  - queue
dependencies:
  - LTR-2
  - LTR-6
type: enhancement
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
v0.2 user testing and an independent friction audit found that configuration appears in the wrong phase. The empty state shows default language, output destination and the YouTube source-package checkbox before anything is queued, although the checkbox is irrelevant until a YouTube link exists. Once the first item is added, the default-language control disappears, so the remembered default can only be changed by clearing the queue. The only remaining language control is per row, so setting one language for a batch means changing every row. Product decision: the empty state is input-only and the queue state owns configuration. A queue-level language control with an explicit Apply to all action replaces the lost default-language control. Existing remembered-default behavior (the persisted defaultLanguage preference from LTR-2) is preserved, not removed. Out of scope: YouTube title or metadata before acquisition, summary redesign, queue auto-scroll, retry UX changes, failed-row removal, general visual redesign, v0.3 roadmap work. See doc-1 (Queue semantics, Output and persistent state) for current behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 On a fresh launch or after Clear, the empty state shows the product identity, the drop target and concise supported-input guidance, and none of: a language picker, the output destination control, the source-package checkbox
- [x] #2 The empty-state guidance still names the supported inputs (MP4, MOV, M4A, MP3, WAV, YouTube link) and that links can be pasted with Cmd-V; the overall visual style is not redesigned
- [x] #3 Adding the first item (drop or Cmd-V, file or YouTube link) switches to the queue state, which shows the output destination control and a queue-level language selector
- [x] #4 The source-package checkbox belongs to the queue state only. It is shown only while the current queue contains at least one YouTube job (Waiting, active, Complete or Failed); a queue containing only local files shows no YouTube-specific control
- [x] #5 Adding a YouTube link to a local-only queue makes the source-package checkbox appear; removing the last YouTube job (leaving only local jobs) makes it disappear, and the persisted sourcePackageMode preference is not changed by showing or hiding the control
- [x] #6 A source-package preference set earlier still applies when the control reappears or when a later queue contains a YouTube job; it is shown with its persisted value
- [x] #7 With no output folder set, the empty state shows no folder prompt; starting a batch with no folder still asks once, and cancelling starts nothing (existing behavior unchanged)
- [x] #8 The queue-level language selector shows the persisted default language, and changing it persists across quit and relaunch, as the old Default language control did
- [x] #9 Items added after the selector is changed inherit its current value; changing the selector alone does not change the language of items already in the queue
- [x] #10 An explicit Apply to all button (not a checkbox or toggle) is available when two or more jobs are Waiting; activating it sets the language of every Waiting job to the selector value, and it is absent or disabled when fewer than two Waiting jobs exist
- [x] #11 Apply to all never changes an active (Downloading or Transcribing), Complete or Failed job, which keep their language
- [x] #12 After Apply to all, any Waiting row can still be changed individually with its own picker, and that override is not undone by later selector changes
- [x] #13 The queue-level language selector and Apply to all follow the existing rule that per-job language is editable only while Waiting; they cannot alter a job that has started
- [x] #14 In a mixed local and YouTube queue, a run behaves as in v0.2: sequential processing, each job uses its own language (checked by the Language line in each transcript), a failing job does not stop the others
- [x] #15 With the source-package preference on, YouTube links still produce <VIDEO_ID>/audio.m4a, source.json and transcript.md and local files still produce flat <name>.md; automatic output and no-overwrite suffixing are unchanged
- [x] #16 Removing Waiting items, Retry of a failed file or YouTube job, and Clear still work; Clear returns to the input-only empty state
- [x] #17 Removing the last queued item returns to the input-only empty state with no configuration shown
- [x] #18 Output destination, the source-package checkbox (when shown) and the new language controls are disabled or inert as before while a batch is running, except where the existing rules explicitly allow editing a Waiting job language
- [x] #19 All criteria are verified by running the built app; the preferences and output folder changed during testing are restored afterwards
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BatchQueue: add `waitingCount`, `hasYouTubeJobs` (any job whose source is .youtube, any state) and `applyLocale(_:)` which sets locale only on Waiting jobs. No change to run/save/retry/remove/clear.
2. ContentView empty state: remove languagePicker, destinationControl and sourcePackageToggle from the empty branch; keep identity, drop target, notice, supported-input line and explanatory copy.
3. ContentView queue state: add one compact language row (queue-level Picker bound to the existing persisted `defaultLanguage` @AppStorage, so new items inherit it; changing it never touches existing jobs) with an `Apply to all` Button shown only when waitingCount >= 2. Source-package checkbox shown only when queue.hasYouTubeJobs; the persisted preference is never written by showing/hiding. Destination control stays; remains disabled while processing, as does the checkbox. The language selector stays enabled while running (it only affects new items and Waiting jobs, consistent with per-row editing rules).
4. Do not touch TranscriptionService, YouTube code, output writers, summary, scrolling, retry UX, failed-row removal.
5. Verify: xcodebuild Debug build; launch exactly the built app; walk the acceptance criteria in the real app with the macOS UI tools (empty state, first item, local-only vs YouTube queue, checkbox appear/disappear and preference unchanged, selector persistence, Apply to all with waiting/active/complete/failed jobs, per-row override, mixed run with per-job languages, package output, removal/retry/clear). Snapshot the output folder first; afterwards delete only test output and restore preferences (language, source-package checkbox).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented (changed locally, verified locally, not committed): BatchQueue gained waitingCount, hasYouTubeJobs (any state) and applyLocale (Waiting jobs only). ContentView: empty state is input-only; queue state shows a queue-level Language picker (bound to persisted defaultLanguage) with an Apply to all button when 2+ Waiting jobs, the destination control, and the source-package checkbox only while the queue contains a YouTube job. Debug build succeeded; behavior checked in the running app. Not run: active-job case of Apply to all, and the destination/checkbox lock during a run (unchanged code, not re-observed). Test output removed from Desktop; defaultLanguage=en-US and sourcePackageMode=0 restored.

Follow-up runtime check (verified locally): queue of Karpathylecture-5min.m4a (active, Transcribing) plus hello.m4a and hallo.m4a (Waiting), all English. After Transcribe, queue selector set to German and Apply to all pressed mid-run: active row stayed English, both Waiting rows became German (screenshot). Saved transcripts: Karpathylecture-5min.md en-US, hello.md and hallo.md de-DE. Test output removed; defaultLanguage=en-US, sourcePackageMode=0 restored.

Human acceptance given by the user for the LTR-7 interaction (empty state input-only, local-file queue configuration, multi-job language + Apply to all, YouTube-specific configuration appearing and disappearing). Criteria #7 (no-folder prompt), #16 (Retry after the change) and #18 (checkbox lock during a run) were not re-observed in the running app after this change and are left unchecked; the code paths are unchanged. During the mid-run check the destination Change… link was seen disabled while the batch ran.

Remaining runtime checks (verified locally, Debug build, correct path confirmed). #7: with outputDestinationBookmark removed (original prefs exported first), the empty state showed no folder prompt; after adding a file and pressing Transcribe the folder panel opened once ("Choose where transcripts are saved."); Cancel started nothing (job stayed Waiting, no files written, no bookmark set, link read "Choose an output folder…"). Original preferences then restored by importing the export (identical except the saved window frame). #16: Retry on a failed YouTube link (nonexistent video) returned only that job to Waiting/Downloading and it failed again with the same message; the Complete job was not re-run (no duplicate package folder). Removal of a Waiting job and Clear were observed earlier in this task. #18: during an active run the source-package checkbox, the "Change…" destination link and Clear were disabled (screenshot), per-row pickers were disabled, and the queue-level language selector stayed enabled; the controls re-enabled when the run ended. Cleanup: only the test-created jNQXAC9IVRw folder was deleted; pre-existing Desktop items from the user testing (H6SiAe-VObA, Karpathylecture-5min.md) were left untouched.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Made the empty state input-only (identity, drop target, supported-input guidance) and moved configuration into the queue state: a queue-level Language picker bound to the persisted defaultLanguage, an Apply to all button shown with 2+ Waiting jobs that updates Waiting jobs only (BatchQueue.applyLocale), the existing output destination control, and the source-package checkbox shown only while the queue contains a YouTube job in any state (BatchQueue.hasYouTubeJobs; the preference is never written by showing/hiding). Changed LocalTranscriber/BatchQueue.swift (+15) and LocalTranscriber/ContentView.swift (+22/-13); no other product code touched. Verified by a Debug xcodebuild (BUILD SUCCEEDED) and by running the built app: all 19 criteria observed, including a mid-run Apply to all (active job kept its language, Waiting jobs changed, transcripts en-US/de-DE), the no-folder prompt with Cancel, Retry, and control locking during a run. The user gave human acceptance of the interaction. Not covered: Release configuration; changed locally and verified locally only, not committed.
<!-- SECTION:FINAL_SUMMARY:END -->
