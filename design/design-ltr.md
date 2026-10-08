# Design System: Local Transcriber

## 1. Visual Theme & Atmosphere

A warm, editorial product page for a small, technical Mac utility. It pairs restrained documentation-like structure with a confident oversized headline, wine accents, serif italic emphasis, and detailed file previews. The composition feels calm and capable, with generous space around practical information.

- Overall feeling: warm, precise, locally minded, and quietly technical.
- Visual density: sparse hero and section introductions; denser examples and download facts.
- Brand posture: practical and transparent. Explain what happens to media and where work runs.
- Signature motifs: paired headline phrases, selective Georgia italics, wine-colored rules, file and Markdown samples, and a small audio-meter wordmark.

### Key Characteristics

- Use warm cream and charcoal-brown surfaces instead of neutral white and black.
- Set large, tightly tracked sans-serif headlines, then color one italic serif phrase with the wine accent.
- Treat transcript and source examples as real content cards with filename bars and compact monospace text.
- Keep the product screenshot large and quiet, with a soft shadow and a small overlapping transcript card.

## 2. Color Palette & Roles

The table lists the light theme. See Theme Modes for the matching dark palette.

| Role | Semantic Name | Value | Usage |
| --- | --- | --- | --- |
| Primary action | Wine CTA | #762f3d | Filled actions and emphasized links |
| Accent | Wine | #762f3d | Italic headline emphasis and rules |
| Deep band | Deep wine | #4a252e | Download section background |
| Page background | Warm paper | #f3f0ea | Main canvas |
| Recessed surface | Deep paper | #e8e2d9 | Alternating section background |
| Card surface | Warm white | #faf8f4 | File and transcript cards |
| Main text | Ink | #2d2023 | Headings and body copy |
| Supporting text | Muted brown | #695d5c | Secondary descriptions and metadata |
| Border | Warm rule | #d4c9bd | Card edges, dividers, and header rule |
| Band accent | Pale rose | #e4b5bf | Italic emphasis on the deep band |

### Primary

- Wine is the single dominant accent. Use it for the main download action, selected emphasis, and the vertical rule beside the known-limits list.
- Deep wine creates one full-width download band. Keep its copy warm white and its secondary text dusty rose.

### Interactive

- Main CTA hover changes from #762f3d to #8a3848 and translates upward by 1px over 150ms.
- Section links use muted text and change to the main ink color on hover.
- Keyboard focus uses a 2px wine outline with a 3px offset and a 4px outline radius. Inside the download band, use the band's warm white for focus contrast.
- The theme toggle is a compact outlined square control, not a pill.

### Neutral Scale

- Warm paper #f3f0ea is the page canvas.
- Deep paper #e8e2d9 separates selected sections without adding a new hue.
- Warm white #faf8f4 distinguishes content cards from the canvas.
- Ink #2d2023 and muted brown #695d5c form the text hierarchy.
- Warm rule #d4c9bd supplies low-contrast structure.

### Surface & Overlay

- Main canvas: warm paper. Recessed sections: deep paper. Cards: warm white.
- Header overlay: translucent paper at 82% opacity with a 14px backdrop blur and 1px lower rule.
- The download band switches to deep wine, transparent outlined metadata, and light text.

## Theme Modes

The page follows the system appearance when no explicit theme is selected. In the inspected browser, the system preference initially rendered dark mode. The visible theme control switches between light and dark, updates its pressed state, and swaps the product screenshot asset. The light and dark palettes keep the same semantic roles.

### Light Mode

- Background: #f3f0ea warm paper; alternating sections use #e8e2d9.
- Surface: #faf8f4 cards, with #d4c9bd rules.
- Text: #2d2023 primary, #695d5c muted.
- Accent: #762f3d wine; download band #4a252e.
- Notes: warm and editorial, with restrained highlights and a soft card shadow.

### Dark Mode

- Background: #171214; alternating sections use #1c1618.
- Surface: #221b1e cards, with #3a3133 rules.
- Text: #ebe5dc primary, #a89d96 muted.
- Accent: #d7a3ad for emphasis and #8f3d4e for primary actions; download band #36222b.
- Notes: the hierarchy and card layout stay stable. The screenshot switches to its dark asset, while shadows deepen and the paper highlight becomes subtle.

### Shadows & Depth

