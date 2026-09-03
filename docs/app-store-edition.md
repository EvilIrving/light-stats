# Mac App Store Edition

**Branch:** `feature/app-store`  
**Decision date:** 2026-03-26  
**Pricing:** App Store build is **free** (no IAP, no activation codes)

## Goal

Ship a sandboxed Mac App Store (MAS) build **alongside** the existing Developer ID / DMG direct build. The direct product stays full-featured. The store product is a free monitoring subset that can pass App Sandbox and App Review.

```
Direct (unchanged)          App Store (new)
─────────────────           ────────────────
sandbox OFF                 sandbox ON
Developer ID + notarize     Apple Distribution + ASC
self-update (R2/GitHub)     App Store updates only
activation codes / gift     no license UI (free)
full toolbelt               monitoring + Finder menu
```

## Non-goals

- Do not replace or weaken the direct DMG pipeline (`script/build.sh`, `release.yml`).
- Do not add StoreKit / IAP in this edition (store is free).
- Do not force Feature-parity with the direct build.
- Do not change the direct bundle id or UserDefaults keys for existing users.

## Distribution identity

| | Direct | App Store |
|---|---|---|
| Bundle ID | `cain.com.light-stats` | **same** `cain.com.light-stats` |
| App Group | `QZZ878S3NS.com.light-stats.shared` | same |
| Compile flag | _(absent)_ | `APP_STORE` |
| Entitlements | `LightStats.entitlements` | `LightStats-AppStore.entitlements` |
| Configurations | `Debug` / `Release` | `AppStoreDebug` / `AppStore` |
| Scheme | `Light Stats` | `Light Stats AppStore` |

Same bundle ID keeps a single App Store Connect app record and avoids “two apps” confusion. Direct and MAS installs still conflict if both are installed (macOS treats them as the same app id) — document that users should pick one channel; advanced users can keep Direct only.

## Capability matrix

| Capability | Direct | App Store | Reason |
|---|:---:|:---:|---|
| CPU / GPU / memory / disk / disk I/O / network | ✓ | ✓ | Public / sandbox-friendly APIs |
| Battery | ✓ | ✓ | IOKit power sources |
| Health score | ✓ | ✓ | Temperature falls back to `thermalState` only |
| Process list + cleanup | ✓ | ✗ | Sandbox blocks terminating other apps; `/bin/ps` enumeration often denied |
| Themes / localization / launch at login | ✓ | ✓ | |
| Exit-node detection (opt-in) | ✓ | ✓ | `network.client` |
| Finder right-click menu | ✓ | ✗ | Not part of MAS monitoring subset; appex stripped from App Store builds |
| SMC temperature / fan RPM | ✓ | ✗ | Private `AppleSMC`; Review risk |
| Self-update | ✓ | ✗ | MAS forbids replacing own binary |
| Activation / Pro gift UI | ✓ | ✗ | Store edition is free; no codes |
| AI usage (Claude / Codex / Gemini) | ✓ | ✗ | Keychain of other apps + PTY scrape |
| Window snapping / titlebar gestures | ✓ | ✗ | Accessibility APIs vs sandbox |
| Find My Mouse / presentation pointer | ✓ | ✗ | Event taps + overlay tooling |
| Scroll reverse | ✓ | ✗ | Event tap; defer until proven |
| Cleaning mode (key swallow) | ✓ | ✗ | Suppressing keys needs privileges Review dislikes |
| Keep awake / virtual display | ✓ | ✗ | Virtual display / private paths |
| Display brightness (DDC / private) | ✓ | ✗ | Private frameworks must not ship |

## Architecture

### Compile-time channel

```swift
enum AppDistribution {
    enum Channel { case direct, appStore }

    #if APP_STORE
    static let channel: Channel = .appStore
    #else
    static let channel: Channel = .direct
    #endif

    static var isAppStore: Bool { channel == .appStore }
    // Capability booleans derived from channel…
}
```

UI and AppDelegate consult `AppDistribution` (or `#if APP_STORE`) so Direct builds keep today’s behavior with zero runtime cost.

### Build settings (AppStore*)

- `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) APP_STORE`
- `CODE_SIGN_ENTITLEMENTS = Light Stats/LightStats-AppStore.entitlements`
- `ENABLE_APP_SANDBOX = YES`
- `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` (exit node / future ASC only)
- Clear private-framework link flags and bridging header:
  - no `CoreDisplay` / `DisplayServices`
  - no `DisplayPrivateAPI.h` bridging header
