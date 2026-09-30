---
id: LTR-1
title: Build batch queue foundation
status: Done
assignee: []
created_date: '2026-09-30 20:03'
updated_date: '2026-09-30 21:19'
labels: []
milestone: m-0
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace the current single-item orchestration with a sequential batch queue around the existing transcription engine.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Dropping five local media files creates five jobs
- [x] #2 Jobs process sequentially
- [x] #3 Each job independently reaches Complete or Failed
- [x] #4 Failure of one job does not stop remaining jobs
- [x] #5 Existing transcription behavior is preserved
- [x] #6 No YouTube support in this task
- [x] #7 No source package mode in this task
- [x] #8 The language picker is shown only while the queue is empty and sets the default language for newly created jobs; it is hidden once any job exists
- [x] #9 Every job owns its own language, shown in its row; every Waiting job has its own language picker that can be changed independently
- [x] #10 A job's language picker is locked once that job starts Transcribing; Complete and Failed jobs show the language they actually used
- [x] #11 Transcribe runs jobs sequentially, each using its own language
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added BatchQueue.swift (MainActor @Observable BatchQueue + TranscriptionJob, single sequential runner, per-job Locale) between ContentView and the unchanged TranscriptionService. Batch-level Transcribe action; drop targets on window and queue ScrollView; per-job language pickers locked once a job starts; default language picker only in empty state; compact list-row presentation. Verified by human runtime acceptance on a native Debug build: 5-job batch, one Transcribing at a time, broken-not-audio.m4a reached Failed without stopping the queue, ru-RU job completed with Language: ru-RU, English jobs en-US, Save Transcript worked during processing.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced single-item orchestration with a sequential batch queue (ContentView -> BatchQueue -> TranscriptionJob -> unchanged TranscriptionService). Each job owns its Locale, has its own language picker while Waiting, and independently ends Complete or Failed. Verified by xcodebuild (scratch DerivedData, BUILD SUCCEEDED) and human runtime acceptance: five queued jobs processed one at a time, a real AVAudio failure did not stop later jobs, per-job languages honored (ru-RU / en-US in saved Markdown). No YouTube or source-package code added.
<!-- SECTION:FINAL_SUMMARY:END -->
