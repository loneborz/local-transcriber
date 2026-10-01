---
id: LTR-10
title: Build the initial transcribe.wavesweb.nl product site
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-01 17:38'
updated_date: '2026-10-01 17:52'
labels:
  - website
dependencies: []
type: feature
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LocalTranscriber has a README but no public product page. A visitor to the GitHub repo sees build instructions first, not what the app does, what stays on the Mac and what does not. A static site at https://transcribe.wavesweb.nl/ gives the app its own page, structurally based on the existing ChatMD site (loneborz/chatmd, website/: hand-written index.html + styles.css, self-hosted fonts, no build step) but designed for a native Swift/macOS product rather than a CLI.

Hosting is already in place: Cloud86/Plesk pulls main from loneborz/local-transcriber through a GitHub push webhook into /transcribe.wavesweb.nl, and the public document root is /transcribe.wavesweb.nl/website. Anything that reaches main under website/ is therefore published immediately. This task must be developed on a branch, and merging or pushing to main is a production deployment that needs separate explicit approval.

Source material for every claim: README.md, docs/screenshots/ and backlog doc-1 (Engineering Reference). The product boundary in CLAUDE.md applies to the copy: media or URL -> local transcript package; no summarization, search, rewriting or cloud transcription.

Direction: static HTML/CSS, one page, source only under website/. A native macOS feel: system font stack (-apple-system / SF), the real app window shown in frames, light and dark appearance following the system, restrained colour from the app (AccentColor). No terminal block, no CLI aesthetic, no ChatMD name, copy or amber accent.