- `EXCLUDED_SOURCE_FILE_NAMES` for `DisplayControl/**` private implementation files (stubs remain compilable under `APP_STORE`)

### Entitlements (MAS)

```
com.apple.security.app-sandbox = true
com.apple.security.network.client = true
```

No App Group / user-selected files (Finder menu is Direct-only). No `com.apple.security.temporary-exception.*` in v1. Prefer cutting features over exceptions.

### Settings surface (MAS)

Sidebar categories:

- General (theme, language, launch at login, logs) — **no** update section, **no** activation
- Monitoring (status items, health toggles, exit node, refresh)

Hidden: Input Devices, Window Management, AI Usage, Finder Menu.

Popover: Overview only — **no** Cleanup tab (process list / quit apps).

About window: version only; **no** “Check for Updates” (App Store handles updates).

Status bar: no window-controls item; no fan RPM when SMC absent; temperature UI uses thermal state / omits CPU °C when nil.

## License & monetization

- MAS build: free. No activation UI. No StoreKit in this phase.
- Direct build: unchanged (`AppConfig.proGiftEnabled`, activation codes).
- `LicenseManager` remains in the target for Direct; MAS UI never presents it. Capability gates do not call `isPremiumUnlocked` for removed tools.

## Update policy

| | Direct | App Store |
|---|---|---|
| `UpdateManager.checkOnLaunch` | opt-in setting | no-op / not compiled into launch path |
| About “Check for Updates” | shown | hidden |
| Settings update toggles | shown | hidden |

## Testing

- Direct `Debug`/`Release`: existing XCTest suite must stay green (no behavior change).
- `AppStoreDebug`: smoke build + launch; confirm sandbox column = Yes; confirm hidden settings categories; SMC/AI/window tools absent.
- Manual: enable exit node; Finder extension still works via App Group.
- Do **not** require App Store signing in CI for every PR; add a compile gate (`xcodebuild -scheme "Light Stats AppStore" -configuration AppStoreDebug build`) when credentials allow.

## Rollout

1. Land engineering on `feature/app-store` (this doc + gates + configs).
2. Local archive with App Store signing; TestFlight internal.
3. App Review notes: “Free system monitor. Optional exit-node geo lookup. No Finder extension, no process cleanup, no Accessibility features in this build.”
4. Privacy nutrition labels: diagnostics local; exit-node only when enabled; no tracking.
5. Keep Direct releases on the existing tag → DMG path.

## Risks

| Risk | Mitigation |
|---|---|
| IOAccelerator GPU read blocked in sandbox | Show “—” / hide GPU; health score drops GPU weight via existing optional path |
| Process kill / list under sandbox | Cleanup Tab removed from MAS (`includesProcessCleanup`) |
| Review asks about menu-bar / background | `LSUIElement`; explain monitoring purpose in review notes |
| Same bundle ID vs dual install | README note: prefer one channel |
| Future paid MAS | Separate decision; would add StoreKit without re-enabling private APIs |

## Implementation checklist

- [x] Design doc (this file)
- [x] `AppDistribution.swift`
- [x] `LightStats-AppStore.entitlements`
- [x] `AppStore` / `AppStoreDebug` pbxproj configurations (+ `Config/*.xcconfig` helpers)
- [x] Scheme `Light Stats AppStore`
- [x] Gate Settings / About / AppDelegate / status bar / popover
- [x] Stub DisplayControlManager + SMCInfo under `APP_STORE` (no private frameworks / AppleSMC)
- [x] MAS drops Cleanup tab + Finder menu (`includesProcessCleanup` / `includesFinderMenu`); appex omitted on AppStore*
- [x] AGENTS.md / CLAUDE.md note on dual distribution
- [x] Verify Direct Debug + AppStoreDebug compile (sandbox on for MAS; AppleSMC / private display symbols absent)
- [x] Listing runbook: `docs/mac-app-store-listing.md`
- [x] Screenshot set: `docs/app-store-screenshots/mas-1440x900/`
- [ ] TestFlight / App Review submission (follow-up; prefer AppStore-build overview shots without Pro/keep-awake/cleaning chrome)
