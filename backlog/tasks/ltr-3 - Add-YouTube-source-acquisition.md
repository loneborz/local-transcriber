---
id: LTR-3
title: Add YouTube source acquisition
status: To Do
assignee: []
created_date: '2026-09-30 20:03'
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
- [ ] #1 URL can enter the same queue as local media
- [ ] #2 Queue exposes Downloading state
- [ ] #3 yt-dlp integration is isolated from the transcription engine
- [ ] #4 Source metadata is captured
- [ ] #5 Resulting local audio enters the existing transcription service
- [ ] #6 Acquisition failure affects only that job
- [ ] #7 Remaining jobs continue
- [ ] #8 Determine the smallest robust yt-dlp/ffmpeg runtime strategy before implementation
<!-- AC:END -->
