# Growth Context

*Last updated: 2026-07-10*

## Product
- **Name:** Light Stats
- **One-liner:** Native macOS menu bar instrument for live system pressure and developer workflow context.
- **What it does:** Light Stats keeps a 0-100 pressure score and live CPU, GPU, memory, disk, network, battery, thermal, process, and short-term trend signals in the menu bar and popover. Optional tools add Claude Code, Codex, and Gemini usage, proxy and exit-node context, Finder right-click actions and file templates, window placement, scroll reversal, display keep-awake, keyboard cleaning mode, launch at login, and verified self-update. It is a compact status instrument for developers and power users, not a full Activity Monitor replacement.
- **Category:** macOS menu bar system and developer-workflow monitor

## Platform & distribution
- **Platform / requirements:** macOS 14+, Swift 5.9+, Xcode 16+ recommended for development.
- **How it ships / installs:** GitHub Releases DMG.
- **Updates:** Manual checks and opt-in automatic checks use GitHub Releases. Installation downloads the DMG, verifies codesign, notarization, and Team ID, then replaces the running app.
- **Repo:** https://github.com/EvilIrving/light-stats
- **Site:** https://evilirving.github.io/light-stats/

## Pricing model
- Free and open source under the MIT License.

## Audience
- **Who it's for:** macOS power users and developers, especially people who run AI coding agents, work through terminals and Finder, or need fast visibility into whether their Mac is under pressure.
- **Why they reach for it:** They want to know whether the Mac is actually struggling without keeping Activity Monitor open, while keeping AI limits, proxy and exit-node truth, and frequent Finder actions close at hand.

## Differentiators (ranked, all true)
1. **Pressure score instead of raw capacity alerts:** The 0-100 health score focuses on responsiveness pressure using CPU, memory pressure and swap, load, temperature, GPU, and power or disk I/O.
2. **Network truth beyond throughput:** Detects local proxy configuration and tunnel interfaces without external requests, with optional exit-node lookup for public IP, ASN, ISP, and location.
3. **Developer context in one instrument:** Displays Claude Code, Codex, and Gemini subscription usage, and adds an opt-in Finder menu for terminal, file-template, copy, move, and open-with workflows.
4. **Native macOS implementation:** SwiftUI and AppKit, menu bar agent and FinderSync extension, no third-party runtime dependencies.
5. **Privacy-forward defaults:** No remote telemetry. Exit-node lookup, AI usage requests, Claude/Codex window warmup, and automatic update checks are all disabled by default, so a clean install makes no outbound request.
6. **Opt-in Mac utilities:** Window placement, scroll reversal, display keep-awake, cleaning mode, and Finder actions remain dormant until the user enables them.

## Competitors / alternatives
- Do not use public competitor comparisons in launch copy, README copy, listings, or social posts.
- If users ask directly, answer factually and avoid naming specific competitors unless the user names them first.

## Channels
- **Where this audience is:** GitHub, Hacker News Show HN, Product Hunt, r/macapps, r/macOS, r/MacOSApps, MacUpdate-style app directories, open-source Mac app lists.
- **Languages to publish in:** English, Simplified Chinese, Japanese, Korean.

## Voice
- **Tone:** Developer-to-developer, plain, technical, precise, privacy-aware.
- **Words to use / avoid:** Use concrete system signals, local-first language, verified privacy claims, and screenshots. Avoid SaaS marketing language, inflated numbers, fake social proof, and vague claims like “powerful” or “revolutionary.”

## Proof points (REAL only)
- Public GitHub repository.
- MIT License file exists in the repository.
- Latest stable GitHub release observed: v1.8.0.
- Latest prerelease observed: v1.9.0-beta.6.
- GitHub Actions build and release workflows exist.
- Screenshots exist for overview and cleanup panels.
- No adoption, testimonial, or benchmark claim is approved for marketing copy; any public count must be rechecked immediately before use.

## Links
- **Social handles / accounts:**
- **Press / contact:**
