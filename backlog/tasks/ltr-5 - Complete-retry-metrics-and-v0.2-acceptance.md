---
id: LTR-5
title: 'Complete retry, metrics and v0.2 acceptance'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-30 20:03'
updated_date: '2026-10-01 00:20'
labels: []
milestone: m-0
dependencies: []
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finish the operational UX and prove the release against the real workflow. Final acceptance: provide five real YouTube URLs, choose English once, choose the output directory once, enable source package mode, walk away, and return to five complete, traceable packages containing downloaded audio, source metadata and timestamped Markdown transcripts. No Terminal commands, no repeated Save dialogs, no manual filenames, no repeated language selection.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Successful count is shown
- [x] #2 Failed count is shown
- [x] #3 Total media duration is shown
- [x] #4 Total processing time is shown
- [x] #5 Transcription realtime speed is shown
- [x] #6 Output location is shown
- [x] #7 Failed items are individually retryable
- [x] #8 Retry does not repeat completed items
- [x] #9 Final v0.2 acceptance scenario passes: five real YouTube URLs, English chosen once, output directory chosen once, source package mode enabled, unattended run yields five complete packages (audio, source metadata, timestamped Markdown transcript)
- [x] #10 No Terminal commands, repeated Save dialogs, manual filenames or repeated language selection required
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Baseline: AC1-8 and the non-package parts of AC10 are independent of LTR-4; AC9 (five real YouTube URLs with source package mode enabled yielding audio + source metadata + transcript packages) genuinely depends on LTR-4 (declared dependencies are empty, but package mode and retained audio are LTR-4 deliverables), so AC9 cannot be satisfied or checked in LTR-5 until LTR-4 is done.
1. BatchQueue: computed batch summary (succeeded, failed, total media duration, total transcription processing time) and retry(job): only a Failed file/YouTube job returns to Waiting; invalid-link rows are not retryable; completed jobs are never touched.
2. ContentView: summary line (succeeded/failed counts, total media duration, total processing time, realtime speed, output folder with reveal) shown once any job has finished; per-row Retry button for retryable Failed rows that restarts the queue through the same destination guard as Transcribe; move the existing duration/speed formatters into one shared helper so row and summary agree.
3. No change to TranscriptionService, acquisition, output naming or LTR-6 controls.
4. Verify in the real app: counts/durations/speed/output folder; fail one job, retry it, confirm completed jobs are not re-run and the retried job completes; invalid link has no Retry; Clear/remove unchanged; build Debug+Release. AC9 reported as blocked on LTR-4.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Baseline: LTR-5 declares no dependencies, but AC9 (and the description) require source package mode with audio + source metadata + transcript per video, which is LTR-4's deliverable; LTR-3 also deletes downloaded audio after each job. So LTR-4 is a genuine prerequisite for AC9 only; AC1-8 and the non-package part of AC10 do not depend on it. LTR-4 not started.
Implemented (changed locally, NOT committed): BatchQueue.summary (succeeded/failed counts, total media duration and transcription processing time from Complete jobs, realtime speed), BatchQueue.retry + TranscriptionJob.canRetry (only Failed file/YouTube jobs; rejected links are not retryable; Complete jobs untouched); ContentView summary line + 'Show output folder: <name>' reveal link, per-row Retry button that restarts the queue through the same destination guard as Transcribe; duration/speed formatters moved into one shared MetricsFormat so rows and summary agree. TranscriptionService, acquisition, output naming and LTR-6 controls untouched.
Verified locally in the real Debug app: summary shows '2 succeeded · 2 failed · 23.4s of media · processed in 0.5s · 43x realtime' and matches the rows (19s + 4.4s media, 0.4s + 0.1s processing); output folder shown with reveal link; a failed local file (hidden then restored) got a Retry button, Retry completed only that job and saved retrytest.md; a bad-video-ID row retried and failed again; no completed job re-ran (no extra Zoo/retrytest outputs); rejected non-YouTube link has no Retry; Clear still empties the queue. Debug and Release builds succeed. Test outputs written to the Desktop destination were removed afterwards.
Not verified / open: AC9 (blocked on LTR-4); AC10 only partly (no Terminal/Save dialog/manual filename/repeated language selection observed in this session's runs, but not exercised as the full five-URL unattended scenario); 'Show output folder' click not exercised; summary after a mid-run state (counts while processing) only seen between steps.

Additional runtime verification (real Debug app, changed locally, not committed): one Cmd-V paste of five YouTube URLs (mixed youtube.com/youtu.be, extra query params) queued five jobs; one Transcribe click ran them unattended with the default English (never re-selected) and the already-restored Desktop destination; no Save dialog, no filename entry, no Terminal. Live summary mid-run read '1 succeeded - 0 failed - 19s of media...' while job 2 was Downloading. Final: '4 succeeded - 1 failed - 1m of media - processed in 1.2s - 98x realtime'; four transcripts auto-saved as '<title> [<id>].md' (spot-checked one: correct title, 00:00:30 duration, en-US, timestamped text). The fifth video (J7b0jxVB1TE) failed with 'This video is not available'; diagnosed outside the app: the bundled helper gives the same error with or without deno on PATH and no audio-only formats are listed, so the video is genuinely unavailable (not a deno/no-JS-runtime defect). Failure isolation held (the other four completed). 'Show output folder' click opened a Finder window revealing Desktop (selected within its parent, per activateFileViewerSelecting). Retry of the failed row was clicked again but the tool reported no change and the row stayed Failed; no duplicate outputs appeared, so retry-after-failure on a genuinely failing video is only inconclusive, while the earlier hidden-file retry (completed, saved) stands as the success-path evidence. Desktop test outputs removed afterwards. AC9 still blocked on LTR-4; AC10 verified only for the non-package parts (five URLs, language once, destination once, unattended, no Save dialogs/manual filenames/Terminal), not with source package mode.

LTR-4 is Done and integrated (main 434c99a). LTR-5 branch moved onto it (stash/ff/pop; ContentView conflict resolved by keeping both sourcePackageToggle and summaryView). Merged build verified (changed locally, NOT committed): AC9 scenario run in the real app with package mode on - ONE paste of five real YouTube URLs, English default never re-selected, Desktop output folder already chosen, ONE Transcribe click, no dialogs, no Terminal, no filenames typed. Result: five folders <VIDEO_ID>/ each with audio.m4a, source.json, transcript.md (jNQXAC9IVRw, E9lAeMz1DaM, d7T1-RCal24, p80VyQ5wLvg, 3D7hQReQ8vs). Validated per package: source.json parses with all required fields, videoID matches folder, sourceType youtube, audioFilename audio.m4a, locale en-US, channel/publishedDate present; audio.m4a is valid AAC and its duration matches durationSeconds (e.g. 38 vs 37.8s); transcript.md has the video title and non-empty timestamped text; queue summary read '5 succeeded - 0 failed - 2m of media - processed in 1.4s - 101x realtime'; acquisition temp dir empty. Test outputs and the package-mode setting were restored afterwards. Remaining before finalizing LTR-5: check ACs 1-10 on this evidence, final summary, commit/rebase/push. Still unverified overall: Intel/notarization (inherited), retry of a genuinely failing video after the click was inconclusive earlier.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added a queue summary and per-job retry. BatchQueue.summary totals Complete/Failed jobs (counts, total media duration, total transcription processing time) and ContentView shows 'N succeeded - M failed - media duration - processed in - realtime' plus 'Show output folder: <name>' once any job has finished; duration/speed formatting is one shared MetricsFormat used by both rows and summary. TranscriptionJob.canRetry / BatchQueue.retry return only a Failed file or YouTube job to Waiting (rejected links are not retryable; Complete jobs are never touched) and a Retry button restarts the queue through the same destination guard as Transcribe. Evidence (real app, Debug + Release builds, codesign verify passes): summary matched the rows (e.g. '2 succeeded - 2 failed - 23.4s of media - processed in 0.5s - 43x realtime'); live mid-run summary; output folder link opened Finder; a local file that failed (hidden, then restored) got Retry, Retry completed ONLY that job and saved retrytest.md (success path), with no duplicate outputs and completed jobs not re-run; a rejected link has no Retry; Clear unchanged. The permanently unavailable video J7b0jxVB1TE is NOT counted as retry evidence (it only failed again). AC9: with LTR-4 package mode on, one paste of five real YouTube URLs and one Transcribe click (English default never re-selected, Desktop output folder already chosen/persisted) produced five complete <VIDEO_ID>/ packages, each with valid audio.m4a, source.json (all required fields, matching IDs, durations) and timestamped transcript.md; summary '5 succeeded - 0 failed - 2m of media - processed in 1.4s - 101x realtime'; no Terminal, Save dialog or typed filename. AC10 reading: language and output folder are chosen once because both persist (LTR-2); the five-URL runs involved no repeated selection. After the runtime runs one unused property (BatchSummary.realtimeSpeed) was removed; the compiler confirms it was unreferenced and both builds pass. Acceptance: user directed finalization after reviewing this evidence. Unverified/inherited: Intel/x86_64 helper, notarization, Chrome browser drag; retry of a still-failing video was inconclusive and is not claimed.
<!-- SECTION:FINAL_SUMMARY:END -->
