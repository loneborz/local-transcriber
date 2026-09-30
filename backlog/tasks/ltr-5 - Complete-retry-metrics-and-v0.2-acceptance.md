---
id: LTR-5
title: 'Complete retry, metrics and v0.2 acceptance'
status: To Do
assignee: []
created_date: '2026-09-30 20:03'
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
- [ ] #1 Successful count is shown
- [ ] #2 Failed count is shown
- [ ] #3 Total media duration is shown
- [ ] #4 Total processing time is shown
- [ ] #5 Transcription realtime speed is shown
- [ ] #6 Output location is shown
- [ ] #7 Failed items are individually retryable
- [ ] #8 Retry does not repeat completed items
- [ ] #9 Final v0.2 acceptance scenario passes: five real YouTube URLs, English chosen once, output directory chosen once, source package mode enabled, unattended run yields five complete packages (audio, source metadata, timestamped Markdown transcript)
- [ ] #10 No Terminal commands, repeated Save dialogs, manual filenames or repeated language selection required
<!-- AC:END -->
