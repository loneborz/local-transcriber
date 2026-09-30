---
id: LTR-2
title: Add automatic output and persistent defaults
status: Done
assignee: []
created_date: '2026-09-30 20:03'
updated_date: '2026-09-30 22:58'
labels: []
milestone: m-0
dependencies: []
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Remove repeated save and language-selection friction for local batch transcription.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Language can be selected once and inherited by batch jobs
- [x] #2 Destination can be selected once and inherited by batch jobs
- [x] #3 Successful jobs save automatically
- [x] #4 Local source.m4a produces source.md
- [x] #5 No per-item Save dialog
- [x] #6 Destination persistence respects actual macOS sandbox/security requirements
- [x] #7 Inspect entitlements before assuming security-scoped bookmarks are required
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Spike: implement OutputDestination with an app-scoped security-scoped bookmark and test persistence across relaunch WITHOUT the bookmarks entitlement; add a minimal .entitlements + project.pbxproj change only if the spike fails without it.
2. OutputDestination (new file): folder-only NSOpenPanel, bookmark in UserDefaults, explicit none/ready/unavailable status, Transcript -> <basename>.md with numeric suffixes via no-overwrite writes.
3. BatchQueue: owns the destination; saves each job immediately after it completes; save failure is recorded in job.saveError and never turns the job Failed.
4. ContentView: persist default language (@AppStorage); compact 'Saves to: X / Change…' control in empty and queue states, disabled while processing; Transcribe with no destination opens the picker once (cancel = no start); Save Transcript only as fallback when auto-save failed.
5. TranscriptionService untouched; no YouTube/source packages/persistence of queue.
6. Verify: xcodebuild (scratch DerivedData), real files on disk, relaunch persistence, failure isolation, LTR-6 controls.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Runtime defect found in manual E2E: OutputDestination.write combined Data.WritingOptions .withoutOverwriting with .atomic, which Foundation traps on (Data+Writing.swift:793 'withoutOverwriting is not supported with atomic'; reproduced standalone). Fixed by using .withoutOverwriting alone; no bookmarks entitlement added (not required). Human E2E on the fixed build (changed locally, verified locally, not committed): restored bookmark showed 'Saves to: out' after relaunch with no re-pick; two same-named beta.m4a jobs both completed, no crash, auto-saved as beta.md and 'beta 2.md' (no overwrite). On-disk check: both 212-byte valid Markdown (title, Source/Duration/Language/Engine header, timestamped transcript); identical content as expected since both inputs are the same audio. Not yet verified: save-error path with an unwritable destination.

Human runtime E2E (accepted by user): changed Default language to Dutch, dropped multiple files; all jobs inherited Dutch, transcribed and auto-saved with nl-NL metadata; Default language persisted across quit/relaunch. Combined with the earlier destination-restore and beta.md / 'beta 2.md' collision E2E, all 7 criteria verified. Read-only destination save-error path left unexercised at runtime (optional hardening, outside the acceptance criteria).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added OutputDestination (folder-only NSOpenPanel, security-scoped bookmark in UserDefaults, none/ready/unavailable status, no-overwrite numeric-suffix writes), BatchQueue auto-save with job.saveError isolation, and persisted default language in ContentView. Fixed a crash found in manual testing (.withoutOverwriting combined with .atomic traps in Foundation) by dropping .atomic. No bookmarks entitlement needed. Verified by xcodebuild plus human runtime E2E: bookmark restored after relaunch, beta.md / beta 2.md collision suffixing without overwrite, Dutch default inherited (nl-NL) and persisted across relaunch.
<!-- SECTION:FINAL_SUMMARY:END -->
