# Design

## Visual Theme

Light mode. macOS-native feel: SF Pro through system font stack, clean hierarchy, subtle depth through shadow rather than border. The page is an extension of the macOS environment — familiar, unintrusive, fast.

**Physical scene:** A developer at their desk in a well-lit room, glancing at this page between tasks. They want information, not an experience.

## Color Palette

Restrained strategy. One accent, ≤10% of surface.

- Background: `#f5f5f7` — Apple light gray, slightly warm
- Surface (cards, active tabs): `#ffffff` — pure white on tinted ground
- Text primary: `#1d1d1f` — Apple near-black
- Text secondary: `#86868b` — Apple system gray
- Accent: `#0071e3` — Apple system blue
- Border / divider: `#e5e5ea`

## Typography

- Sans: `-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", sans-serif`
- Mono (data/metrics): `"SF Mono", Menlo, Monaco, monospace`
- Scale: headings at 1.25rem / 1.5rem / 1.875rem; body at 0.9375rem (15px)
- Line-height: 1.6 for body, 1.25 for headings

## Layout

- Single centered column, max-width 640px — focused reading width
- Generous vertical rhythm: sections separated by 2–3× body spacing
- Tab bar: inline pill group, system-standard segmented control pattern
- No cards where prose suffices

## Motion

- Tab transitions: quick crossfade (120ms ease-out), no slide
- No entrance animations — content is the focus
- Hover: 150ms color transitions only
