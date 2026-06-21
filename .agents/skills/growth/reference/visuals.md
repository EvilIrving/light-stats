# visuals

Produce the images and clips that sell an indie/OSS project: real screenshots, a demo GIF (or terminal cast for a CLI), launch/directory gallery shots, an OG/social-preview image, and icon polish.

Read `GROWTH.md` for the product, platform, and brand. The cardinal rule for any UI product: **capture real screenshots, never AI-generate the interface.** Image models hallucinate UI. The actual project, running, is the asset.

For installer/DMG background artwork specifically, use the **dmg-background** skill. For deep visual craft on a landing page, hand off to **impeccable**.

## Priority order

1. **The demo asset** (highest leverage). For a GUI: a 5–15s GIF showing the tool in action. For a CLI: a clean terminal recording (asciinema/agg) or a sharp code+output sample. For a library: a minimal, real usage snippet.
2. **Primary screenshot** — the main UI / output with real data.
3. **Secondary screenshots** — the features that differentiate (from `GROWTH.md`).
4. **OG image** (1200×630) for link previews.
5. **Icon** review (polish only if needed).

## Capturing screenshots

- Capture on a high-DPI display at 2x. Don't upscale low-res shots.
- Show a clean environment and genuine, plausible data, not zeroed-out or maxed-out values.
- Take light-mode and dark-mode variants where the UI supports both.
- Crop tightly to the thing you're showing; a full 5K screenshot buries it.
- macOS tooling: `⌘⇧4`+space for a window with shadow, or CleanShot X / Shottr for framing; `screencapture` CLI for scripted shots. Use the platform's equivalent elsewhere.

## Demo GIF / video / cast

- Record with the OS screen recorder (`⌘⇧5` on macOS) or CleanShot; for terminals use asciinema → agg for GIF.
- Keep it short (5–15s) and loop cleanly. Trim dead frames.
- Export GIF for README/Reddit (autoplays inline) and MP4 for PH/social (smaller, sharper).
- Show motion only a live tool can convey: real-time updates, the key interaction, the novel capability from `GROWTH.md`.
- Keep file size sane: a README GIF over ~5 MB is too heavy; drop to 12–15 fps and resize before reducing colors.

## Gallery shots (Product Hunt / directories)

- PH gallery: 1270×760, up to 6 images. First image is the hook (the GIF's key frame or the UI in context).
- Annotate sparingly: one label or arrow to point at the differentiating feature. Don't clutter.
- Show the product in a real context (its actual environment), not floating on an abstract gradient.

## OG / social preview image

- 1200×630, used when the repo or site URL is shared.
- Compose: icon + name + one-line tagline + a real screenshot. Minimal, centered text (edges get cropped).
- This is the one place a designed composite (not a raw screenshot) is appropriate. Use the project's brand colors; keep it consistent with the icon.
- Wire it in with the right meta tags (`og:image`, `og:image:width/height`, `twitter:card=summary_large_image`); `web` covers placement.

## Optimization

- Serve **WebP** (or PNG for screenshots needing crisp text) sized to display dimensions. Don't ship a 5K image into a small README slot.
- Quality ~80 for photos, near-lossless for UI screenshots (text must stay sharp).
- Quick commands: `cwebp -q 80 in.png -o out.webp`; `sips -Z 1280 in.png --out out.png` (macOS resize).
- Add real `alt` text everywhere for accessibility and SEO.

## Don'ts

- Don't AI-generate the UI, fake data, or mock up unshipped features.
- Don't use stock "person at laptop" photos. Show the actual project.
- Don't ship blurry, upscaled, or stale screenshots; refresh when the UI changes.

## Deliverable

A shot list mapped to where each asset is used (README, Reddit, PH, OG), exact dimensions per slot, and capture/export settings. If producing assets directly, capture from the real running project (build it first if needed), then optimize and place them.
