# Product

## Register

brand

## Users

macOS power users and developers. They keep a terminal open, run local AI coding agents, move through Finder, and care whether their machine is fast *right now*. They want system pressure, AI limits, and network truth without leaving the menu bar, and they distrust tools that phone home without being asked.

## Product Purpose

Light Stats is a native macOS menu bar instrument. It reads CPU, GPU, memory pressure, disk, disk I/O, network throughput, proxy state and exit node, battery, temperature, fan, processes, and AI-agent usage (Claude Code, Codex, Gemini CLI), then folds the live pressure signals into a single 0–100 health score. A compact menu bar widget shows the essentials; a click opens a detailed panel with short-term trends and process context. Product surfaces (popover, About, toast, update, permission prompts) can wear Classic, Golden Hour, Amber, or Ink Night; Ink Night is selected on a clean install, and Settings stays a system-white tool panel.

Monitoring is the core, and it stays read-only. Around it Light Stats has optional developer and system tools: AI usage, proxy exit-node lookup, Finder right-click actions and file templates, window snapping, mouse and trackpad scroll controls, display keep-awake, and a keyboard cleaning lock. Every network request and persistent system interaction ships off. A user who only wants the readout sees no extra icon, receives no Accessibility prompt, runs no event tap, and makes no outbound request. Restraint here is not "fewer features"; it is "nothing you didn't ask for runs."

This web page is its external presence: a landing page that shows the real instrument, a privacy policy that names every opt-in network behavior, and a support hub.

### What sets it apart

- **Network truth, not just speed.** Beyond up/down throughput, it detects whether you are behind a proxy and which exit node you are leaving through (opt-in, geo-located).
- **One honest health number.** The score reflects responsiveness pressure, not capacity. A Mac with 30 GB used stays green if it isn't actually struggling.
- **Developer context in the menu bar.** Subscription windows for Claude Code, Codex, and Gemini sit beside proxy and exit-node context; Finder actions open terminals, create files from type-aware templates, and route selected files without leaving Finder.
- **Opt-in by construction.** Monitoring is read-only and always on; capabilities that touch the system or network are off until enabled and stop when disabled. Automatic update checks, Beta channel, AI provider requests, usage-window warmup, exit-node lookup, Finder actions, event taps, and keep-awake assertions do not run on a clean install.
- **Instrument chrome you can choose.** Classic system readout, warm Golden Hour, lamp-lit Amber, or cool Ink Night; configuration UI stays plain white so it never competes with the dial.

## Brand Personality

A precision instrument. Calm, mechanical, exact. Numbers are tabular and trustworthy; the page reads like a well-labeled readout, not a sales pitch. Apple-adjacent restraint without imitation. When it commits to a signal color, that color means something (live, healthy, measured). Ink Night is the clean-install look. Classic uses system materials, Golden Hour uses warm brass over amber and coral light, Amber uses warm bar lamplight with a teal neon accent, and Ink Night uses cool charcoal grain.

## Anti-references

- Bloated SaaS landing pages with animated counters and gradient heroes
- Dark pattern privacy policies that bury or deny data collection
- Terminal-green or neon "hacker" tech aesthetics worn as costume
- Material Design card grids with identical icon-title-description tiles
- Decorative glassmorphism that blurs data instead of carrying it
- The hero-metric template: one giant number, small label, gradient accent

## Design Principles

- **Show the instrument.** The real app, real readouts, real screenshots. Clarity is the pitch.
- **Native-first, deliberately.** The system font stack and macOS-honest color are a chosen voice for a Mac app, not a default. Mono carries the data. Theme is product surface only; Settings stays a tool panel.
- **Content owns the visual hierarchy.** Health, live metrics, status, and trends are the panel's focal points. Navigation chrome—tab tracks, selected states, toolbar controls, wells, and hover washes—must remain subordinate: never the panel's darkest, brightest, most saturated, or highest-contrast region. Selection should read through small changes in type weight, a restrained wash, or a fine indicator, not a dominant filled control.
- **Trust through transparency.** Every claim about data and network is concrete and verifiable, including the one feature that does reach out. Diagnostic logs stay local (default Full, switchable down) and are redacted.
- **Every word earns its place.** No filler, no restated headings, no marketing-speak.
