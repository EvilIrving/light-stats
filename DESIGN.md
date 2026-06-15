# Design

## Aesthetic lane

A precision instrument / spec-sheet readout. Strict, visible structure as voice (Swiss / tech-spec), left-aligned, with a tabular monospace carrying every number and label. Not a centered SaaS stack, not editorial. Reference points: a well-labeled hardware spec sheet, an instrument panel, Apple's own restraint reworked around live data.

## Visual Theme

Light mode, deliberately. **Physical scene:** a developer at a well-lit desk glances at this page between commits to decide whether to install. They want a readout, not an experience. Cool-tinted near-white ground, surfaces a shade brighter, depth through hairline rules and low shadow rather than heavy cards. A single live-green accent signals "measured / healthy" the way the app itself does.

## Color Palette

OKLCH. Tinted neutrals (cool, hue ~255). Strategy: restrained neutrals + one load-bearing signal color (green = live/healthy, echoing the app), blue reserved for actions/links, purple as a rare data highlight. Never `#000` / `#fff`.

| Role | OKLCH | Note |
|------|-------|------|
| Background | `oklch(98.5% 0.004 255)` | cool near-white |
| Surface | `oklch(99.6% 0.002 255)` | panels, screenshot frame |
| Sunken | `oklch(96.5% 0.005 255)` | readout grid wells |
| Ink (primary) | `oklch(22% 0.012 260)` | near-black, cool |
| Muted | `oklch(52% 0.016 260)` | secondary text |
| Faint | `oklch(68% 0.012 260)` | labels, meta |
| Line | `oklch(91% 0.006 260)` | hairline rules / dividers |
| Accent — live | `oklch(70% 0.16 150)` | green signal, ≤15% of surface |
| Accent — strong | `oklch(62% 0.15 150)` | green on light, text-safe |
| Action | `oklch(56% 0.17 250)` | links, primary button |
| Data — memory | `oklch(56% 0.18 300)` | purple, rare highlight only |

## Typography

- Sans (prose, headings): `-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", sans-serif` — native voice for a Mac app, chosen not defaulted.
- Mono (all data, labels, spec rows, eyebrows): `"JetBrains Mono", "SF Mono", Menlo, monospace`, loaded from Google Fonts, `font-feature-settings: "tnum" 1` for tabular figures.
- Eyebrow labels: mono, uppercase, `0.72rem`, letter-spacing `0.12em`, faint.
- Scale: fluid `clamp()` headings, ≥1.25 ratio. Display `clamp(2rem, 5vw, 3.25rem)`, section `1.5rem`, sub `1.125rem`, body `0.9375rem` (15px), meta `0.8125rem`.
- Body line length capped at ~68ch. Line-height 1.6 body, 1.2 headings.

## Layout

- Page max-width `960px`; reading column for prose `~680px`. Generous fluid vertical rhythm with `clamp()`, tight groupings inside the readout grid for contrast.
- **Hero is asymmetric:** statement left, real popover screenshot framed right; stacks on narrow viewports.
- **Readout grid:** the tracked metrics are a labeled spec grid (mono), grouped by domain (Compute / Memory / Storage / Network / Power / Intelligence / Health), `grid-template-columns: repeat(auto-fit, minmax(220px, 1fr))`. Hairline rules, no nested cards.
- Tab bar (Overview / Privacy / Support): inline segmented control, system-standard.
- Screenshots sit in a single rounded surface frame with low shadow; never a colored placeholder block.

## Motion

- One restrained page-load reveal: hero fades/rises with a short stagger (≤320ms, ease-out-quint). No scattered micro-interactions.
- Tab transitions: quick crossfade (120ms ease-out), no slide.
- Hover: 150ms color only. Never animate layout properties; expand/collapse via `grid-template-rows`.
