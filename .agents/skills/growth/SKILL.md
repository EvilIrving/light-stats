---
name: growth
description: Use when the user wants to promote, launch, announce, or grow awareness of an indie or open-source software project. Covers release launches (Product Hunt, Hacker News Show HN, Reddit, platform directories, package registries), marketing copy (README, repo description and topics, release notes, taglines, listing blurbs), screenshots and demo GIFs, social posts and short demo clips, competitive positioning against alternatives, a single landing page / GitHub Pages site (structure, SEO, AI citation, schema), and open-source community growth (stars, issues, contributors, forum engagement). Reads project facts from GROWTH.md; run `init` to generate it. Not for in-app UI design (see impeccable) or installer/DMG artwork (see dmg-background).
version: 2.0.0
user-invocable: true
argument-hint: "[init · launch · copy · visuals · social · position · web · community] [target]"
license: Content distilled from a general SaaS marketing skill pack and rewritten for indie/open-source projects. See the attribution note at the end of this file.
---

Promotes and grows indie and open-source software. One skill, every promotion task. Honest, indie, developer-to-developer. Real assets, never fabricated numbers.

This skill replaces a 22-skill generic SaaS marketing pack. That pack assumed pricing tiers, sales teams, lead capture, and buyer ICPs. This one assumes a maker shipping a project on GitHub (or similar) and wanting it found and used. Project-specific facts are **not** baked in here; they live in `GROWTH.md` so the skill travels to any project unchanged.

## Setup (non-optional)

Two steps before any promotion work. Skipping either produces output that misstates the project or reads like generic SaaS marketing.

### 1. Load project context

Read **`GROWTH.md`** from the project root. It holds this project's facts: what it is, who it's for, how it ships, pricing model, differentiators, competitors, channels, voice, languages, and links. Every reference file reads from it.

- If `GROWTH.md` exists, consume it fully and proceed.
- If it's **missing, empty, or placeholder** (`[TODO]` markers, under ~200 chars): run `init` first (see [reference/init.md](reference/init.md)) to generate it from the project, get the user's confirmation, then resume their original task with the fresh context.
- If the facts are already in this session's history, don't re-read. Re-load after `init` runs or the user edits the file.

**Never invent project facts.** If `GROWTH.md` doesn't cover something a task needs (a competitor's current pricing, a real download count), get it from the project or the user, or leave it out. Do not guess.

### 2. Pick the surface

Every task targets one **surface**:

- **Repo-native** (README, repo description, release notes, issues) — the primary surface for a code project. Developer audience: dense, factual, links over adjectives.
- **Launch channels** (Product Hunt, Hacker News, Reddit, directories, package registries) — each has its own culture and rules; `launch` covers them.
- **Owned web** (a single landing page, if one exists) — `web` covers it. One page, never a SaaS marketing site.

Identify the surface from the task, apply the shared laws below, then the relevant reference file.

## Shared growth laws

Apply to every task. These are the skill's portable identity, true for any indie/OSS project.

### Honesty (this is the whole brand)

Indie and open-source tools earn trust by being trustworthy. Violating this is the fastest way to lose the audience that actually installs maker software.

- **Never fabricate numbers.** No invented download, star, or user counts, no "trusted by thousands," no made-up benchmarks. No real number → no number.
- **Never fabricate testimonials, reviews, or endorsements.** Quote only real, sourced feedback.
- **Never claim features that aren't shipped.** Verify against the project (README, source). "Coming soon" is fine when labeled.
- **Be honest about competitors.** State their genuine strengths. Evaluators verify, and maker communities punish dishonest comparisons hard.

### Positioning

- Lead with what's true and durable for this project. Pull the differentiators from `GROWTH.md`; for OSS that's often *free, open, native, lightweight, privacy-respecting*.
- Match the project's real pricing model from `GROWTH.md` (free, one-time, or a light paid tier). Never use enterprise-SaaS framing: no "book a demo," "contact sales," "start your trial," gated downloads, or lead-capture forms. Indie distribution is "download / install / star," not a funnel.
- If the project respects privacy (local-first, no telemetry, opt-in network), say so plainly. It's a selling point.

### Voice

- Developer-to-developer by default; honor the voice recorded in `GROWTH.md`. The audience reads diffs.
- Specific over vague. Concrete capabilities and real constraints beat adjectives.
- Show the thing. A GIF of the tool working beats a paragraph describing it.
- **No em dashes.** Use commas, colons, semicolons, periods, or parentheses. Also not `--`.
- No buzzwords: drop "revolutionary," "game-changing," "seamless," "cutting-edge," "powerful," "robust," "next-gen." If a sentence survives deleting the adjective, delete it.

### The marketing-slop test

If a power user or HN reader would read it and think "AI-written marketing fluff," it failed. Two reflex checks:

- **Number check** — every statistic traces to a real source, or it's cut.
- **Category-reflex check** — if the copy could describe any tool in the category, it's generic. Rewrite around what only *this* project does (from `GROWTH.md`'s differentiators).

## Commands

| Command | Description | Reference |
|---|---|---|
| `init` | Inspect the project and generate or update `GROWTH.md` (run first on any new project) | [reference/init.md](reference/init.md) |
| `launch [version/what]` | Plan a release or first public launch across the channels that fit an indie/OSS project | [reference/launch.md](reference/launch.md) |
| `copy [target]` | Write or refine README, repo description/topics, release notes, taglines, listing blurbs | [reference/copy.md](reference/copy.md) |
| `visuals [target]` | Screenshots, demo GIFs, gallery shots, OG image, icon polish | [reference/visuals.md](reference/visuals.md) |
| `social [target]` | Launch and ongoing posts plus short demo clips for the platforms that fit | [reference/social.md](reference/social.md) |
| `position [target]` | Competitive landscape and honest positioning vs alternatives; user-language research | [reference/position.md](reference/position.md) |
| `web [target]` | The single landing page / GitHub Pages site: structure, lightweight SEO, AI citation, schema | [reference/web.md](reference/web.md) |
| `community [target]` | Open-source community: stars, issues, contributors, forum and Reddit engagement | [reference/community.md](reference/community.md) |

### Routing rules

1. **No argument** — render the command table above as a menu and ask what they'd like to do.
2. **First word matches a command** — load its reference file and follow it. Everything after the command name is the target.
3. **First word doesn't match** — general growth invocation. Run setup (load `GROWTH.md`, or `init` if absent), apply the shared laws, infer the closest command, and use the full argument as context.

Setup is loaded by the time a sub-command runs; sub-commands don't re-invoke `/growth`.

## Related skills

- **impeccable** — in-app UI / frontend design and landing-page visual craft. `web` here handles structure and content; hand visual polish to impeccable.
- **dmg-background** — installer/DMG background artwork. `visuals` here does not duplicate it.

---

*Attribution: the source material was a general-purpose SaaS marketing skill pack (ai-seo, launch, copywriting, copy-editing, competitors, competitor-profiling, customer-research, community-marketing, content-strategy, directory-submissions, image, video, social, schema, seo-audit, site-architecture, co-marketing, product-marketing, public-relations, programmatic-seo, free-tools). It has been content-reviewed, stripped of B2B/SaaS assumptions, consolidated into one skill, and made project-portable via GROWTH.md.*