- Borders define card edges; avoid replacing them with bright rings.
- File cards use a 1px rule, a subtle inset top highlight, and a broad low-opacity shadow.
- The screenshot uses layered drop shadows rather than a heavy frame.
- Focus is a clear outline, separate from resting card elevation.

## 3. Typography Rules

Use a native system sans for almost all interface and body copy. Georgia italic is a deliberate editorial accent, not a second general-purpose heading family. Use system monospace for filenames, JSON, timestamps, and small technical labels.

### Font Family

- Primary: -apple-system, BlinkMacSystemFont, "SF Pro Text", Aptos, system-ui, "Segoe UI", Roboto, sans-serif.
- Serif accent: Georgia, "Times New Roman", serif; italic, regular weight, colored wine.
- Monospace: ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, monospace.
- OpenType Features: no custom feature settings observed.

### Hierarchy

| Role | Font | Size | Weight | Line Height | Letter Spacing | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Hero headline | System sans | 80px desktop; 46.8px at 390px | 750 | 75.2px desktop; 44px mobile | -3.2px desktop; -1.87px mobile | Two short lines, tight leading; italic serif phrase stays inline |
| Section heading | System sans | 46.4px desktop; 33.6px mobile | 750 | 1.0 | -0.03em | Balanced line breaks; selective italic serif accent |
| Body | System sans | 17px | 400 | 27.2px | Normal | Warm, readable paragraphs |
| Lead | System sans | 20px desktop; 17.6px mobile | 400 | 31px desktop; 27.3px mobile | Normal | Hero summary, limited measure |
| Step heading | System sans | 18.4px | 750 | 1.6 | -0.01em | Compact instructional subhead |
| Label / technical meta | System monospace | 12px | 400 | 1.4 to 1.6 | Normal | File bar, manifest labels, compact data |
| Caption / footer | System sans | 14.4px | 400 | 23px | Normal | Secondary links and supporting details |

### Principles

- Headlines use weight and close tracking for impact, then open into generous body line-height.
- Balance headings to avoid awkward final words; preserve the short two-part hero construction.
- Reserve monospace for actual technical artifacts and metadata, not general navigation or paragraphs.

## 4. Component Stylings

### Buttons and Links

- Primary CTA: wine fill, white bold 17px text, 54px height, 10px radius, 13.6px by 21.6px padding, small inset highlight, and soft shadow.
- Secondary CTA: text link beside the main action in the hero; avoid competing button fills.
- In the download band, use a warm-white filled button with deep-wine text.
- Hover and active feel: short and crisp. The primary action darkens and lifts 1px over 150ms. The light button becomes white.
- Text links are direct and usually underlined or visibly distinct through color and placement.

### Cards and Containers

- Surface style: warm-white file cards on light backgrounds and charcoal-plum cards on dark backgrounds.
- Radius: 16px on file and metadata cards.
- Border: 1px warm rule, with a subtle inset top highlight.
- Shadow or elevation: one restrained inset highlight plus a soft broad shadow.
- Internal spacing: a compact monospace filename header separated by a rule, then padded content. Code blocks scroll horizontally when necessary.

### Inputs and Interactive Controls

- No conventional form fields appear on the inspected homepage.
- Theme control: 36px square, 1px border, 10px radius, icon-only, with an accessible pressed state.
- Transcript code examples are keyboard-focusable and scroll when their content exceeds the card width.
- Focus behavior: 2px outline, 3px offset, 4px rounding; adapt outline color within the download band.

### Navigation

- Structure: sticky 60px header with wordmark, section anchors, journal and GitHub links, and theme control.
- Background treatment: translucent theme-colored surface, backdrop blur, and thin lower border.
- Link style: compact 15px muted text; active hover increases contrast.
- Responsive behavior: section anchors hide below 861px. The brand and utility links remain visible; no replacement menu control was observed.
- Scroll behavior: anchor navigation uses smooth scrolling and 5rem scroll padding to account for the sticky header. A skip link precedes the header.

### Image Treatment

- Product UI screenshot is the main visual, shown at a wide aspect ratio with a soft layered shadow.
- Provide distinct light and dark screenshot assets and swap them with the theme.
- No decorative photography or illustration was observed. Icons are simple outline SVGs; the wordmark includes a small audio-meter mark.

