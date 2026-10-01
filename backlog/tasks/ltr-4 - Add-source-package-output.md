---
id: LTR-4
title: Add source package output
status: Done
assignee:
  - '@claude'
created_date: '2026-09-30 20:03'
updated_date: '2026-10-01 00:16'
labels: []
milestone: m-0
dependencies: []
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Provide optional traceable source packages for research/archive workflows. source.json must be a LocalTranscriber-owned stable metadata schema rather than a raw yt-dlp metadata dump.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 For YouTube sources, output is VIDEO_ID/ containing audio.m4a, source.json and transcript.md
- [x] #2 source.json is a LocalTranscriber-owned stable metadata schema, not a raw yt-dlp metadata dump
- [x] #3 source.json preserves source type
- [x] #4 source.json preserves source URL
- [x] #5 source.json preserves video ID
- [x] #6 source.json preserves title
- [x] #7 source.json preserves channel
- [x] #8 source.json preserves publication date when available
- [x] #9 source.json preserves duration
- [x] #10 source.json preserves acquisition timestamp
- [x] #11 source.json preserves local audio filename
- [x] #12 source.json preserves transcription locale
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Worktree: this work lives in ../local-transcriber-ltr4 (branch claude/ltr-4-source-package, from clean main 57e6112) so the uncommitted LTR-5 work in the main checkout is untouched.
Design (optional source package = a mode, YouTube sources only; local files unchanged):
1. SourcePackage.swift (new): SourcePackageManifest, an app-owned Codable schema (schemaVersion, sourceType, sourceURL, videoID, title, channel, publishedDate, durationSeconds, acquiredAt, audioFilename, transcriptionLocale), never raw yt-dlp JSON; stable key order; optional fields omitted when unknown.
2. OutputDestination.writePackage: creates <VIDEO_ID>/ with a no-overwrite directory (numeric suffix if it already exists, same rule as .md collisions), copies the downloaded audio as audio.m4a, writes source.json and transcript.md, and removes a half-written package it created if any step fails (error then follows the existing job.saveError path).
3. BatchQueue: when package mode is on and the job is a YouTube job with metadata, save the package instead of the flat .md; transcript.md is rendered with the real video title and URL rather than the temp audio filename (small renderer overload; the flat .md output is unchanged).
4. ContentView: a persisted 'Save YouTube links as source packages' checkbox beside the output-folder control, disabled while processing.
5. README: document the package layout and schema.
6. Verify in the real app: package folder contents, source.json fields/values, transcript.md, collision handling, local files and flat YouTube output unchanged when the mode is off, save-failure path, Debug+Release build. LTR-5 stays In Progress and untouched; it resumes after LTR-4 is integrated.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added an optional source-package mode for YouTube sources (persisted checkbox 'Save YouTube links as source packages', off by default). With it on, each YouTube job writes <VIDEO_ID>/ containing audio.m4a (the downloaded audio, copied out of the temp directory), source.json and transcript.md; local files still save as a single .md, and with the mode off YouTube jobs still save the flat 'Title [ID].md'. source.json is an app-owned, versioned schema (SourcePackageManifest: schemaVersion, sourceType, sourceURL, videoID, title, channel, publishedDate, durationSeconds, acquiredAt, audioFilename, transcriptionLocale) built from SourceMetadata, never raw yt-dlp JSON; unknown optional fields are omitted. transcript.md describes the video (title, URL, channel, published date) via a small renderer overload instead of the temp audio filename; the flat .md is unchanged. OutputDestination.writePackage never reuses or overwrites a folder (repeat of a video becomes '<ID> 2') and removes a package folder it created if a later step fails; failures use the existing job.saveError / Save Transcript path. Verified locally in the real Debug app (worktree build): packages for jNQXAC9IVRw and E9lAeMz1DaM each held audio.m4a (valid AAC m4a, 19s), parseable source.json with correct values (title, channel, 2005-04-24 / 2018-10-25, duration, UTC acquiredAt, en-US) and transcript.md; a repeat became 'jNQXAC9IVRw 2'; local alpha.m4a stayed flat alpha.md in the same batch; mode off gave the flat file again; temp acquisition dir empty; read-only destination -> job Complete with 'Not saved: You don't have permission…' and Save Transcript…, nothing created; scratch harness confirmed sparse metadata omits channel/publishedDate/durationSeconds. Debug and Release builds succeed, codesign --verify --deep --strict passes. Acceptance: the user directed LTR-4 to be started, finalized and integrated before returning to LTR-5. Not verified: the cleanup of a half-written package when a step after folder creation fails (code path only; the only failure exercised was folder creation itself), Chrome/other-browser concerns (n/a), Intel and notarization (inherited from LTR-3).
<!-- SECTION:FINAL_SUMMARY:END -->
