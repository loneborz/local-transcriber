---
id: LTR-6
title: Add queue removal and reset controls
status: Done
assignee: []
created_date: '2026-09-30'
updated_date: '2026-09-30 22:01'
labels: []
milestone: m-0
dependencies:
  - LTR-1
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Remove the queue lock-in that appears after the first file is added. Let the user correct accidental additions and return to an empty/new-batch state without relaunching the app. This task adds queue editing only and must not introduce transcription cancellation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A Waiting job can be removed individually before transcription starts
- [x] #2 Removing a queued job changes only LocalTranscriber queue state and never deletes or modifies the source media file
- [x] #3 Removing the final queued job returns the app to its empty drop state
- [x] #4 When the queue is idle, the user can clear/reset the queue and start a fresh batch without relaunching the app
- [x] #5 Completed and Failed jobs can be cleared when the queue is idle so the user can return to a fresh batch
- [x] #6 An actively Transcribing job cannot be removed through this feature; cancellation remains out of scope
- [x] #7 Queue removal/reset controls do not interrupt or silently alter an active transcription
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BatchQueue: add remove(_:) (Waiting jobs only, matched by stable id), clear() (no-op while a batch is running), canClear. Idle means no job is Transcribing (queue not processing); Clear is therefore allowed for any mix of Waiting/Complete/Failed.
2. ContentView/JobRow: per-row remove control on Waiting rows only; one Clear button beside Transcribe, disabled while processing; Clear also resets the notice.
3. No cancellation, no confirmation dialog, no persistence, TranscriptionService untouched, source files never touched.
4. Verify: xcodebuild (scratch DerivedData), diff review, runtime check in the running app.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
BatchQueue: remove(_:) (Waiting only, by id), clear() guarded by canClear (!jobs.isEmpty && !isRunning). ContentView: xmark remove control on Waiting rows only; Clear button beside Transcribe, disabled while processing, resets notice. Idle = no job Transcribing. TranscriptionService untouched; no cancellation, dialogs or persistence. AC #3 rests on human 'works correctly all around' plus source: removing the last job leaves jobs empty, which drives the existing empty state (same path human verified after Clear).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added Waiting-job removal and an idle-only Clear to the batch queue (BatchQueue.swift, ContentView.swift); TranscriptionService unchanged. Verified by xcodebuild (scratch DerivedData, BUILD SUCCEEDED) and human runtime acceptance: per-row removal, no control on Transcribing rows, removal mid-run leaves the active job running and removed jobs never run, Clear disabled while processing and clears mixed Waiting/Complete/Failed queues back to the empty drop state, new files accepted afterwards, source files untouched.
<!-- SECTION:FINAL_SUMMARY:END -->