### Distinctive Components

- Hero pairs the large two-line “Media in. / Markdown out.” headline and product UI screenshot; a transcript card overlaps the screenshot edge.
- Four instructional steps use numbered markers, top rules, short headings, and concise descriptions.
- File preview cards show either a YouTube source-package tree or syntax-colored JSON and Markdown.
- A two-column download manifest sits in the contrasting deep-wine band.

## 5. Layout Principles

### Spacing System

- Base unit: an 8px rhythm with 4px subdivisions.
- Repeated spacing values: 8px, 16px, 24px, 32px, 40px, 48px, 64px, and 80px; larger section spacing reaches 104px in the download band.
- Use CSS `clamp()` for hero and section padding where the page scales with viewport width.

### Grid & Container

- Grid logic: centered container capped at 1160px. Hero and main content grids become two columns at 960px. The hero uses equal columns with a 64px gap; output, local-processing, and limits sections use an uneven 0.85:1.15 split with an 80px gap. The download layout uses a 0.9:1.1 split.
- Max content width: 1160px.
- Section spacing: desktop sections are spacious; at 390px, regular sections use 64px vertical padding. Hero padding is tighter at about 36px top and 48px bottom.
- Step grid: one column below 640px, two columns from 640px, and four columns from 1000px.

### Whitespace Philosophy

- Whitespace philosophy: give section introductions and product imagery room; increase density only for lists, examples, and release facts.
- Alignment tendencies: left-aligned copy and cards; grids align to a shared centered wrapper.
- Content width behavior: explanatory copy has a limited measure, while file examples and screenshots can use the full grid column.

### Border Radius Scale

- Micro: 4px on focus outlines.
- Standard: 10px on actions and theme control.
- Large: 16px on cards and manifest.
- Pill: no pill-shaped treatment observed.

## 6. Depth & Elevation

| Level | Treatment | Use |
| --- | --- | --- |
| Flat | Warm paper or deep-paper section fill | Page canvas and alternating sections |
| Ring | 1px warm rule or translucent band rule | Cards, header, and manifest |
| Card | Inset top highlight plus low-opacity, broad shadow | File previews |
| Focus | 2px outline with 3px offset | Keyboard-accessible controls and links |

### Depth Principles

- Surface hierarchy: separate content with tonal paper shifts, then use a border and restrained shadow for file artifacts.
- Shadow language: broad, soft, low contrast; avoid floating every section.
- Blur, glass, or overlay behavior: only the sticky header uses a translucent blurred overlay.
- When depth is used versus avoided: screenshot and file cards receive depth; text sections and the download band stay flat.

## 7. Do's and Don'ts

### Do

- Keep the base palette warm and the wine accent focused.
- Use italic Georgia to emphasize a few words, not entire paragraphs.
- Make file structures and transcripts readable, believable content artifacts.
- Preserve clear distinctions between local processing and network activity in explanatory layouts.
- Keep core copy direct and specific about supported inputs, output, and constraints.

### Don't

- Add gradients, decorative photography, multiple competing accent colors, or pill-heavy UI.
- Turn technical details into tiny unreadable text; keep examples in cards with filename context.
- Make the download section look like another ordinary paper section.
- Hide keyboard focus or rely on color alone for theme and action states.

## 8. Responsive Behavior

### Breakpoints

| Name | Width | Key Changes |
| --- | --- | --- |
| Mobile | 480px and below | Main grids stack; hero type scales down; manifest becomes one column; file tree labels stack; tighter nav gaps below 380px |
| Tablet | 481px to 959px | Main two-column sections stack; nav section links hide at 860px and below; step grid uses two columns from 640px |
| Desktop | 960px and above | Hero, output, local, download, and limits sections use two-column grids; steps reach four columns at 1000px |

### Touch Targets

- Observed primary CTA height is 54px; theme control is 36px square.
- Keep text and icon controls visually distinct and retain the visible focus outline.

### Collapsing Strategy

- Desktop behavior: centered wide wrapper, side-by-side text and visual content, four-step row at 1000px and above.
- Tablet behavior: one-column main sections, two-column steps from 640px, and hidden section anchors below 861px.
- Mobile behavior: one-column content, 16px side gutters at 390px, stacked manifest fields below 480px, and smaller hero headline.
- Breakpoint-driven component changes: at 480px the manifest changes to one column and file-tree label/value pairs stack. At 380px header gaps and GitHub text size tighten.
- Touch target and spacing adjustments: preserve the 54px CTA and comfortable card padding. The theme button remains compact at 36px in the observed design.

