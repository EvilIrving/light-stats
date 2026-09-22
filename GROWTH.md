# Growth Context

*Last updated: 2026-09-13*

## Product
- **Name:** Light Stats
- **One-liner:** Native macOS menu bar instrument for live system pressure, with optional developer tools and four visual themes.
- **What it does:** Light Stats keeps a 0-100 pressure score and live CPU, GPU, memory, disk, network, battery, thermal, process, and short-term trend signals in the menu bar and popover. Optional tools add AI usage for 15 providers, proxy and exit-node context, Finder right-click actions and file templates (including Word / Excel / PowerPoint and user templates), native-first window placement, a default input source, hardware display brightness, Find My Mouse and a presentation pointer with a user-recorded trigger, mouse and trackpad scroll controls, display keep-awake, keyboard cleaning mode, launch at login, and verified self-update (Stable or Beta channel). The popover and related product surfaces support four themes (Classic, Golden Hour, Amber, Ink Night), with Ink Night selected on a clean install; Settings stays a system-white tool panel. A local diagnostic journal is always on and user-exportable; a 48-hour performance recording is a separate opt-in. It is a compact status instrument for developers and power users, not a full Activity Monitor replacement.
- **Category:** macOS menu bar system and developer-workflow monitor

## Platform & distribution
- **Platform / requirements:** macOS 14+, Apple Silicon only. Swift 5.9+, Xcode 16+ recommended for development. Intel Macs are not supported.
- **How it ships / installs:** Signed and notarized DMG from `https://download.onecat.dev/stable` (GitHub Releases as a secondary source).
- **Updates:** Manual checks and opt-in automatic checks read the Cloudflare R2 channel marker, falling back to GitHub Releases. Channel choice: Stable (final only) or Beta (includes prereleases). Installation downloads the DMG, verifies SHA-256 (R2), codesign, notarization, and Team ID, then replaces the running app.
- **Repo:** https://github.com/EvilIrving/light-stats
- **Site:** https://evilirving.github.io/light-stats/

## Pricing model
- Free and open source under the MIT License.

## Audience
- **Who it's for:** macOS power users and developers, especially people who run AI coding agents, work through terminals and Finder, or need fast visibility into whether their Mac is under pressure.
- **Why they reach for it:** They want to know whether the Mac is actually struggling without keeping Activity Monitor open, while keeping AI limits, proxy and exit-node truth, and frequent Finder actions close at hand. Some also want a calm instrument look (film/noir mesh) rather than a generic utility chrome.

## Differentiators (ranked, all true)
1. **Pressure score instead of raw capacity alerts:** The 0-100 health score focuses on responsiveness pressure using CPU, memory pressure and swap, load, temperature, GPU, and power or disk I/O.
2. **Network truth beyond throughput:** Detects local proxy configuration and tunnel interfaces without external requests, with optional exit-node lookup for public IP, ASN, ISP, and location.
3. **Developer context in one instrument:** Displays AI subscription usage for 15 providers (quota windows collapse to the tightest one, balances stay bar-free), and adds an opt-in Finder menu for terminal, type-aware and user file templates, copy, move, and open-with workflows.
4. **Native macOS implementation:** SwiftUI and AppKit, menu bar agent and FinderSync extension, with template-tinted SVG icons in-bundle.
5. **Local-first defaults:** Exit-node lookup, AI usage requests, Claude/Codex window warmup, automatic update checks, and the Beta update channel stay off until you enable them. The diagnostic journal is written locally with redaction; a 48-hour performance recording is a separate opt-in.
6. **Opt-in Mac utilities:** Window placement, default input source, display brightness, Find My Mouse and its presentation pointer, mouse and trackpad scroll controls, display keep-awake, cleaning mode, and Finder actions remain dormant until the user enables them.
7. **Selectable instrument chrome:** Four themes (Classic, Golden Hour, Amber, Ink Night) on product surfaces; the three dynamic themes provide grain and light-dynamics controls; Settings remains a white tool panel.

## Competitors / alternatives
- Do not use public competitor comparisons in launch copy, README copy, listings, or social posts.
- If users ask directly, answer factually and avoid naming specific competitors unless the user names them first.

## Channels
- **Where this audience is:** GitHub, Hacker News Show HN, Product Hunt, r/macapps, r/macOS, r/MacOSApps, MacUpdate-style app directories, open-source Mac app lists.
- **Languages to publish in:** English, Simplified Chinese, Japanese, Korean.

## Voice
- **Tone:** Developer-to-developer, plain, technical, precise, privacy-aware.
- **Words to use / avoid:** Use concrete system signals, local-first language, verified privacy claims, and screenshots. Avoid SaaS marketing language, inflated numbers, fake social proof, and vague claims like “powerful” or “revolutionary.” Prefer “pressure” over “usage capacity,” “opt-in” over “seamless.”

## Proof points (REAL only)
- Public GitHub repository.
- MIT License file exists in the repository.
- Latest stable GitHub release observed on 2026-09-04: v1.9.2.
- Latest tagged prerelease observed on 2026-09-04: v1.9.2-beta.7.
- Unreleased working-tree changes observed on 2026-09-14: AI usage covers 15 providers via a compile-time registry, Overview quota rows collapse to the tightest window with tap-to-expand, balance-only providers sink to the bottom without bars, Cursor's primary window follows auto percent; Apple Silicon only (`ARCHS = arm64`); Finder menu adds Word/Excel/PowerPoint blanks and user file templates, move/copy to favorites, and hide/show; window management prefers macOS' own tiling then falls back, surfaces system edge-drag, and uses a traffic-light titlebar heuristic with Fn pointer snap; optional default input source after app switch; diagnostic journal always on with user-exportable ZIP, performance recording kept separate.
- GitHub Actions build and release workflows exist.
- Screenshots under `website/screenshots/{classic,golden-hour,amber,ink-night}/` (overview + cleanup each, PNG).
- No adoption, testimonial, or benchmark claim is approved for marketing copy; any public count must be rechecked immediately before use.

## Links
- **Social handles / accounts:**
- **Press / contact:**
