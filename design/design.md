# Design System: Wavesweb Homepage

Source: [wavesweb.nl homepage](https://wavesweb.nl/). This guide records the homepage as rendered during a live browser inspection. Values labeled as measured come from computed browser styles at the viewport widths listed in Responsive Behavior. Other pages linked from the homepage were not inspected.

## 1. Visual Theme & Atmosphere

Wavesweb feels like a thoughtful independent studio: warm paper, dark wine, quiet gray, and large editorial type create a calm surface for fairly technical work. The layout has generous breathing room, but its content is not vague or decorative. It explains a problem, names an approach, then backs up the claim with structured evidence and small project artifacts. Section changes rely on color and composition more than boxes. The hero is centered and expressive; the situations ledger is analytical; the evidence area is a contrasting wine field; the Labs area is a compact project catalog; and the footer closes with an oversized editorial statement.

- Overall feeling: warm, assured, investigative, and human.
- Visual density: sparse in the hero, information-dense in evidence and project cards, with strong spacing between sections.
- Brand posture: personal and first-person, with proof of work in place of broad promotional claims.
- Signature motifs: wine-colored sections and actions, oversized type, italic Georgia emphasis, numbered evidence, a floating translucent navigation pill, and an animated five-line wave signal.

### Key Characteristics

- Pair soft cream and dusty pink with deep burgundy, then keep other accent colors out of the main interface.
- Treat typography and section color as the main hierarchy. Use cards when content needs an inspectable boundary.
- Put concrete labels, numbers, states, and artifacts inside project cards so they read as evidence rather than generic feature tiles.
- Use italics sparingly to give one phrase in a headline a literary accent.
- Keep the mood warm in both appearance modes. Dark mode uses brown-black and wine rather than pure black.

## 2. Color Palette & Roles

The website exposes separate light and dark tokens on the root element. Values below are taken from computed CSS variables or computed component styles. `#F7F1E7` is the observed light Labs card surface; the other named palette values are root tokens or sampled section and control colors.

| Role | Semantic Name | Value | Usage |
| --- | --- | --- | --- |
| Primary action, light | Wine | `#762F3D` | Filled CTA, active links, active markers, and the light-theme accent |
| Primary action, dark | Berry | `#8F3D4E` | Filled CTA with white label; the dark-theme CTA uses a deeper berry than the dusty-pink accent |
| Deep accent | Wine shadow | `#4A252E` | Light-theme evidence section, secondary action text, and CTA hover |
| Page background, light | Warm stone | `#E8E2D9` | Main homepage ground in light mode |
| Page background, dark | Deep paper | `#1C1618` | Main homepage ground in dark mode |
| Base paper, light | Paper | `#F3F0EA` | Primary light surface and light-mode hover surface |
| Base paper, dark | Night paper | `#171214` | Deepest dark surface and footer ground |
| Main text, light | Dark ink | `#2D2023` | Body copy and section headings in light mode |
| Main text, dark | Warm ink | `#EBE5DC` | Body copy in dark mode |
| Display text, dark | Warm white | `#F3F0EA` | High-contrast display headings and footer brand |
| Card surface, light | Cream card | `#F7F1E7` | Raised Labs project cards and the light evidence panel text field |
| Card surface, dark | Charcoal plum | `#251E20` | Raised Labs project cards in dark mode |
| Muted text, light | Muted brown | `#695D5C` | Supporting copy and secondary information |
| Muted text, dark | Warm gray | `#A89D96` | Secondary copy and mid-tone wave traces |
| Border, light | Warm border | `#D4C9BD` | Inset card outline and restrained dividers |
| Border, dark | Charcoal border | `#373131` | Dark card inset outline |
| Rule, light | Stone rule | `#A89D96` | Fine separators and muted details |
| Rule, dark | Dim rule | `#605855` | Low-contrast separators and outer wave traces |
| Active detail | Rose | `#D7A3AD` | Selected evidence-tab rule and the core hero wave |

### Primary

- Light-theme actions use wine `#762F3D` with white text.
- Dark-theme filled CTAs use berry `#8F3D4E` with white text. Dusty pink `#D7A3AD` remains the accent for selected markers, the wave core, and evidence rules.
- The evidence band stays deep wine in both modes: `#4A252E` in light mode and `#36222B` in dark mode.

### Interactive

- Active navigation and selected states use the current theme's accent.
- Light CTA hover moves to `#4A252E`; dark CTA hover moves to `#9C4A5B`.
- Navigation links shift toward the deeper wine on hover. Focus-visible navigation and brand links use a 2px wine outline with a 3px offset. Footer links use a 2px dusty-pink outline with a 3px offset.
- Transitions are short and restrained: CTA color, shadow, and transform transition over 0.18 seconds; theme surfaces transition over 0.24 seconds.

### Neutral Scale

- Light mode moves from paper `#F3F0EA` through warm stone `#E8E2D9` to ink `#2D2023`.
- Dark mode moves from deep paper `#171214` through page ground `#1C1618` and card ground `#251E20` to warm ink `#EBE5DC`.
- Gray tokens stay warm rather than blue. Use `#A89D96` for secondary detail and `#605855` for low-contrast dark rules.

### Surface & Overlay

- Main homepage ground: `#E8E2D9` in light mode, `#1C1618` in dark mode.
- Raised project cards: `#F7F1E7` in light mode, `#251E20` in dark mode.
- Footer: `#2D2023` in light mode, `#120E10` in dark mode.
- The floating navigation pill uses a translucent surface, a subtle warm border, an inset highlight, and a soft shadow. It is the one glass-like surface; keep other sections matte.

## Theme Modes

The page provides explicit light and dark choices. Changing modes recolors surfaces, text, borders, card shadows, the navigation pill, and the filled CTA. The wine family changes role while pink remains the prominent dark-mode accent. The evidence band remains a strong contrast block in both modes.

### Light Mode

- Background: homepage ground `#E8E2D9`; base paper `#F3F0EA`.
- Surface: cream cards `#F7F1E7`; light footer `#2D2023`.
- Text: ink `#2D2023`, with display white `#F3F0EA` where placed on dark surfaces.
- Accent: wine `#762F3D`; deep wine `#4A252E`; active pink `#D7A3AD`.
- Notes: the evidence section is a solid deep-wine block with warm-white text. Light cards use a restrained inset border and soft shadow.

### Dark Mode

- Background: homepage ground `#1C1618`; deepest paper `#171214`.
- Surface: cards `#251E20`; evidence band `#36222B`; footer `#120E10`.
- Text: warm ink `#EBE5DC`; display headings `#F3F0EA`.
- Accent: dusty rose `#D7A3AD`; pale rose `#E4C6C8`. Filled CTA: berry `#8F3D4E` with white text; hover: brighter berry `#9C4A5B`.
- Notes: borders and rules recede into plum-gray. Card depth is mostly an inset border with a very soft shadow, not a large floating elevation.

### Shadows & Depth

- Light card shadow token: `0 12px 28px #30202312`; the sampled project card uses a 1px inset border plus `0 6px 18px` at 5% opacity.
- Dark card outline: 1px inset `#373131`, with the same soft `0 6px 18px` shadow scale. The dark CTA shadow token is `0 8px 18px #00000052`.
- Light CTA shadow token: `0 8px 18px #4A252E24`; the sampled CTA uses a subtle 14% wine shadow.
- The navigation pill uses a three-part shadow: inset top highlight, soft 12px/30px lift, and a faint 1px/2px contact shadow.
- Focus is an outline or small underline, not a glow.

## 3. Typography Rules

Use a clean system sans for most content and Georgia for selected italic phrases and small editorial indices. The effect comes from the contrast between precise, closely tracked sans-serif display text and a few quiet serif accents. Keep copy widths controlled and line lengths readable.

### Font Family

- Primary: `Aptos, "Segoe UI", sans-serif` as declared and computed by the page. The actual rendered face depends on the visitor's installed fonts.
- Serif accent: `Georgia, "Times New Roman", serif`, used for italic emphasis and numbered evidence indices.
- Monospace: system monospace stack for technical artifacts where needed; it is not a dominant homepage typeface.
- OpenType Features: no custom feature settings were observed.

### Hierarchy

Sizes below are measured at 1440px unless the note says otherwise. Fluid CSS tokens compress the same hierarchy on smaller screens.

| Role | Font | Size | Weight | Line Height | Letter Spacing | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Hero headline | Aptos stack | 70.16px at 1440px; 45px at 360px | 750 | 65.95px desktop; 42.75px at 360px | -0.035em | Centered, tightly led, usually split across deliberate lines; the emphasized word is Georgia italic |
| Section heading | Aptos stack | 44.64px | 750 | 43.75px | -0.03em | Large but smaller than the hero; one phrase may switch to Georgia italic |
| Project title | Aptos stack | 21.6px | 750 | 24.19px | -0.025em | Clear card title, not a display headline |
| Body | Aptos stack | 16px; hero support 17.28px desktop | 400 | 24px; hero support 28.51px desktop | Normal | Main copy stays readable and conversational; hero copy is held to about 46ch |
| Label / Eyebrow | Aptos stack | 12.16px | 800 | 14.59px | 0.14em | Uppercase, compact, and widely tracked |
| CTA | Aptos stack | 16px | 800 | 24px | Normal | Bold and verb-led |
| Footer statement | Aptos stack | 54.4px | 760 | 53.31px | -0.035em | Large two-line sign-off |
| Evidence index | Georgia italic | 14.4px | 400 | 21.6px | Normal | Small editorial counter before a tab label |

### Principles

- Use a compact leading ratio for display text: about 0.94 for the hero and 0.98 for section headings.
- Set display tracking tightly, then use normal tracking for body copy.
- Use Georgia italics for a selected word or index, not for whole paragraphs.
- Keep labels uppercase with generous tracking, while keeping body copy in sentence case.
- Let a smaller viewport reduce the display size and adjust the line breaks; do not simply scale the desktop headline without checking its measure.

## 4. Component Stylings

### Buttons and Links

- Primary CTA: light fill `#762F3D`; dark fill `#8F3D4E`; white label in both modes; 10px radius; 51px measured height; padding of about 13.6px by 18.4px. Use 800 weight and a small soft shadow.
- Secondary CTA: transparent background, bold wine-colored text, and a fine underline rule. It sits beside the primary action without competing for fill or weight.
- Text links: mainly plain text, with accent or muted color shifts on hover. Navigation links use a 44px high hit area on desktop.
- Hover and active feel: the primary CTA darkens in light mode or lightens in dark mode, and its shadow grows slightly over 0.18 seconds. The evidence selection gains a 3px inset pink rule at the top. No button lift was observed.
- Focus: retain the visible focus treatments on navigation and footer links. Mobile menu and theme controls have 44px minimum dimensions.

### Cards and Containers

- Surface style: matte cream in light mode and dark plum-charcoal in dark mode.
- Radius: 16px for project cards; 10px for CTA buttons.
- Border: a subtle 1px inset border, which gives the card a precise edge without a strong box outline.
- Shadow or elevation: low, soft separation. Avoid a large floating-card shadow.
- Internal spacing: roughly 18px around card content on desktop, with tighter horizontal padding at narrow widths.
- Labs cards combine category, counter, title, a short explanation, focus and approach labels, a compact evidence artifact, and a secondary link. The small artifact is part of the card's information design, not a decorative image.

### Inputs and Interactive Controls

- No text form was present on the inspected homepage.
- The evidence selector uses real radio inputs inside labeled tabs, grouped as Product / Growbook, Gebruik / UserTesting, and Operatie / Enterprise IT.
- Selecting a radio changes the visible evidence panel. The selected tab is marked by a pink 3px top inset rule and brighter text in the dark evidence band.
- The theme control offers separate Licht and Donker choices in the mobile menu. On desktop it is a 44px icon button with an accessible name and pressed state.

### Navigation

- Structure: a centered, fixed pill around the wordmark, three primary links, and a theme control. The wordmark includes a three-stroke wave mark.
- Background treatment: translucent paper or charcoal, a subtle 1px border, inset highlight, soft layered shadow, and full pill radius on desktop.
- Link style: plain text, 44px high links, 700 weight for the current page, and a short accent underline under the active desktop link.
- Sticky or scroll behavior: the header is fixed and can slide above the viewport while scrolling down. It is visible at the page top. The transform transition is 0.48 seconds with an eased curve.
- Mobile: at 620px and below, replace the desktop links with a 44px menu button. The pill becomes nearly full-width with a 24.8px radius and the open panel expands below it. The panel contains the three links and explicit light and dark theme buttons.

### Image Treatment

- No stock photography or raster illustration was observed on the homepage.
- The hero uses a decorative, aria-hidden SVG wave field with five long traces in a 1200 by 220 viewBox. The center trace is dusty pink, with gray traces around it. SVG path data morphs on an 8-second infinite loop.
- Project cards use small, structured diagrams and artifact-like information blocks. Keep them diagrammatic and readable rather than replacing them with generic screenshots.
- Keep corners consistent with the 10px CTA and 16px card radii; the navigation is the full-pill exception.

### Distinctive Components

- Situations ledger: a large heading beside three numbered rows, each pairing a concrete situation with an approach. Fine rules separate rows; the index and two text columns give the list an operational feel.
- Evidence band: a full-width deep-wine section with three radio-style evidence tabs and a changing content panel. The panel pairs a short explanation with a compact evidence list.
- Labs project cards: four numbered project cards with explicit status, focus, approach, and embedded evidence artifact.
- Hero signal: a wide, slowly morphing five-trace SVG under the CTA row, used as a quiet signature graphic rather than a loud illustration.

## 5. Layout Principles

### Spacing System

- Base unit: 4px, matching the root CSS `--spacing: .25rem` value.
- Repeated spacing values: use a 4px rhythm, with common practical steps around 8px, 12px, 16px, 24px, 32px, 48px, and 72px. This list is an implementation inference from the observed measurements, not a separate named token scale.
- Keep section spacing generous. The desktop hero uses about 54px above and below its main content; the narrow-phone layout deliberately tightens this spacing.

### Grid & Container

- Grid logic: centered max-width page container; editorial two-column situations ledger; three-column evidence tabs and evidence content on wider screens; four project columns on wide desktop.
- Max content width: 1360px, measured at 1440px with 40px outer margins.
- Tablet page width: 720px at a 768px viewport, leaving 24px gutters.
- Mobile page width: 354px at 390px and 324px at 360px, leaving 18px gutters.
- Section spacing: distinguish major sections with vertical room and full-width background shifts, not a stack of bordered boxes.

### Whitespace Philosophy

- Whitespace philosophy: let the claim breathe, then compress the proof into labeled rows and cards.
- Alignment tendencies: centered hero; left-aligned section headings and evidence; project grid aligned to the same page container.
- Content width behavior: keep explanatory copy narrow, while evidence bands and project collections can span the full container.

### Border Radius Scale

- Micro: 0px or a small line treatment for rules and underlines.
- Standard: 10px for primary CTA; 16px for project surfaces.
- Large: around 25px for the expanded mobile navigation pill.
- Pill: 999px for desktop navigation and fully rounded small controls.

## 6. Depth & Elevation

| Level | Treatment | Use |
| --- | --- | --- |
| Flat | Matte section background with no shadow | Main page regions and text-led sections |
| Ring | Thin inset rule or visible outline | Project cards, selected tabs, and keyboard focus |
| Card | Soft 1px inset border plus a low-opacity 6px / 18px shadow | Labs project cards |
| Focus | 2px outline with 3px offset on key navigation and footer links | Keyboard navigation |

### Depth Principles

- Surface hierarchy: page ground first, wine evidence band second, cards and floating navigation as the only lifted surfaces.
- Shadow language: short and diffuse. The edge should remain more legible than the shadow.
- Blur, glass, or overlay behavior: translucency and a small inset highlight belong to the navigation pill; other regions stay matte.
- When depth is used versus avoided: use depth for a clickable navigation capsule and discrete project cards. Do not shadow every section.

## 7. Do's and Don'ts

### Do

- Keep the warm paper, wine, and dusty-pink relationship in both theme modes.
- Give the hero one clear sentence and a concise pair of actions.
- Use measured, concrete problem and evidence language inside ledgers and cards.
- Preserve the serif italic accent as a small contrast against sans-serif typography.
- Maintain strong page gutters, a visible 44px mobile menu target, and useful focus indicators.

### Don't

- Do not add a bright blue or multicolor accent palette.
- Do not turn every content block into a rounded card; several sections are intentionally flat.
- Do not use large dark shadows, glass treatment on every surface, or decorative stock imagery.
- Do not use italics for long copy or make every heading oversized.
- Do not remove status labels, counters, or small evidence artifacts from the project cards; they carry the proof structure.

## 8. Responsive Behavior

Viewport inspection was performed at 1440px, 768px, 390px, and 360px. The breakpoint values below were also read from the live stylesheet.

### Breakpoints

| Name | Width | Key Changes |
| --- | --- | --- |
| Narrow phone | 360px and below | Hero type and spacing compress; title measure is capped to about 11ch; the wave field is shortened |
| Mobile | 620px and below | Page gutters become 18px; desktop nav becomes a full-width expandable pill with menu button; hero and evidence spacing tighten |
| Tablet | 621px to 900px | Page gutters are 24px; desktop navigation remains; situations stack below 1100px; Labs cards become a single column below 859px |
| Desktop | 901px and above | Wide editorial spacing returns; at 1392px and above, Labs projects use four columns |

Additional observed stylesheet thresholds: the situations ledger changes to one column at 1100px; evidence tabs and their content restructure at 700px; the Labs card layout is single-column below 859px. At 700px to 859px the cards use a more horizontal internal arrangement.

### Touch Targets

- Keep the mobile navigation button and desktop theme icon at 44px minimum size.
- Mobile navigation rows are about 48px high; primary CTA height is about 51px.
- Keep the evidence radio label area wide enough to work as a touch target, not just as a tiny radio circle.

### Collapsing Strategy

- Desktop behavior: hero and page container remain centered; situations use a heading column and a two-part evidence ledger; projects sit in up to four columns on wide screens.
- Tablet behavior: situations stack their heading above the rows; project cards reflow into one column as width drops below 859px.
- Mobile behavior: replace top navigation with a menu control; preserve three evidence choices across the width; stack the evidence panel and wrap its evidence list.
- Breakpoint-driven component changes: at 700px the evidence tabs become compact stacked labels and the details list wraps; at 620px the nav changes; at 360px the hero uses the narrow display size and less vertical spacing.
- Touch target and spacing adjustments: retain 44px controls while reducing gutters and section spacing; avoid shrinking controls to make the layout fit.

## 9. Agent Prompt Guide

### Quick Color Reference

- Primary CTA: light `#762F3D`, dark `#8F3D4E`. Accent pink: `#D7A3AD`.
- Background: light `#E8E2D9`, dark `#1C1618`.
- Heading text: light `#2D2023`, dark `#F3F0EA` for display headings.
- Body text: light `#2D2023`, dark `#EBE5DC`.
- Border or ring: light `#D4C9BD`, dark `#373131`; selected evidence rule `#D7A3AD`.
- Accent: wine and dusty pink, with deep-wine evidence bands in both modes.

### Quick Summary

Wavesweb is a warm editorial studio site with a measured, evidence-first layout.
Use the paper, wine, and dusty-pink palette with separate light and dark tokens.
Set large, tightly tracked sans-serif headlines and reserve Georgia italics for small emphasis.
Keep the navigation in a floating pill on desktop and an expandable, full-width pill on mobile.
Use structured ledgers, selectable evidence panels, and evidence-rich Labs cards.
Use whitespace and section backgrounds for hierarchy; keep borders and shadows restrained.

### Example Component Prompts

- Hero: Center a short, two-line Aptos display headline at a fluid 62px to 70px desktop scale, with tight leading and one Georgia italic word. Keep the supporting copy near 46ch, place a filled wine CTA beside a transparent underlined action, then add a low-contrast five-line wave SVG.
- Card: Build a 16px-radius Labs card with a fine inset border, faint 6px / 18px shadow, uppercase status, 01 / 04 index, 22px title, concise explanation, compact evidence artifact, and a text link. Use four columns on wide screens and one column below 859px.
- Navigation: Make a centered fixed pill with a subtle translucent surface, one-pixel border, inset highlight, soft layered shadow, wordmark wave, three 44px links, and theme control. Below 620px, replace links with a 44px menu toggle and an expanding panel.
- Button: Use a 10px-radius filled CTA with 16px bold Aptos text, 51px height, and 18px horizontal padding. Keep hover color shift and shadow transition near 0.18s; use a transparent underlined style for the secondary action.

### Ready-to-Use Prompt

Create a Wavesweb-style homepage in a warm editorial design language. Use the two-theme paper and wine palette, Aptos with a small Georgia italic accent, a centered display hero, a floating navigation pill, a numbered situations ledger, a selectable evidence band, and restrained evidence-rich project cards. Keep a 1360px max-width container with 40px desktop gutters, 24px tablet gutters, and 18px mobile gutters. Add the compact menu below 620px and maintain accessible 44px controls. Use quiet transitions, soft borders, minimal shadows, and direct Dutch copy that names a real situation, approach, or evidence source.

### Iteration Guide

1. Check the page in both theme modes and preserve each mode's background, surface, and accent roles.
2. Compare desktop and phone composition, especially the hero measure, navigation menu, evidence tabs, and card layout.
3. Keep emphasis selective: one italic phrase, one primary action, and clear labels before adding extra decoration.

## Optional Appendix: Interaction Patterns

- Scroll behavior: the fixed header can slide out of view as the page scrolls down and is shown again at the page top. The 0.48-second easing keeps the motion soft.
- Hover behavior: primary CTA changes to the deeper wine in light mode and brighter berry in dark mode, with a slightly stronger shadow. Labs cards shift from `#F7F1E7` to `#F3F0EA` in light mode and from `#251E20` to `#2B2326` in dark mode. Navigation links change to the deeper theme accent.
- Click behavior: theme control changes the root theme and corresponding colors. Selecting a Product, Gebruik, or Operatie radio switches the visible evidence panel. The mobile menu expands and collapses below the fixed pill.
- Animation tone: the decorative hero signal morphs its SVG paths over 8 seconds and repeats indefinitely. The site uses short 0.18 to 0.24 second control and surface transitions. The navigation hide/show transition is 0.48 seconds.

## Optional Appendix: Content & Messaging Patterns

- Headline pattern: a plain statement with a purposeful break and one italic phrase, such as “Van complex vraagstuk / naar werkbare verandering.”
- CTA language: direct action phrases such as “Neem contact op” and “Zie hoe ik werk.”
- Trust signal pattern: labeled situations, approach descriptions, dates, counts, status, and live project links instead of generic claims.
- Voice and tone: first-person, direct Dutch, curious and practical. Copy explains what is being examined, where the friction lies, and what will change.

## Optional Appendix: Observed Pages

- [Wavesweb homepage](https://wavesweb.nl/): only page inspected; it supplied the palette, typography, navigation, responsive rules, interaction patterns, project cards, and content voice.

## Optional Appendix: Evidence Notes

- Observed in the live homepage: two theme modes; a fixed navigation pill; a 1360px desktop content width; a 44.64px measured desktop section heading; a 70.16px measured desktop hero heading; 10px CTA radius; 16px card radius; a mobile navigation breakpoint at 620px; a narrow-phone adjustment at 360px; a selector that changes evidence panels; and an 8-second SVG path animation.
- Inferred from the live layout: the practical 4px spacing rhythm and the recommendation to use the observed patterns as a reusable system on pages that were not inspected.
- Not inspected: linked internal routes, form pages, and every keyboard interaction. Focus-visible declarations were read from the live stylesheet, while the interactive tests covered the theme control, evidence selector, mobile navigation, hover CTA, and card hover.
