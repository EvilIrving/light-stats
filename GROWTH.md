# Growth Context

*Last updated: 2026-06-21*

## Product
- **Name:** Light Stats
- **One-liner:** Native macOS menu bar monitor with pressure scoring and privacy-first diagnostics.
- **What it does:** Light Stats is a native macOS menu bar system monitor for CPU, GPU, memory pressure, disk, disk I/O, network, proxy state, exit node, battery, temperature, fan, processes, AI subscription usage, window controls, scroll behavior, cleaning mode, self-update, and a 0-100 health score. It keeps live pressure signals visible in the menu bar and opens a detailed popover for context. It is designed as a lightweight status instrument, not a full Activity Monitor replacement.
- **Category:** macOS menu bar system monitor

## Platform & distribution
- **Platform / requirements:** macOS 14+, Swift 5.9+, Xcode 16+ recommended for development.
- **How it ships / installs:** GitHub Releases DMG.
- **Updates:** Built-in self-update checks GitHub Releases, downloads the DMG, verifies codesign, notarization, and Team ID, then replaces the running app.
- **Repo:** https://github.com/EvilIrving/light-stats
- **Site:** https://evilirving.github.io/light-stats/

## Pricing model
- Free and open source under the MIT License.

## Audience
- **Who it's for:** macOS power users, developers, local AI coding-agent users, and system administrators who want fast visibility into whether their Mac is under pressure.
- **Why they reach for it:** They want live system status without keeping Activity Monitor open, and they care about local-first tooling, proxy/network truth, memory pressure, AI CLI usage, and menu bar density.

## Differentiators (ranked, all true)
1. **Pressure score instead of raw capacity alerts:** The 0-100 health score focuses on responsiveness pressure using CPU, memory pressure and swap, load, temperature, GPU, and power or disk I/O.
2. **Network truth beyond throughput:** Detects local proxy configuration and tunnel interfaces without external requests, with optional exit-node lookup for public IP, ASN, ISP, and location.
3. **AI CLI usage in the system monitor:** Displays Claude Code, Codex, and Gemini subscription usage when enabled.
4. **Native macOS implementation:** SwiftUI and AppKit, menu bar agent, no third-party runtime dependencies.
5. **Privacy-forward defaults:** No remote telemetry. Exit-node detection and AI usage monitoring are disabled by default. Update checks contact GitHub Releases.
6. **Extra Mac utility features:** Cleaning mode, window controls, titlebar gestures, hotkeys, and scroll-direction controls sit next to system monitoring.

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
- Latest GitHub release observed: v1.5.2.
- GitHub Actions build and release workflows exist.
- Screenshots exist for overview and cleanup panels.
- No real usage, download, star, testimonial, or benchmark numbers captured yet.

## Links
- **Social handles / accounts:**
- **Press / contact:**
