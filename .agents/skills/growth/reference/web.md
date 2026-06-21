# web

The optional owned web surface: a **single landing page** (likely GitHub Pages), not a SaaS marketing site. Merges site structure, lightweight SEO, AI citation, and schema, scoped to one small page that points at the repo and releases.

Read `GROWTH.md` for product facts, differentiators, pricing model, and links. If there's no landing page and the README is the public face, most of this applies to the README's discoverability instead. Don't build a multi-page site, a blog, a CMS, or programmatic page farms; that machinery is irrelevant for an indie/OSS project.

For the page's visual craft, hand off to **impeccable** (`web` here is structure + content + discoverability; impeccable does the design).

## One-page structure

Top to bottom:

1. **Hero** — name, one-line description, the demo asset, a primary action button (download / install / the project's real entry point from `GROWTH.md`) plus a "View on GitHub" link.
2. **What it is** — one short paragraph; who it's for.
3. **Feature highlights** — scannable, grouped, with real screenshots. Emphasize the differentiators.
4. **Comparison** (optional) — the honest "alternative to [incumbent]" angle (see `position`).
5. **Install** — the real install paths and requirements from `GROWTH.md`, plus any trust note (signed/notarized, reproducible) and a permissions/config explainer.
6. **Footer** — repo, releases, license, language links (if multi-language), privacy note.

No pricing-funnel section, no signup, no lead-capture form, no newsletter gate. The conversion is "install" and "star the repo." If the project has a paid tier, present it as a plain price, not a sales motion.

## Lightweight SEO

For one page the fundamentals are enough:

- **Title tag**: `[Name] — [category + top differentiator]` (~55–60 chars).
- **Meta description**: one clear sentence with the differentiators (~150 chars).
- **One `<h1>`**, then sequential `<h2>`/`<h3>`. Clean hierarchy helps search and AI citation.
- **Target real intent**: the "[incumbent] alternative" and "[category]" queries from `position`. Use them naturally in headings and the first paragraph.
- **Image SEO**: descriptive filenames, real `alt` text, WebP, lazy-load below the fold, explicit width/height to avoid layout shift.
- **Performance**: keep it a static page. No heavy JS. Fast load is free here and helps ranking.
- **HTTPS** (GitHub Pages provides it), a canonical tag, a simple sitemap.

## AI citation (light touch)

So assistants can recommend it when asked "best [category]":

- **Lead each section with a direct, self-contained statement** ("[Name] is a [category] that [does X]."). Extractable sentences get cited.
- **A short FAQ** answering real questions (is it free? is it open source? how is it different from [incumbent]? what platforms? does it send data anywhere?). Mark it up with `FAQPage` schema.
- **Honest, specific facts** — assistants prefer concrete claims over adjectives.
- Don't write separate "content for AI" or chunk the page into bait fragments. One clear page serves people and AI both.
- Keep the README equally clear; assistants cite GitHub heavily for developer tools.

## Schema (JSON-LD)

Minimal, accurate structured data. Don't mark up anything not on the page.

- **`SoftwareApplication`**: `name`, `operatingSystem`, `applicationCategory`, `offers` with the real `price` (`"0"` if free), `softwareVersion`, `downloadUrl`, `url` (repo). Pull values from `GROWTH.md`.
- **`FAQPage`**: the FAQ Q&A pairs.
- Optionally **`BreadcrumbList`** only if the site has real hierarchy (a one-pager doesn't).

Validate with Google's Rich Results Test and the schema.org validator. Keep values accurate and current.

## Deliverable

For a landing page: the section outline with copy hooks (pull finished copy from `copy`), the title/meta, the heading map, the FAQ list, and the JSON-LD block. For improving the README's discoverability instead: the same applied to README structure. Keep it to one page; resist scope creep into a multi-page site.
