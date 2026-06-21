# init

Generate or update `GROWTH.md` — the per-project context file that every other `growth` command reads. This is what makes the skill portable: no project facts live in the skill, they live here, regenerated for whatever project the skill lands in.

Run this first on any new project. If `GROWTH.md` already exists, `init` updates it rather than starting over.

## Process

### 1. Check for an existing file

If `GROWTH.md` exists at the project root, read it, summarize what's captured, and ask which sections to update. Only re-gather those. Don't discard the user's edits.

### 2. Auto-draft from the project (preferred)

Inspect the repository and draft a first version. Read whatever the project actually has:

- **README** (all language variants) — the single richest source: description, features, install steps, screenshots, badges.
- **Manifest / metadata** — `package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, `*.podspec`, `Package.swift`, `*.xcodeproj`, `Info.plist`, `composer.json`, etc. Reveals name, platform, language, dependencies, license.
- **Repo metadata** — existing GitHub description and topics, `LICENSE`, `CONTRIBUTING.md`, release history, homepage URL.
- **Source layout / docs** — confirm claimed features actually exist; note the tech stack and any privacy posture (telemetry? network calls?).
- **An agent/architecture doc** if present (`CLAUDE.md`, `AGENTS.md`, `ARCHITECTURE.md`) — often the most accurate feature and design summary.

Draft all sections from what you find. Flag anything you inferred rather than confirmed.

### 3. Confirm with the user

Present the draft and ask: **"What's wrong? What's missing?"** Specifically confirm the things you can't reliably infer: the pricing model, the real differentiators (vs what the maker *thinks* is special), the named competitors, the target channels, and the voice. Iterate until the user signs off.

If the user prefers, walk through the sections conversationally instead of auto-drafting. Lead with product + differentiators; don't dump every question at once.

### 4. Write `GROWTH.md`

Save to the project root using the schema below. Then tell the user: *"Saved. The growth skill will use this for every promotion task. Run `/growth init` anytime to update it."*

## GROWTH.md schema

Keep it factual and tight. Leave a field blank rather than inventing it. Every claim here must be true, because it propagates into public copy.

```markdown
# Growth Context

*Last updated: [date]*

## Product
- **Name:**
- **One-liner:** (under ~15 words, the category + the differentiator)
- **What it does:** (2-4 sentences)
- **Category:** (how users would search for it, e.g. "macOS menu bar system monitor", "CLI HTTP client")

## Platform & distribution
- **Platform / requirements:** (OS, arch, runtime, version floor)
- **How it ships / installs:** (GitHub Release DMG, Homebrew, npm, PyPI, crates.io, App Store, etc.)
- **Updates:** (self-update, package manager, manual)
- **Repo:** (URL)
- **Site:** (URL or none)

## Pricing model
- (free / free + paid tier / one-time purchase / paid — with the real details. If free, say so. Never enterprise-SaaS framing.)

## Audience
- **Who it's for:** (primary users, in their terms)
- **Why they reach for it:** (the trigger / job to be done)

## Differentiators (ranked, all true)
- (the things only this project does, or does better — the core of every pitch)

## Competitors / alternatives
| Name | Model | Honest strength | How we differ |
|------|-------|-----------------|---------------|
| | | | |

## Channels
- **Where this audience is:** (the specific subreddits, registries, directories, communities that fit — e.g. r/macapps + Homebrew Cask for a Mac app; r/rust + crates.io for a Rust lib; Show HN + Product Hunt broadly)
- **Languages to publish in:**

## Voice
- **Tone:** (e.g. developer-to-developer, plain, technical)
- **Words to use / avoid:**

## Proof points (REAL only)
- (genuine metrics, notable users, real quotes — leave empty if none yet)

## Links
- **Social handles / accounts:**
- **Press / contact:**
```

## Notes

- `GROWTH.md` is separate from impeccable's `PRODUCT.md` on purpose: different fields, different lifecycle, no overwrite conflicts. If both exist, they can coexist.
- Re-run `init` after a major release or pivot. Stale context produces stale copy.
- The pricing and differentiator fields are the ones most often gotten wrong by auto-draft. Always confirm them with the user before relying on them.
