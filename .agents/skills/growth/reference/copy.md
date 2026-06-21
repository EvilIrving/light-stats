# copy

Write and refine the words: README, repo description and topics, release notes, taglines, launch-post copy, and listing blurbs. For an indie/OSS project most "copy" is repo-native and developer-facing. There is no funnel and (usually) no pricing page.

Read `GROWTH.md` first for the product facts, differentiators, voice, pricing model, and languages. Read the project's `README` to match the current feature set. **Never describe a capability you haven't confirmed in the project.**

## Principles

- **Clarity over cleverness.** The reader is scanning to decide whether to install. State what it is and why it's different in the first two lines.
- **Specific over vague.** Concrete capabilities and real constraints beat adjectives. Pull the specifics from `GROWTH.md`.
- **Benefit + proof.** Each claim should be checkable. Developers trust what they can verify.
- **Honest.** No fabricated numbers, no fake social proof, no unshipped features. (See the shared honesty law.)
- **No em dashes. No buzzwords.** Cut "revolutionary / seamless / powerful / cutting-edge / robust / game-changing."

## Quick word-level sweep

When editing existing copy:

- **Cut filler**: very, really, just, actually, basically, in order to, simply.
- **Replace weak verbs**: utilize → use, leverage → use, facilitate → help, implement → set up.
- **Kill empty adjectives**: powerful, robust, seamless, intuitive, modern, next-gen. If the sentence stands without it, delete it.
- **Active voice**, **one idea per sentence**. Tables and lists beat prose for feature rundowns.

## Surface-specific guidance

### Repo description (the one-liner)

Appears in search, social cards, the repo header. ~120 chars. Lead with the category + the top differentiator (both from `GROWTH.md`).

- Pattern: `[Category] — [what it does in a clause]. [Differentiator], [differentiator].`
- Add **topics** separately: accurate ecosystem/category tags so the repo surfaces in GitHub search.

### README

The primary pitch. Structure that works for a code project:

1. **Name + one-line description + badges** (build/release status).
2. **Language switcher** if `GROWTH.md` lists multiple languages.
3. **A screenshot, GIF, or code sample immediately** — show the thing before any prose.
4. **One short "what it is / who it's for" paragraph.**
5. **Features** grouped as scannable bullets.
6. **Install** — the real install paths from `GROWTH.md` (download, package manager, registry), platform/version requirements, and any trust note (signed/notarized, reproducible build).
7. **Permissions / config** — explain anything the tool needs and why. Honesty here converts skeptics.
8. **Build from source** — developers want it; it also proves an open-source claim.
9. **Contributing / License.**

Keep marketing language out of the README. It's documentation that sells by being clear.

### Release notes

Developers read these to decide whether to update.

- Group under **Added / Changed / Fixed** (keep-a-changelog style).
- Lead with the headline change in plain language.
- Link issues/PRs; credit contributors by handle.
- No hype. Precise technical descriptions are the right register.

### Taglines

2–3 options for launch posts / directories / social. Each under ~60 chars, each true, each built from a real differentiator in `GROWTH.md`. Provide options with a one-line rationale; let the user pick.

### Directory / listing blurbs

Vary the opening per audience (don't paste one description everywhere):

- **alternativeTo**: lead with the alternative framing ("Open-source alternative to [incumbent]").
- **Category directories**: lead with the outcome/use.
- **Dev / `awesome-*` lists**: lead with the technical substance (stack, dependencies, platform).

Each needs: a <10-word tagline, a ~60-char short description, a ~150-word long description, and 5–8 tags.

## Localization

If `GROWTH.md` lists multiple languages, produce copy in those (commonly en + others). Don't machine-translate and walk away: translate the full meaning, keep technical terms consistent, keep every version honest to the same feature set. If you can only do one language well, ship it and flag the rest as TODO rather than shipping low-quality translations.

## Deliverable

Copy organized by section, 2–3 options for headlines/taglines (each with rationale), and a flag on any claim you couldn't verify against the project so the user confirms it before publishing.
