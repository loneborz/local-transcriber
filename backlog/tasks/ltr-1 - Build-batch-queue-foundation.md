---
id: LTR-1
title: Build batch queue foundation
status: To Do
assignee: []
created_date: '2026-09-30 20:03'
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
- [ ] #1 Dropping five local media files creates five jobs
- [ ] #2 Jobs process sequentially
- [ ] #3 Each job independently reaches Complete or Failed
- [ ] #4 Failure of one job does not stop remaining jobs
- [ ] #5 Existing transcription behavior is preserved
- [ ] #6 No YouTube support in this task
- [ ] #7 No source package mode in this task
<!-- AC:END -->
