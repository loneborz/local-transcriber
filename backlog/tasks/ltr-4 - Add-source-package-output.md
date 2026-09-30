---
id: LTR-4
title: Add source package output
status: To Do
assignee: []
created_date: '2026-09-30 20:03'
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
- [ ] #1 For YouTube sources, output is VIDEO_ID/ containing audio.m4a, source.json and transcript.md
- [ ] #2 source.json is a LocalTranscriber-owned stable metadata schema, not a raw yt-dlp metadata dump
- [ ] #3 source.json preserves source type
- [ ] #4 source.json preserves source URL
- [ ] #5 source.json preserves video ID
- [ ] #6 source.json preserves title
- [ ] #7 source.json preserves channel
- [ ] #8 source.json preserves publication date when available
- [ ] #9 source.json preserves duration
- [ ] #10 source.json preserves acquisition timestamp
- [ ] #11 source.json preserves local audio filename
- [ ] #12 source.json preserves transcription locale
<!-- AC:END -->
