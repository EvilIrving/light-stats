# Light Stats

[![Build](https://github.com/EvilIrving/light-stats/actions/workflows/build.yml/badge.svg)](https://github.com/EvilIrving/light-stats/actions/workflows/build.yml)
[![Release](https://github.com/EvilIrving/light-stats/actions/workflows/release.yml/badge.svg)](https://github.com/EvilIrving/light-stats/actions/workflows/release.yml)

Light Stats is a native macOS menu bar instrument that shows whether your Mac is **under pressure right now**, not just how full it is. A 0-100 health score and live CPU, GPU, and memory-pressure signals sit in the menu bar; optional developer tools add AI CLI usage, proxy and exit-node context, Finder actions, window placement, a default input source, display brightness, and display keep-awake. The popover can wear one of four visual themes, with Ink Night selected on a clean install, while Settings stays a plain system-white tool panel. Apple Silicon only.

**English** · [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

---

https://github.com/user-attachments/assets/f167325d-e972-42fe-a54f-17a8a7a40834

---

## Screenshots

Ink Night, the clean-install default, shown in Overview and Memory:

| Overview | Memory |
|----------|--------|
| <img src="docs/screenshots/ink-night/popover-overview.png" width="320" alt="Overview panel in the Ink Night theme" /> | <img src="docs/screenshots/ink-night/popover-cleanup.png" width="320" alt="Memory cleanup in the Ink Night theme" /> |

Themes (Overview):

| Classic | Golden Hour | Amber | Ink Night |
|---------|------|-----------|-----------|
| <img src="docs/screenshots/classic/popover-overview.png" width="160" alt="Classic theme" /> | <img src="docs/screenshots/golden-hour/popover-overview.png" width="160" alt="Golden Hour theme" /> | <img src="docs/screenshots/amber/popover-overview.png" width="160" alt="Amber theme" /> | <img src="docs/screenshots/ink-night/popover-overview.png" width="160" alt="Ink Night theme" /> |

---

## Overview

Light Stats keeps the Mac's live pressure signals visible in the menu bar and opens a detailed floating panel when you need more context. It is designed for power users and developers who want quick status checks without keeping Activity Monitor open, plus optional workflow context for AI coding agents, networks, and Finder.

The app uses native macOS APIs for routine sampling and has no third-party runtime dependencies. Monitoring is the read-only core; network requests and persistent system interactions are **off by default**. On a clean install you get only the menu bar readout: no extra icon, no Accessibility prompt, no event tap, no input-source observer, no privileged helper, and no outbound request.

---

## Features

### Menu Bar

- Compact two-line status item with fixed-width values to avoid layout jumping
- Optional items for Logo, CPU, GPU, memory, disk, network, fan, battery, and health
- Upload and download speed display
- Fan indicator with a rotating visual style
- Optional 0-100 health score display

### Overview Panel

- CPU, GPU, memory pressure, swap activity, and load average
- P/E core usage charts and top CPU processes
- Battery status, charge level, cycle count, health, power draw, and temperature when available
- Disk capacity and aggregate disk I/O speed
- Network speed, local proxy state, and optional public exit-node information
- Optional hardware brightness for built-in and external displays (DDC; off by default)
- Temperature, fan, thermal state, and disk status strip
- System health score with dimension-level summary and toggles
- Claude Code, Codex, and Gemini subscription usage when AI monitoring is enabled
- Short-term sparklines for key metrics
- Metric icons use template-tinted SVG outlines (CPU, GPU, memory, disk, network, proxy, temperature, processes)

### Appearance

- Four visual themes for the product surfaces (popover, About, Toast, Update, permission prompts):
  - **Classic**: system instrument readout without card chrome (Liquid Glass on macOS 26+, ordinary system chrome on macOS 15)
  - **Golden Hour**: warm grain and brass instrument ink over an amber and coral light field
  - **Amber**: espresso-black cocktail bar with warm amber light and a cool teal neon accent
  - **Ink Night** (clean-install default): ink-black grain with cool charcoal surfaces
- Golden Hour, Amber, and Ink Night each provide film-grain and five-step light-dynamics controls (Still, Gentle, Natural, Smooth, Lively)
- The Settings window stays system white and does not follow the display theme, so configuration remains a calm tool panel

### Memory Cleanup

- Memory pressure overview and swap warning
- App list sorted by memory usage
- Normal quit and force quit with confirmation
- Expandable child process details
- Layout is the instrument readout: sections, hairlines, and dense rows

### Finder Menu

- Optional FinderSync extension, disabled by default
- Copy selected file paths or names, or copy the current folder path from blank space
- Create text, code, Word, Excel, and PowerPoint files; TXT and Markdown are shown by default, with other types selectable in Settings
- Import existing files as templates, preserving names, formats, and contents; moving or deleting the original does not affect the template
- Move or copy to favorite folders, or choose a destination with Other Location…
- Open favorite folders directly, or open files and the current folder with a chosen terminal or configured app
- Hide or unhide selected items; showing hidden files changes Finder’s global setting and relaunches Finder after confirmation
- Optional cmux window and workspace actions, with individual menu items configurable
- Covers the home folder, external volumes, and added favorite folders; cloud folders remain subject to other Finder extensions and system state
- Extension registration status and Finder relaunch controls in Settings

### Window Management

- A single **Window Management** switch (off by default) turns everything on together: the menu bar window-control icon, the global snap shortcuts, and the titlebar gestures — there are no separate sub-toggles
- Placement prefers macOS' own Window-menu tiling, matched by `AXIdentifier` rather than localized title; only thirds, display moves, and minimize use the app's own geometry
- Menu bar window-control menu with designer-provided action icons
- Left, right, top, and bottom half shortcuts for high-frequency window placement
- `Control + Option + Return` maximizes the current window; `Control + Option + C` centers it
- Additional menu actions for corners, thirds, display movement, maximize, center, restore, and minimize
- Titlebar trackpad swipe: the titlebar band is measured from the window's traffic lights, and a swipe that starts on a control the app itself reacts to is ignored. Hold **Fn** to snap the window under the pointer instead — the way to reach apps that draw their own titlebar
- Settings also surfaces macOS' own drag-to-edge tiling switches (macOS 15+); the edge-drag switch is turned on once the first time window management is enabled
- Turning the switch off removes the icon and stops all window-control event taps immediately; Accessibility permission is requested only when you turn it on

### Default Input Source

- Optional: after switching apps, return to one chosen input source already installed on the Mac
- Off by default; does not need Accessibility permission
- Only corrects drift in a short window after an app becomes active, so a later `Ctrl+Space` is left alone; secure-input fields are never touched
- One global default, not an input-method manager: no per-app rules, no website rules, no indicator

### Scroll Direction Control

- Independent vertical and horizontal scroll-direction reversal
- Traditional mouse wheels are affected by default; trackpads and Magic Mouse can be included explicitly
- Optional mouse-wheel acceleration disablement with a fixed 1 to 10 lines per wheel step
- Step multiplier for fine-tuning reversed wheel movement
- Uses an Accessibility event tap only when reversal or acceleration control is enabled, and rebuilds the tap after wake when needed

### Find My Mouse

- Record the trigger you prefer (left or right modifier, Fn, an F-key, a regular key, or a combination). Double-tap to dim every display and spotlight the pointer; triple-tap to toggle a persistent Presentation Pointer
- The spotlight follows the pointer and fades on any click or key press, with a 4-second safety timeout; triple-tap again to hide Presentation Pointer
- No extra shortcut or separate setting; the listen-only event tap never intercepts or rewrites events, requires Accessibility permission, and is off by default
- Pro features: anyone who launches the app during the current gift period keeps Pro for life. After the first paid release, new users unlock Pro with an activation code (Settings → General). The app stays MIT-licensed; codes are verified offline with Ed25519 and make no network call

### Cleaning Mode

- 60-second keyboard lock for safe keyboard cleaning
- Full-screen translucent overlay with countdown timer
- Mouse-only exit button, while keyboard input is suppressed
- Uses CGEventTap with Accessibility permission

### Keep Awake and Launch at Login

- Popover-toolbar quick toggle for display-sleep prevention, with no Accessibility permission
- Stops immediately when toggled off or when Light Stats exits
- Optional launch at login through the native macOS login-item service

### Auto-Update

- Manual checks and optional automatic checks read the Cloudflare R2 channel marker (`latest-stable.json` / `latest-beta.json`), falling back to GitHub Releases; automatic checks are off by default
- Update channel: **Stable** (final releases only) or **Beta** (also considers prerelease builds such as `v1.9.0-beta.N`)
- SemVer 2.0 comparison understands pre-release identifiers so beta increments and promotion to a final release are ordered correctly
- R2 downloads also verify a SHA-256 sum, then codesign, notarization, and Team ID
- Replaces the running app via a detached script after exit
- Shows a minimal progress window during download and install

### Diagnostics and Performance Recording

- A local structured fault journal is always on (no Off / Errors / Full switch). Continuous metrics are time-throttled; capability and probe records write on first observation and on change
- Settings can export a diagnostic ZIP (system context, hardware probes, 7 days of logs, 50 MB cap). Serial numbers, credentials, usernames, and home paths are redacted; nothing is uploaded
- A separate, off-by-default 48-hour performance recording captures this app's CPU, memory, wakeup, and disk plus companion system load. It never mixes into the diagnostic journal or the exported report

### Network and Proxy

Light Stats detects local proxy configuration from environment variables, system proxy settings, and active tunnel interfaces without sending external requests.

Public exit-node detection is optional. When enabled, it can query a selected geo-IP provider for public IP, location, ASN, and ISP, then cache the result to avoid repeated requests.

### AI Subscription Usage

When enabled, Light Stats reads credentials stored locally by Claude Code, Codex, and Gemini CLIs, then requests current subscription utilization from that provider. AI monitoring is disabled by default and never transmits credentials to another provider or to the Light Stats developer.

Claude Code and Codex each have a separate, off-by-default usage-window warmup switch. After a rolling window resets, warmup sends the minimal headless prompt `ok` through that provider's CLI from a temporary empty directory, discards normal output, and verifies the new window. Gemini does not use warmup.

### Health Score

The health score summarizes CPU, memory pressure and swap, load average, temperature, GPU, and power into a 0-100 score. It focuses on real-time responsiveness pressure rather than slow-moving capacity numbers. On laptops, the power dimension uses battery state; on desktops, it uses disk I/O pressure. Missing or disabled dimensions are reweighted automatically.

---

## Privacy

Light Stats has no remote telemetry. Local system metrics, local proxy detection, process lists, scroll behavior, and window control stay on the Mac.

- A clean install makes no outbound request. Exit-node lookup, AI usage monitoring, Claude/Codex warmup, and automatic update checks are all disabled by default. The Beta update channel is also off by default.
- Exit-node detection contacts the selected geo-IP provider to identify the public IP, location, ASN, and ISP, then caches the result for 60 seconds.
- AI monitoring contacts only the enabled provider's own usage endpoint using credentials already stored by that provider's CLI.
- Optional Claude/Codex warmup sends the headless prompt described above through the selected provider's CLI.
- Manual update checks and opt-in automatic checks contact Cloudflare R2, falling back to GitHub Releases; downloaded updates are verified before installation.
- The diagnostic journal stays on disk under the app's support directory. Exporting a report is user-initiated; performance recordings are a separate opt-in session. Neither is sent to the Light Stats developer.

There is no analytics, crash reporting, advertising, account system, or developer-operated telemetry endpoint. See the full [privacy policy](https://evilirving.github.io/light-stats/#privacy).

---

## Install

Download the latest DMG from [download.onecat.dev/stable](https://download.onecat.dev/stable) (or [GitHub Releases](https://github.com/EvilIrving/light-stats/releases/latest)), open it, and drag Light Stats into Applications. Release builds are signed and notarized; the built-in updater also verifies SHA-256 (R2), codesign, notarization, and Team ID before replacing the app.

Requirements: macOS 14 or later on an Apple Silicon Mac. Intel Macs are not supported.

---

## Settings

- Visual theme (Classic, Golden Hour, Amber, Ink Night), with film grain and light dynamics for the three dynamic themes
- Menu bar item visibility
- Refresh rate: Low (5s), Medium (2s), High (1s)
- Temperature unit: Celsius or Fahrenheit
- Launch at login, automatic update checks, and Stable/Beta update channel; Keep Awake is a popover-toolbar quick toggle
- Export a diagnostic report; optional 48-hour performance recording
- Exit-node detection and provider selection
- AI monitoring for Claude Code, Codex, and Gemini, plus separate Claude/Codex warmup switches
- Vertical and horizontal reversal, optional trackpad and Magic Mouse inclusion, wheel-acceleration control, fixed line count, and step multiplier
- Default input source after switching apps
- Window management (a single toggle for the menu bar icon, snap shortcuts, and titlebar gestures), plus macOS' own edge-tiling switches
- Hardware display brightness (DDC)
- Finder menu, terminal selection, cmux actions, favorite directories, apps, and file templates
- Health score dimension toggles
- Language: English, Simplified Chinese, Japanese, Korean, or system language

The Settings sidebar links directly to **General**, **Monitoring**, **Input Devices**, **Window Management**, **AI Usage**, and **Right-Click Menu**. It is navigation-only and does not show runtime status dots. The window uses a fixed system-white canvas with a light sidebar; only the monitoring popover and related product surfaces follow the selected theme.

---

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full development guide.

### Requirements

- macOS 14+ on Apple Silicon
- Xcode 16 or newer recommended
- Swift 5.9+
- SwiftLint for local linting (`brew install swiftlint`)

### Build

```bash
# Production package → overwrite /Applications/Light Stats.app → open
./script/debug-run.sh

# Release DMG (no install)
./script/build.sh
```

### Quality Checks

```bash
swiftlint lint --strict
./script/validate_localization.sh
```

GitHub Actions runs SwiftLint, localization validation, and XCTest as parallel quality gates. Pull requests and `main` package an unsigned DMG only after those checks pass. Release tags rerun the same gates before signing and notarization; only the verified notarized artifact can be published. GitHub Pages remains an independent docs-only workflow.

### Tests

The XCTest suite lives in `LightStatsTests/` and is wired into the Xcode project (the
`LightStatsTests` unit-test target on the shared `Light Stats` scheme), so CI and the command
below run it. Coverage focuses on the pure, regression-prone logic: the `HealthScoreService`
scoring curves, the default-off settings contract, and the three AI-usage JSON parsers (via
fixtures under `LightStatsTests/Fixtures/`).

```bash
xcodebuild test \
  -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" \
  -destination 'platform=macOS'
```

### Tech Stack

- SwiftUI for panels and settings
- AppKit for menu bar integration, popovers, overlays, and custom views
- Combine and Swift Concurrency
- Mach API, IOKit, Accessibility, Core Graphics event taps, CFNetwork, Network, SMC, and getifaddrs
- Zero third-party runtime dependencies

### Architecture

The app separates metrics into models, services, view models, and views. `SystemMonitor` coordinates sampling and publishes snapshots to the UI, while services collect data for each metric area.

Cached or asynchronous collectors, such as exit-node lookup and AI usage providers, use actors. UI-bound state stays on the main actor. Fast syscall helpers remain synchronous where appropriate.

### Project Layout

- `Light Stats/Models/`: metric data structures, health score, release info, `AppTheme`, snap actions, input-source options
- `Light Stats/Services/`: system collectors, scoring, update, scroll reversal, native-first window snapping, hotkeys, titlebar gestures, keyboard lock, AI usage, Finder menu, display brightness, diagnostic journal
- `Light Stats/ViewModels/`: app state, sampling, settings, cleaning mode, update coordination, Finder menu, display control
- `Light Stats/Views/StatusBar/`: menu bar rendering
- `Light Stats/Views/Popover/`: floating panel UI and reusable components
- `Light Stats/Views/Theme/`: theme tokens, mesh backgrounds, grain, picker, appearance presets
- `Light Stats/Views/Settings/`: settings UI (system-white tool panel)
- `Light Stats/Views/About/`: about window
- `Light Stats/Views/CleaningMode/`: cleaning mode overlay
- `Light Stats/Views/Update/`: update progress window
- `Light Stats/Views/Permission/`: themed Accessibility guidance panel
- `Light Stats/Utilities/`: formatters, metric history, `SVGIcon`
- `Light Stats/Resources/`: localized strings, window-control icons, metric SVG outlines
- `FinderMenu/` and `FinderMenuExtension/`: shared Finder actions and FinderSync integration
- `LightStatsTests/`: XCTest suites (health score, defaults, AI parsers, PTY, diagnostics, window snap, default input source, Finder templates, SemVer)
- `.github/workflows/`: reusable quality gates plus build, Pages deploy, and signed release automation

---

## Roadmap

- More detailed network diagnostics
- Additional validation across laptop and desktop Macs
- Per-app network usage tracking
- More granular cleanup recommendations
- Continued tuning for themes, window gestures, and menu bar density
