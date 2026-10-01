---
id: LTR-8
title: Refine the empty-state hierarchy and copy
status: Done
assignee:
  - '@claude'
created_date: '2026-10-01 13:54'
updated_date: '2026-10-01 16:15'
labels:
  - ux
dependencies:
  - LTR-7
type: enhancement
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After LTR-7 made the empty state input-only, a focused design review of the running app found it still reads like a small landing page. The strongest elements are the waveform with its blue + badge and a closing slogan, while the drop target is the weakest element. Three paragraphs repeat what the tagline and the supported-input line already say, in a first-person mascot voice ("I'll pull out the audio", "Feed me", "Stick around and watch the magic happen!") used nowhere else in the app. Spacing is uneven and the group is top-aligned, so it looks loose in a taller window. Product decision: the LTR-7 interaction model is correct; this is a visual hierarchy and copy refinement only, aiming at a calm native macOS utility. The empty state should read as three semantic groups: product mark plus tagline, the drop target, and one supported-input and paste hint. Out of scope: queue-state redesign and queue copy (including the queue "Feed me" line), click-to-choose-files, default window sizing and position behavior, YouTube metadata or title work, configuration changes, processing-state redesign, broader branding, new capabilities.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The empty state shows the waveform mark, the tagline "Media in. Markdown out.", the drop target labelled "Drop here", and exactly one supporting line below it: "MP4, MOV, M4A, MP3, WAV or a YouTube link · ⌘V to paste"
- [x] #2 The pipeline explanation paragraph and the line "Stick around and watch the magic happen!" no longer appear anywhere in the empty state
- [x] #3 The waveform in the empty state has no blue + badge; the waveform still appears and animates while a batch is processing
- [x] #4 Dragging a supported file or link over the empty state shows the existing drag-over highlight, and the drop target text reads "Drop to add" while targeted and "Drop here" otherwise
- [x] #5 The empty state is arranged as three visually distinct groups (mark and tagline; drop target; supported-input and paste hint), with spacing between groups clearly larger than spacing within a group, judged on screenshots of the running app
- [x] #6 At the minimum usable window size the whole empty state is visible with no clipping and no overlap
- [x] #7 At the larger window size currently in use (about 640×545) the composition still reads as one coherent group, with no large awkward gap between the groups and no group appearing detached
- [x] #8 At rest, the drop target is clearly distinguishable from the surrounding window background at both the minimum supported window size and approximately 640×545, without requiring drag-over state to make it visible
- [x] #9 Dropping a media file or YouTube link anywhere in the window, and pasting with Cmd-V, still adds jobs and switches to the queue state, as before
- [x] #10 Supported input types are unchanged: MP4, MOV, M4A, MP3, WAV and YouTube links are accepted, other input still shows the existing notice
- [x] #11 Queue state, including its drag-over text, copy, controls and all LTR-7 behavior (queue-level language, Apply to all, destination, conditional source-package checkbox), is unchanged; removing the last item or pressing Clear returns to the new empty state
- [x] #12 Window sizing and position behavior are unchanged, and no new control, click action or capability is added to the empty state
- [x] #13 All criteria are verified by running the built app, and any preferences or window frame changed during testing are restored afterwards
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ContentView: stop rendering the shared waveform above both states. Render it inside the queue branch only when jobs exist (same spacing as today, so queue layout is unchanged) and inside the empty branch as the first element of the new empty-state layout. Remove the showsPlus parameter and the + badge overlay from WaveformBars.
2. Empty state: three groups in one centered column. Group 1 = waveform + tagline (tight spacing). Group 2 = existing drop target (same size/shape/drag-over feedback; label "Drop here", "Drop to add" while targeted; slightly stronger resting fill/stroke so it is clearly visible at rest). Group 3 = the single hint line "MP4, MOV, M4A, MP3, WAV or a YouTube link · ⌘V to paste". Keep the existing red notice below the hint. Delete the pipeline paragraph and the "Stick around…" line. Inter-group spacing clearly larger than intra-group spacing. Vertically center the column in the window so a taller window does not leave an empty lower third; no change to window sizing or position.
3. Leave untouched: queue branch and its "Feed me"/drop-more text, drop/paste handling, supported extensions, BatchQueue, TranscriptionService, YouTube code, window sizing, defaults.
4. Verify: Debug build; launch the exact built product; check the empty state at the minimum window size and ~640×545 (set via the saved window-frame preference with the app quit, restored afterwards from an exported backup); drag-over text; whole-window drop and Cmd-V; waveform animating during processing; queue state unchanged; Clear/remove returns to the new empty state. Snapshot Desktop and prefs first; remove only test output; restore preferences and window frame.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in ContentView.swift only (changed locally, verified locally, not committed): empty state is a centered column of three groups (waveform + tagline spacing 12; drop target; hint line), groups 28pt apart; hint line "MP4, MOV, M4A, MP3, WAV or a YouTube link · ⌘V to paste"; paragraph and "Stick around…" removed; "+" badge and showsPlus removed from WaveformBars; drag-over label "Feed me" -> "Drop to add" (empty state only; queue "Feed me" untouched); drop target resting fill 0.035->0.06 and stroke 0.22->0.4 for visibility. Shared waveform now renders in the queue branch only when jobs exist (same 18pt spacing, queue layout unchanged). Debug build succeeded. Runtime at ~640x545: empty state centered and balanced; Cmd-V adds a job and queue state looks identical to LTR-7; waveform animates while Transcribing (screenshots differ, bars scaled); Clear returns to the new empty state. NOT verified: minimum window size (two attempts to set the window frame via the saved preference were not honoured; stopped per bounded-retry rule), the "Drop to add" text and drag-over highlight at runtime (needs a synthetic drag), and whole-window file drop (only Cmd-V exercised). Test output removed and preferences restored from an exported backup.