## 9. Agent Prompt Guide

### Quick Color Reference

- Primary CTA: #762f3d in light mode; #8f3d4e in dark mode.
- Background: #f3f0ea light; #171214 dark.
- Heading text: #2d2023 light; #ebe5dc dark.
- Body text: #2d2023 light; #ebe5dc dark, with muted text #695d5c or #a89d96.
- Border or ring: #d4c9bd light; #3a3133 dark; focus uses the wine accent.
- Accent: #762f3d light; #d7a3ad for dark-mode emphasis.

### Quick Summary

- Build a warm, editorial Mac utility site with practical technical detail.
- Use a system sans hierarchy, tight oversized headlines, and selective italic Georgia.
- Keep one wine accent and a distinct dark-wine download band.
- Present transcripts, source packages, and structured data as bordered 16px file cards.
- Use a sticky blurred header, soft card shadows, thin rules, and generous section spacing.
- Support light and dark palettes with matching product screenshots and clear focus states.

### Example Component Prompts

- Hero: Create a two-column desktop hero with a tightly tracked two-line sans headline, one italic wine phrase, a concise lead, a single filled download CTA, and a wide product screenshot with a soft shadow and overlapping transcript card.
- Card: Create a warm file artifact card with a 1px border, 16px radius, subtle inset highlight, soft shadow, monospace filename bar, and readable technical sample.
- Navigation: Create a 60px sticky translucent header with a wordmark, section anchors, utility links, and outlined theme toggle. Hide section anchors below 861px.
- Button or badge: Use a bold 17px wine CTA, 10px radius, 54px height, white inset highlight, soft shadow, and a 1px upward hover lift.

### Ready-to-Use Prompt

Create a responsive product page for a local Mac utility using this design system. Use warm paper surfaces, deep brown ink, a focused wine accent, system sans typography, and selective italic Georgia emphasis. Make the headline large and short, explain the workflow in numbered steps, show output as realistic file cards, distinguish local work from network activity, and place release details in a contrasting deep-wine band. Use a sticky blurred header, responsive one-column mobile layouts, visible keyboard focus, and matched light and dark themes with separate product screenshots. Keep copy direct, specific, and transparent about limits.

### Iteration Guide

1. Keep the wide hero and file artifacts as the visual anchors.
2. Tune wrapping and spacing before introducing extra decoration.
3. Verify both theme palettes and widths around 390px, 768px, and 1440px.

## Optional Appendix: Interaction Patterns

- Scroll behavior: sticky header stays at the top; anchor scroll is smooth with top padding for the header.
- Hover behavior: primary CTA darkens and lifts by 1px; section links gain contrast; the light download CTA turns white.
- Click behavior: theme control switches palettes, updates its pressed state, and swaps the product screenshot. Initial mode follows the observed system preference unless a theme is explicitly selected.
- Animation tone: restrained and quick. Transitions are 150ms; reduced-motion preference disables transitions and smooth scrolling.

## Optional Appendix: Content & Messaging Patterns

- Headline pattern: brief two-part statement, “Media in. Markdown out.”
- CTA language: action-first and literal, such as “Download for Mac” and “Source on GitHub.”
- Trust signal pattern: state supported macOS and hardware, show signing and notarization facts, explain what stays on-device, and disclose known limits.
- Voice and tone: plain, technically specific, and unembellished. Pair a concise claim with concrete operational details.

## Optional Appendix: Observed Pages

- [Local Transcriber homepage](https://transcribe.wavesweb.nl/): inspected as the source for the visual system, responsive layout, both theme modes, and interactions. Linked Journal content was not part of this extraction.

## Optional Appendix: Evidence Notes

- Observed: live homepage DOM, computed styles, CSS variables, responsive behavior at 1440px, 768px, and 390px, hover state, and manual theme toggle.
- Observed: initial browser rendering used dark mode under the current system preference; manual selection changed the root theme attribute and screenshot asset.
- Inferred: warm paper, selective serif emphasis, and artifact-like file cards are the reusable visual language rather than one-off decorative details.