Non-goals:
- No download button, release, installer, notarization or version claim; none exists.
- No framework, bundler, package.json, CI workflow or build step; no external requests (CDN, web fonts, analytics, trackers, cookies, forms).
- No DNS, Plesk or webhook changes; no GitHub repository settings (homepage URL, topics) changed. Recommendations may be reported.
- No change to the app, Vendor/, LocalTranscriber.xcodeproj or README.md, and no UI altered for screenshots.
- No new app screenshots or app icon design. Existing docs/screenshots are copied; fresh or retina captures are a separate decision.
- No multi-page site, blog, docs section, localisation or privacy page beyond what a single page needs.
- No AI marketing language, comparisons with other tools, testimonials or invented numbers.
- No new Backlog tasks created automatically; discovered follow-ups are reported only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All work is done on a branch, not main; nothing is committed to main, pushed to main or merged without separate explicit approval, and the report states which of changed locally, verified locally, committed, pushed and deployed applies
- [ ] #2 Only files under website/ (and this task file) are added or changed; no file under LocalTranscriber/, Vendor/, LocalTranscriber.xcodeproj or README.md changes, and website/ contains nothing that should not be public
- [ ] #3 The site is static HTML and CSS (at most a small inline script for progressive enhancement) with no framework, build step or package manifest, and makes no request to any origin other than its own; fonts are system fonts or self-hosted files
- [ ] #4 The layout follows the ChatMD site structure (index.html, styles.css, optional fonts/, favicon and apple-touch icon, og.png, canonical and Open Graph metadata, skip link, sticky nav, banded sections) but contains no ChatMD name, copy, terminal block or CLI styling, and looks native to macOS
- [ ] #5 The hero headline is exactly "Media in. Markdown out." with a one-sentence statement (media or URL -> local transcript package) and the real queue screenshot from docs/screenshots/queue.png in a window frame
- [ ] #6 The page explains media or YouTube link -> one sequential queue -> on-device transcription -> timestamped Markdown, including the supported inputs, per-job language and the ten languages, all matching README.md
- [ ] #7 A local-versus-network section states that transcription, audio extraction and file writing happen on the Mac, and that YouTube audio download and Apple language assets are the network steps; it does not claim the app is fully offline when links are used
- [ ] #8 A source-package section shows the folder layout (audio.m4a, source.json, transcript.md) and a sample transcript and source.json that match what the current build writes, as in README.md
- [ ] #9 A limitations section states honestly: macOS 26 or later; YouTube helper is Apple silicon only; not notarized and no release; pinned yt-dlp can break as YouTube changes; YouTube only, 30-minute download limit; early project
- [ ] #10 The call to action is "View on GitHub" (https://github.com/loneborz/local-transcriber) and "Build from source" (with the clone and xcodebuild steps from the README); there is no download button and no statement or implication that a release exists
- [ ] #11 The copy makes no claim of summarization, search, RAG, knowledge management, cloud transcription, automatic correction, Intel support or distribution, and uses no AI marketing language; each factual claim is traced to README.md, doc-1 or the source in the implementation notes
- [ ] #12 Screenshots are the real docs/screenshots images (queue.png, empty-state.png) copied into website/, shown at or below their native 860x540 size with width/height attributes and meaningful alt text, never upscaled
- [ ] #13 The page is verified in a real browser from a local static server at roughly 390, 768 and 1280 px wide in light and dark appearance: no horizontal scroll, no console errors, readable text contrast, working keyboard focus and skip link, and prefers-reduced-motion respected
- [ ] #14 Every internal link, anchor, asset path and external link resolves, and all paths are relative so the site works with website/ as the document root; title, description, canonical (https://transcribe.wavesweb.nl/) and a 1200x630 og.png are present
- [ ] #15 Publishing to production happens only after the user approves the merge; after that, the live https://transcribe.wavesweb.nl/ is checked (HTTPS 200, expected title and assets, record state before and after) and the result reported separately from local verification
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Research (done): ChatMD website/ structure, README.md, doc-1, the two real screenshots (dark app window, 860x540, rounded corners), AccentColor (unset, so system blue), hosting model (document root = website/, push to main deploys).
2. Branch claude/ltr-10-product-site from clean main; no commits to or pushes of main.
3. Build website/ as one static page: index.html + styles.css, no fonts (system stack), no external requests. Colour via CSS custom properties with a prefers-color-scheme dark block only (no toggle, no theming system). Waveform mark as inline SVG derived from the in-app mark; favicon.svg/png and apple-touch-icon from the same mark.
4. Sections: sticky nav; hero ("Media in. Markdown out.", one-sentence statement, View on GitHub / Build from source, queue screenshot in a window frame); How it works (input -> queue -> on-device transcription -> Markdown, inputs, languages); Output (sample Markdown); Local versus network table; Source packages (layout + source.json); Limitations; Build from source (README commands); footer. Copy only from README.md / doc-1.
5. Copy docs/screenshots/queue.png and empty-state.png into website/assets/ unmodified (860x540, width/height set, never upscaled). Compose og.png (1200x630) with headless Chrome from an HTML scratch page in the scratchpad: headline, mark and the existing queue.png in a frame; no new capture, no invented UI.
6. Verify locally with python3 -m http.server and headless Chrome at 390/768/1280 in light and dark: screenshots, horizontal overflow and console errors via DevTools protocol, link/asset/anchor resolution script, grep for banned claims and ChatMD leftovers, contrast spot-check, reduced-motion and focus styles reviewed.
7. Confirm git diff touches only website/ and the task file; stop uncommitted for review; no merge, push or deploy.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented on branch claude/ltr-10-product-site (uncommitted, not pushed): website/index.html, styles.css, favicon.svg/png, apple-touch-icon.png, og.png (1200x630, composed in headless Chrome from the existing queue.png plus the in-app waveform mark; no new capture), assets/queue.png and empty-state.png (byte copies of docs/screenshots). System fonts only; one CSS-level prefers-color-scheme block; no script. Copy taken from README.md and doc-1 (sample Markdown and source.json copied from README).
Local verification (headless Chrome via DevTools protocol, python http.server, DPR 2): 390/768/1280 px x light/dark: no horizontal overflow, no console/log/network errors, zero non-local requests, images load at native 860x540 (never upscaled; displayed smaller on narrow screens). Fixed during verification: grid min-content overflow at 390 px, hero word spacing, dark shadow banding, tag contrast (now >=4.5). Link check: 24 refs, all anchors/files resolve; 4 distinct GitHub URLs return 200. Skip link and focus ring checked by Tab key; scroll-behavior is auto under prefers-reduced-motion. Banned-claim grep: every hit is a negation or limitation. Not verified: Safari/Firefox rendering, a real iPhone, production. Known limit: 860 px screenshots look soft on 2x displays; fresh retina captures are out of scope.
<!-- SECTION:NOTES:END -->