Runtime evidence (drag, Finder -> real app, one attempt + one materially different retry): attempt 1 failed because the Finder window was behind other windows and the mouse-down never hit the file row (no drag, label stayed 'Drop here', nothing queued). Retry with the Finder window raised and held-press synthetic drag: while a Finder-dragged hallo.m4a was held over empty window area OUTSIDE the drop box, the label read 'Drop to add' and the existing accent-tinted fill/border highlight was shown (screenshot). Releasing there added the file as a Waiting job (M4A, 0:02) -> whole-window drop confirmed. Clear returned to the empty state ('Media in. Markdown out.' / 'Drop here' / hint line). No transcription run. Cleanup: job cleared, test Finder window closed, Desktop unchanged, prefs (incl. window frame) restored from export, app quit, no python3.13 processes.
Source check (supported-input handling): git diff of LTR-8 touches only LocalTranscriber/ContentView.swift (+30/-41) and contains no change to dropDestination, UTType/accepted types, URL validation, add/paste handling, or pasteLinks; the diff is limited to empty-state layout, copy and the WaveformBars plus badge removal. BatchQueue.swift and MyApp.swift are unchanged.
Not verified: minimum window size (deferred to manual verification by the user).

Human verification (user, running app at the minimum window size): the three-group composition stays coherent; waveform and tagline visible; drop target clearly distinguishable at rest; hint readable with no clipping or awkward wrapping. Covers #6 and the minimum-size half of #8. Prefs and window frame restored from export afterwards (app quit).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Refined the empty state in LocalTranscriber/ContentView.swift only: waveform + tagline, a labelled drop target ('Drop here' / 'Drop to add' while targeted, existing highlight kept), one hint line ('MP4, MOV, M4A, MP3, WAV or a YouTube link · ⌘V to paste'); removed the pipeline paragraph, the 'Stick around' slogan and the + badge (WaveformBars showsPlus). Queue state, input handling, window sizing and BatchQueue/MyApp unchanged. Verified: Debug build succeeded; running app at ~640x545 (layout, at-rest drop target, Cmd-V adds a job, waveform animates while transcribing, queue identical to LTR-7, Clear returns to empty state); Finder drag shows 'Drop to add' + highlight and a drop outside the drop box adds the job; minimum window size verified manually by the user; source diff shows no input-handling changes. Prefs, window frame and Desktop restored. Not committed or pushed.
<!-- SECTION:FINAL_SUMMARY:END -->
