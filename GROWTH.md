# Growth Context

*Last updated: 2026-08-18*

## Product
- **Name:** Light Stats
- **One-liner:** Native macOS menu bar instrument for live system pressure, with optional developer tools and four visual themes.
- **What it does:** Light Stats keeps a 0-100 pressure score and live CPU, GPU, memory, disk, network, battery, thermal, process, and short-term trend signals in the menu bar and popover. Optional tools add Claude Code, Codex, and Gemini usage, proxy and exit-node context, Finder right-click actions and file templates, window placement, mouse and trackpad scroll controls, display keep-awake, keyboard cleaning mode, launch at login, and verified self-update (Stable or Beta channel). The popover and related product surfaces support four themes (Classic, Golden Hour, Amber, Ink Night), with Ink Night selected on a clean install; Settings stays a system-white tool panel. Local privacy-aware diagnostic logging is optional. It is a compact status instrument for developers and power users, not a full Activity Monitor replacement.
- **Category:** macOS menu bar system and developer-workflow monitor

## Platform & distribution
- **Platform / requirements:** macOS 14+, Swift 5.9+, Xcode 16+ recommended for development. Apple Silicon is the primary target.
- **How it ships / installs:** GitHub Releases DMG (signed and notarized).
- **Updates:** Manual checks and opt-in automatic checks use GitHub Releases. Channel choice: Stable (final only) or Beta (includes prereleases). Installation downloads the DMG, verifies codesign, notarization, and Team ID, then replaces the running app.
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
3. **Developer context in one instrument:** Displays Claude Code, Codex, and Gemini subscription usage, and adds an opt-in Finder menu for terminal, type-aware file templates, copy, move, and open-with workflows.
4. **Native macOS implementation:** SwiftUI and AppKit, menu bar agent and FinderSync extension, zero third-party runtime dependencies (including template-tinted SVG icons in-bundle).
5. **Privacy-forward defaults:** No remote telemetry. Exit-node lookup, AI usage requests, Claude/Codex window warmup, automatic update checks, and the Beta update channel are all disabled by default, so a clean install makes no outbound request. Diagnostic logs (default Full, switchable to Errors or Off) stay local with redaction and are never uploaded.
6. **Opt-in Mac utilities:** Window placement, mouse and trackpad scroll controls, display keep-awake, cleaning mode, and Finder actions remain dormant until the user enables them.
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
- Latest stable GitHub release observed on 2026-08-18: v1.9.0.
- Latest tagged prerelease observed on 2026-08-18: v1.9.1-beta.2.
- Unreleased working-tree changes observed on 2026-08-18: visible theme lineup is Classic / Golden Hour / Amber / Ink Night (raw keys glass/film/bar/noir), Ink Night remains the clean-install default, Bento and Ash Veil are removed, the popover uses one instrument layout, Settings has six direct destinations, Keep Awake moved to the popover toolbar, input controls add optional trackpad/Magic Mouse reversal and fixed-line wheel scrolling, and maximize/center gain global shortcuts.
- GitHub Actions build and release workflows exist.
- Screenshots under `docs/screenshots/{classic,golden-hour,amber,ink-night}/` (overview + cleanup each, PNG).
- No adoption, testimonial, or benchmark claim is approved for marketing copy; any public count must be rechecked immediately before use.

## Links
- **Social handles / accounts:**
- **Press / contact:**
