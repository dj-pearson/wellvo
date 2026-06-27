# Daily OK — Senior Check-In SEO / GEO / ASO Strategy

> **Status:** Active (feat/senior-checkin-seo). Supersedes the dual-audience framing in
> `pSEO.md` and aligns web + App Store on a **seniors-led** identity.
> **Decision (2026-06-27):** Seniors-led, teen secondary. We make senior / elderly
> daily check-in the primary identity on every brand surface (home hero, OG, titles,
> JSON-LD, App Store name/subtitle/keywords, AI-retrieval files). The teen / child
> funnel (`/child-safety`, kid-mode copy) stays **live and indexed** as a secondary
> long-tail catcher, but it no longer shares top billing.

---

## 1. Why seniors-led

- The App Store listing already moved first: name is **`Daily OK: Senior Check-In`**,
  subtitle **`Elderly safety & care alerts`**, keywords weighted to aging/caregiver
  (`docs/ASO_STRATEGY.md`). Web + AI surfaces were still running a 50/50 "aging
  parents **and** kids" message, diluting the entity.
- The keyword opportunity is lopsided: ~90% of mapped demand in `pSEO.md` is
  elderly/caregiver intent ("check in app for elderly", "daily check in app for
  seniors", "wellness check on elderly parent", "what to do when parent doesn't
  answer the phone"). The teen cluster is real but thin and more competitive
  (Life360 owns it).
- The narrative whitespace is **"presence without surveillance"** — a dignity-first
  daily reassurance for the adult child of an aging parent that needs no pendant, no
  GPS, no facility move. That story is sharpest when told about seniors.
- A single coherent entity ("the senior daily check-in app") ranks and gets cited by
  LLMs far better than a split one. GEO rewards a crisp, consistent definition.

## 2. The entity, stated once (canonical)

> **Daily OK is a senior check-in app.** Adult children set up a once-a-day "I'm OK"
> for an aging parent; the parent taps one giant button (or replies from the
> notification). If they miss it, Daily OK fires escalating alerts to a chosen circle
> of family. No pendant, no GPS tracking, no cameras, no wearables. The same gentle
> check-in also works for teens and any loved one you worry about. iOS and Android,
> $3.99–$9.99/mo with a free trial.

This exact framing must appear, verbatim or near-verbatim, in:
`llms.txt`, `llms-full.txt`, the home `<meta description>`, the site-wide
`SoftwareApplication` JSON-LD `description`, and the App Store description's first
line. Consistency across these is the single biggest GEO lever — keep them in sync.

## 3. Keyword architecture (web)

**Primary (head + brand surfaces):**
senior check-in app · check-in app for elderly / for seniors · daily check-in app
for elderly parents · elderly safety app · welfare/wellness check app · aging-in-place
check-in · medical alert alternative (no pendant).

**Supporting clusters (existing pSEO pages — keep, retitle senior-first):**
- `/check-in-app-for-elderly`, `/daily-check-in-app-for-seniors`,
  `/peace-of-mind-app-for-elderly-parents`, `/elderly-care` — cornerstone, internally
  linked from the home "Perfect for" senior card and footer.
- Jobs-to-be-done / `/what-to-do/*` — "parent isn't answering the phone", calm plans.
- Comparisons `/compare/*` — vs Life Alert, vs Snug Safety, vs Life360 (frame Life360
  as the *teen/location* alternative, us as the *senior/consent* one).

**Secondary (teen — keep indexed, do not feature):**
`/child-safety`, kid-mode. Left standing as long-tail; demoted from hero/nav primacy,
not redirected. Revisit in 90 days: if teen pages cannibalize the senior entity in
Search Console, orphan them (remove from nav, keep in sitemap).

## 4. GEO / AI-search (rank in ChatGPT, Claude, Perplexity, Google AI Overviews)

- **`llms.txt` / `llms-full.txt`** — lead with the §2 canonical definition; senior
  use case first, teen as one secondary line. Keep the page index accurate (no dead
  links). These are the retrieval source of truth until entity profiles exist.
- **`robots.txt`** — explicitly allow the full modern crawler set: GPTBot,
  OAI-SearchBot, ChatGPT-User, ClaudeBot, Claude-SearchBot, PerplexityBot,
  Perplexity-User, Google-Extended, Applebot, Applebot-Extended, Amazonbot,
  Bytespider, CCBot, cohere-ai, Meta-ExternalAgent, Diffbot, Bingbot, YandexBot.
  Keep `/admin`, `/api`, `/account`, `/app/` disallowed for all.
- **Structured data** — `SoftwareApplication` with `audience` (caregivers + seniors),
  `featureList`, `screenshot`, `aggregateRating` (only when we have real ratings —
  never fabricate); `Organization` with `sameAs` to the App Store + social/entity
  profiles; `FAQPage` on every cornerstone page answering the literal questions people
  ask AI assistants ("is there a check-in app for elderly parents?", "what happens if
  my mom doesn't check in?").
- **Answer-shaped content** — each cornerstone page opens with a 1–2 sentence direct
  answer (extractable snippet) before the marketing prose. LLMs and AI Overviews lift
  the first clear definition.
- **Entity authority (off-codebase, tracked here):** register the §2 description on
  Wikidata, Crunchbase, G2, Capterra, Product Hunt so the entity is consistent across
  the web. This is what graduates Daily OK from "a site" to "a known thing".

## 5. Multi-engine indexing (Google / Bing / Yandex)

- **Verification:** add GSC, Bing Webmaster, and Yandex Webmaster verification tags
  (placeholders wired in `+onRenderHtml.tsx` STATIC_HEAD + documented below). Submit
  `sitemap.xml` in all three consoles.
- **IndexNow:** publish an IndexNow key file in `public/` and ping
  `api.indexnow.org` on deploy so Bing + Yandex index new/changed pages within
  minutes instead of waiting for a crawl. (Google does not use IndexNow; it gets the
  sitemap + GSC.)
- **Sitemap:** already auto-generated at build from prerendered HTML with git
  `lastmod` (`scripts/generate-sitemap.mjs`). No change needed beyond keeping noindex
  pages out.

## 6. App Store (ASO) — keep web and store identical

The store is already seniors-led (`docs/ASO_STRATEGY.md`). Keep the description's
first line equal to the §2 canonical sentence. Subtitle: senior/elderly safety.
Keywords: aging/parent/caregiver/elderly/welfare/fall/alone/wellness + secondary teen
terms only where character budget remains. Screenshots: senior receiver tapping the
giant "I'm OK" button first; teen frame, if any, last. Custom Product Pages: a
senior-specific CPP is the priority; a teen CPP is optional secondary.

## 7. Imagery transition

Lead imagery = aging parent / adult-child-caregiver emotional register, not generic
family. Concrete changes:
- `og-image` (social card) — senior + "I'm OK" + escalation cue; update the SVG
  source and regenerate the PNG (binary; needs a render/export pass).
- Home "Perfect for" order: **Aging Parents & Dementia Care first** (already first),
  teen card after long-distance.
- Alt text everywhere describes the senior check-in scene.
- App Store screenshots: see §6.

> Photographic/PNG assets (og-image.png, screenshots) are binary and need a designer
> or a capture-script run — this repo can update the SVG sources, alt text, captions,
> and the screenshot caption spec, and flags the binary regen as a follow-up.

## 8. Measurement

- GSC + Bing + Yandex: track impressions/clicks for the §3 primary cluster.
- GA4 (`G-J2H67EW9JY`): `download_cta_click` by landing page; senior pages should
  carry the load.
- Re-audit at 30 / 60 / 90 days. 90-day gate: decide whether teen pages stay indexed
  or get orphaned based on whether they help or dilute the senior entity.

## 9. Backward-compat notes (per CLAUDE.md)

- All web/SEO/doc changes here are additive or copy-only — no API/DB/on-device state
  touched, so no `MIN_SUPPORTED_*` constraint applies.
- Do **not** change existing URL paths for indexed pages (no renames of
  `/child-safety` etc.) — demotion is via nav/linking/copy, not redirects, to avoid
  losing existing equity. Any future redirect must be a 301 with the old URL kept in
  the sitemap through one indexing cycle.
- App Store product IDs and bundle ids are untouched (`net.wellvo.*`,
  `com.wellvo.ios`).
