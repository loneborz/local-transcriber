---
id: LTR-6
title: 'Add queue removal and reset controls'
status: To Do
assignee: []
created_date: '2026-09-30'
labels: []
milestone: m-0
dependencies: [LTR-1]
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Remove the queue lock-in that appears after the first file is added. Let the user correct accidental additions and return to an empty/new-batch state without relaunching the app. This task adds queue editing only and must not introduce transcription cancellation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A Waiting job can be removed individually before transcription starts
- [ ] #2 Removing a queued job changes only LocalTranscriber queue state and never deletes or modifies the source media file
- [ ] #3 Removing the final queued job returns the app to its empty drop state
- [ ] #4 When the queue is idle, the user can clear/reset the queue and start a fresh batch without relaunching the app
- [ ] #5 Completed and Failed jobs can be cleared when the queue is idle so the user can return to a fresh batch
- [ ] #6 An actively Transcribing job cannot be removed through this feature; cancellation remains out of scope
- [ ] #7 Queue removal/reset controls do not interrupt or silently alter an active transcription
<!-- AC:END -->
