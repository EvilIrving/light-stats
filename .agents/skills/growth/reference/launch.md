# launch

Plan a release or first public launch for an indie/open-source project. Read `GROWTH.md` first for the product, differentiators, channels, and pricing model.

Forget the SaaS launch playbook (waitlists, five-phase betas, lead capture, "early access" gating). For a maker project the model is simpler: ship the release, then announce it where this project's audience actually gathers, in the order that compounds. The release pipeline itself (tags, build, publish, package registry) is the project's own; your job is the *attention* layer on top of it.

## Pre-flight (must be true before announcing anything)

- [ ] The release is **actually published and installable** — the artifact built, downloads work, the package/registry entry resolves. Verify, don't assume.
- [ ] README is current: features match the build, screenshots are fresh, install steps work from a clean machine.
- [ ] First-run / first-use is honest about anything surprising (permissions, network access, required config), not sprung on the user.
- [ ] A short demo GIF/asset exists (see `visuals`). For a UI tool this is the single highest-leverage asset; for a CLI/library, a clean terminal cast or code sample is the equivalent.
- [ ] Release notes written (see `copy`).
- [ ] You can answer "why this, why now?" in one sentence (from `GROWTH.md` differentiators; see `position`).

If any are false, fix before launching. A launch you only get once should not point at a broken install or a stale README.

## Channels

Pull the specific channels from `GROWTH.md` → Channels. The fit depends on what the project is. General map:

| Channel | Fits | Effort | Notes |
|---|---|---|---|
| **Repo + release page** | Everything | Low | Home base. Release notes + README are the canonical pitch; everything links back here. |
| **Hacker News (Show HN)** | Open-source, native, technically interesting | Medium | Only with a real technical hook (see below). Broadly applicable across project types. |
| **Reddit** | Most projects | Low–Med | Use the *specific* subreddit for the niche from `GROWTH.md` (e.g. r/macapps for a Mac app, r/rust for a Rust crate, r/selfhosted for a server tool). Read each sub's self-promo rules. |
| **Product Hunt** | Polished apps/tools with broad appeal | Med–High | Optional. Works for indie products; rewards a warm audience. |
| **Package registry / store** | Libraries, CLIs, apps, self-hosted | Low | Homebrew, npm, PyPI, crates.io, Docker Hub, App Store, marketplace, etc. — whatever the project ships through. A good registry listing is durable discovery. |
| **Directories** | Apps with a category | Low | Category directories + alternativeTo + relevant `awesome-*` lists. See below. |
| **Social / dev communities** | Everything | Low | Hand to `social`. |

Skip (don't fit a free/indie project): paid ads, journalist/PR pitching (press won't cover a small free tool without a real story), B2B review sites (G2/Capterra), email-list waitlists.

## The "why this exists" hook

Every channel asks it. Pick the sharpest *true* angle from `GROWTH.md` differentiators. Common indie/OSS hooks:

- **Open-source + native + zero/few dependencies** — strongest on HN.
- **Free/open alternative to [the dominant paid tool]** — strongest on Reddit. Stay honest about the incumbent's strengths (see `position`).
- **The one genuinely novel capability** — whatever this project does that nothing else does.
- **Privacy / local-first** — if true.

## Hacker News (Show HN)

HN rewards substance and punishes marketing. Only post with a genuine technical story.

- **Title**: `Show HN: [Name] – [plain category description]`. No adjectives, no hype.
- **First comment (yours)**: why you built it, what's technically interesting (the hard part, the architecture, the constraint you solved), and honest limitations.
- **Be present** for the first few hours. Answer every technical question plainly; concede real shortcomings.
- **Never** ask for upvotes; HN flags it instantly.
- Best days: Tue–Thu mornings US time. Weekend Show HN gets less traffic but a friendlier crowd.

## Reddit

- Read each subreddit's self-promo rules first; they vary widely.
- **Lead with the demo asset**, then 2–3 sentences on what it is and the honest hook. Link the repo/release.
- Disclose you're the author. Maker communities respect "I made this, it's free/open source" and resent stealth marketing.
- Reply to every comment, including critical ones, without defensiveness.
- Ongoing presence follows the 90/10 rule: be a genuine member, not a drive-by promoter.

## Directories & registries (trimmed)

Submit once, point at the repo or release. No 13-tier SaaS catalog.

| Surface | Fits | Notes |
|---|---|---|
| **alternativeTo** | Apps with named alternatives | List against the incumbents from `GROWTH.md`. The "alternative to X" framing matches real search intent. |
| **Package registry / store** | Per ecosystem | Homebrew Cask/formula, npm, PyPI, crates.io, Docker Hub, App Store, plugin marketplace — lowers install friction for the target audience. |
| **GitHub topics** | Every repo | Add accurate topics; free discovery inside GitHub. |
| **`awesome-*` lists** | Most projects | PR into the relevant curated lists (honest placement only). |
| **Category directories** | Apps | The niche directories named in `GROWTH.md`. |

Skip: "submit to 200 directories" spam, paid submission services, B2B review sites.

## Product Hunt (optional)

Works for a polished indie app but is optional.

- Prepare: a clear tagline (~60 chars), 3–6 gallery images (real screenshots + the GIF), a 30–60s demo, and a first comment telling the build story.
- Launch Tue–Thu, 12:01 AM Pacific. Be present all day; reply to every comment.
- Ask for **feedback**, never upvotes.
- Convert attention into repo stars and traffic, since there's no signup to capture.

## Ongoing launches

Each meaningful release is an announcement:

- **Major** (new capability) — release notes + the niche subreddit + social + maybe a fresh Show HN if there's a new technical angle.
- **Medium** (refinements, new integration) — release notes + social.
- **Minor** (fixes) — release notes only. Steady changelog activity signals a living project, which itself drives trust and stars.

## Deliverable

Pre-flight gaps, channel order with the chosen hook per channel (channels from `GROWTH.md`), the Show HN title + first-comment draft (if applicable), the Reddit post draft, the directory/registry checklist, and a simple day-of timeline. Every item actionable today.
