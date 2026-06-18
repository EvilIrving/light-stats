---
name: dmg-background
description: Generate a ready-to-paste image-model prompt for the Light Stats DMG installer background. Use when the user wants to create or redesign the DMG background image, the install window artwork, or asks for a "dmg background" prompt. Reads real branding from the codebase, applies the impeccable design skill, and bakes in the exact dimensions and reserved-icon zones the build script requires.
---

# DMG Background Prompt Generator

Produce a single, polished prompt the user can paste into an image model to generate
the DMG installer background for **Light Stats**. The output is a PROMPT — do not try
to generate the image yourself.

## Workflow

Do these in order, then emit the prompt.

### 1. Craft the branding copy from real project docs and code (never invent it)

Read the project's actual documentation and code — e.g. `AGENTS.md`, `build.sh`,
`README`, the project site under the repo, settings/about views, localization strings —
and from them write the most fitting marketing & intro copy for the background. You're
not just copy-pasting fields; you're distilling the real product into:

- A **title** = the real app name.
- A short, compelling **subtitle/tagline** that captures what the product is and why
  someone wants it (grounded in what the docs/code actually say it does).
- A few faint **feature chips** drawn from the genuinely user-facing capabilities —
  pick the strongest 6–7, never internal service names.

The app ships **en / zh-Hans / ja**; default the copy to the language the user is
writing in, and offer to localize the title line.

Quote the copy you landed on back to the user in one line ("Copy grounded in: …") with
the sources you drew from, so they can see it's real, not guessed.

### 2. Apply the design skill

Invoke the **impeccable** skill (Skill tool) to shape the visual direction —
hierarchy, palette, typography, restraint, negative space. Fold its guidance into the
prompt's art-direction language. Keep it Apple-native, premium, calm.

### 3. Hard layout constraints (from build.sh — do NOT change these)

These come from the Finder AppleScript in `build.sh`. The image MUST respect them or
the icons will overlap the artwork:

- **Canvas: 1320 × 840 px** (this is the 660 × 420 window at 2× retina). Always 2×.
- Window content maps to 660 × 420 points; icon size is 96.
- **App icon** lands at point `{180, 210}` → ~**27% width, 50% height**.
- **Applications folder** lands at point `{480, 210}` → ~**73% width, 50% height**.
- The two icons are overlaid by Finder ON TOP of the background. So keep those two
  spots **visually calm and low-detail** — soft, near-uniform tone, no busy texture,
  text, logos, or focal graphics that would clash with an icon sitting there. Do NOT
  describe them as "blank circles" or draw empty placeholders; the background should
  read as one continuous, finished image — the calm just lets the real icons pop.
- No window chrome, borders, traffic-light dots, or outer drop shadows.

If the user has edited the positions in `build.sh`, recompute the percentages from the
actual `set position of item …` values before writing the prompt.

### 4. Emit the prompt

Output BOTH a Chinese and an English version of the prompt (English tends to steer
image models more precisely), each as a single copy-pasteable block. Each version must
include, in this spirit:

- Canvas size + 2× retina note.
- Branding block (title = real app name, subtitle = distilled tagline, faint
  dot-separated feature chips from real features).
- A soft, semi-transparent right-pointing arrow (→) in the center band between the two
  icon spots, with a faint "drag to install" caption.
- An instruction to keep the ~27% and ~73% width / 50% height areas calm and low-detail
  (icons overlay there) — phrased as art direction, never as "leave a blank circle".
- The no-chrome / no-border / no-shadow rules.
- Palette + mood words from the impeccable pass.

End by telling the user: once they have the image, hand it back and you'll replace
`packaging/dmg-background.png`, stamp it @2× DPI, and re-align coordinates in `build.sh`
if needed.

## Notes

- The current background lives at `packaging/dmg-background.png` (660 × 420 @1×).
- Keep the center horizontal band empty — that is where both icons land.
- Do not add the version number into the artwork unless the user asks (it dates the image).
