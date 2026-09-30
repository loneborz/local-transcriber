---
id: LTR-2
title: Add automatic output and persistent defaults
status: To Do
assignee: []
created_date: '2026-09-30 20:03'
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
- [ ] #1 Language can be selected once and inherited by batch jobs
- [ ] #2 Destination can be selected once and inherited by batch jobs
- [ ] #3 Successful jobs save automatically
- [ ] #4 Local source.m4a produces source.md
- [ ] #5 No per-item Save dialog
- [ ] #6 Destination persistence respects actual macOS sandbox/security requirements
- [ ] #7 Inspect entitlements before assuming security-scoped bookmarks are required
<!-- AC:END -->
