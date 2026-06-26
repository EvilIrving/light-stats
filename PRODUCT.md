# Product

## Register

brand

## Users

macOS power users, developers, and system administrators. They keep a terminal open, run local AI coding agents, and care whether their machine is fast *right now*. They want truth about what their Mac is doing without leaving the menu bar, and they distrust tools that phone home.

## Product Purpose

Light Stats is a native macOS menu bar instrument. It reads CPU, GPU, memory pressure, disk, disk I/O, network throughput, proxy state and exit node, battery, temperature, fan, processes, and local AI-agent usage (Claude Code, Codex, Gemini CLI), then folds the live pressure signals into a single 0–100 health score. A compact menu bar widget shows the essentials; a click opens a detailed panel.

Monitoring is the core, and it stays read-only. Around it Light Stats has grown a small set of optional system tools — window snapping, scroll-direction reversal, a keyboard cleaning lock — but **every one of them ships off**. A user who only wants the readout never sees an extra icon, is never asked for Accessibility permission, and pays no event-tap or network cost. Restraint here is not "fewer features"; it is "nothing you didn't ask for runs."

This web page is its external presence: a landing page that shows the real instrument, a privacy policy that tells the truth about the one opt-in network feature, and a support hub.

### What sets it apart

- **Network truth, not just speed.** Beyond up/down throughput, it detects whether you are behind a proxy and which exit node you are leaving through (opt-in, geo-located).
- **One honest health number.** The score reflects responsiveness pressure, not capacity. A Mac with 30 GB used stays green if it isn't actually struggling.
- **AI-agent usage in the menu bar.** Live token-window usage for Claude Code, Codex, and Gemini CLI, read locally.
- **Opt-in by construction.** Monitoring is read-only and always on; every capability that touches the system or the network (window management, scroll reversal, exit-node detection, AI usage) is off until you turn it on, and goes fully silent when you turn it off. The monitor's credibility and the extra tools' intrusiveness never collide because the intrusive parts default to dormant.

## Brand Personality

A precision instrument. Calm, mechanical, exact. Numbers are tabular and trustworthy; the page reads like a well-labeled readout, not a sales pitch. Apple-adjacent restraint without imitation. When it commits to a signal color, that color means something (live, healthy, measured).

## Anti-references

- Bloated SaaS landing pages with animated counters and gradient heroes
- Dark pattern privacy policies that bury or deny data collection
- Terminal-green or neon "hacker" tech aesthetics worn as costume
- Material Design card grids with identical icon-title-description tiles
- Glassmorphism and decorative blurs
- The hero-metric template: one giant number, small label, gradient accent

## Design Principles

- **Show the instrument.** The real app, real readouts, real screenshots. Clarity is the pitch.
- **Native-first, deliberately.** The system font stack and macOS-honest color are a chosen voice for a Mac app, not a default. Mono carries the data.
- **Trust through transparency.** Every claim about data and network is concrete and verifiable, including the one feature that does reach out.
- **Every word earns its place.** No filler, no restated headings, no marketing-speak.
