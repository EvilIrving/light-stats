# Design System & UI Architecture

Light Stats follows a **precision instrument** aesthetic inspired by hardware telemetry, laboratory spec sheets, and Apple's own design restraint. It focuses on live pressure rather than passive capacity.

---

## 1. Core Principles

- **Precision Instrument, Not Generic Dashboard:** Data is presented as a high-density readout with hairline dividers, explicit section boundaries, and tabular typography. Avoid playful consumer illustrations, bulky cards, or artificial padding.
- **No Nested Cards:** The popover surface is a unified readout. Data rows sit directly on the theme background with hairline separators. Never nest bordered cards inside cards.
- **Fixed Widths for Jitter-Free Telemetry:** All real-time telemetry numbers use tabular digits (`tnum`) and fixed-width formatting so that fluctuating numbers never cause surrounding labels or layouts to jump.
- **Layer-Hosted Graphics for Efficiency:** Animated elements (such as spinning fans) execute on Core Animation layers directly (`FanIconLayerView`), avoiding continuous per-frame SwiftUI re-renders.

---

## 2. Client Application Design System

### Dimensions & Geometry
- **Menu Bar Status Item:** Compact 2-line display (~22pt height), fixed cell widths for upload/download speeds and metric readings.
- **Popover Panel:** Fixed width of `360pt`, dynamic height clamped to a maximum of `780pt` (visible screen area aware).
- **Settings Window:** Native macOS Preferences window (tabbed toolbar, clean system background, standard controls).

### Themes
Light Stats provides four visual themes for its floating popover and transient overlays:
1. **Ink Night (Shipped Default):** Charcoal-tinted matte dark ground with subtle film grain and cool, subdued telemetry accents.
2. **Classic:** Pure system material readout. Utilizes native Liquid Glass materials on macOS 26+ and standard vibrancy on macOS 14/15.
3. **Golden Hour:** Warm brass instrument ink layered over an amber-and-coral ambient light field.
4. **Amber:** Espresso-black ground inspired by vintage audio equipment, with warm amber glow and a teal accent.

*Note on Dynamic Lighting:* Golden Hour, Amber, and Ink Night support user-adjustable film grain and 5 levels of light-field dynamics (Still, Gentle, Natural, Smooth, Lively). The scene timeline automatically pauses when the popover is closed or hidden to ensure 0% idle CPU footprint.

### Typography & Numbers
- **System Sans:** `-apple-system` for primary labels, section headers, and prose.
- **Tabular Figures:** All numeric displays (percentages, frequencies, transfer rates, health scores) enforce `.monospacedDigit()` to guarantee alignment and prevent horizontal jitter.
- **Byte and Rate Formatting:** Centralized in `ByteFormatter` with strict rules: binary units (KiB, MiB, GiB) for memory; decimal (B/s, KB/s, MB/s) for network throughput; rate values padded to fixed character counts.

---

## 3. Website Design System

The official website (`website/index.html`) is specified in detail in [website/DESIGN.md](website/DESIGN.md).

- **Aesthetic:** Clean, left-aligned spec sheet in OKLCH cool light mode.
- **Palette:** Cool near-white background (`oklch(98.5% 0.004 255)`), hairline rules (`oklch(91% 0.006 260)`), and a single live-green health accent (`oklch(70% 0.16 150)`).
- **Layout:** Asymmetric hero (value proposition left, real popover frame right) with an auto-fit 7-domain telemetry grid.
