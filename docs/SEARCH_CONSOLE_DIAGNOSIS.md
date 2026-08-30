# Search Console diagnosis — dailyok.net

**Data:** GSC performance export, 21 Apr – 27 Aug 2026 (128 days, 875 impressions, 14 clicks).
**Also analysed:** Google Keyword Planner export (166 keywords, Aug 2025 – Jul 2026); the `website/`
source tree at `8bfa7c0`, built and prerendered locally to inspect emitted HTML; live SERP checks.

Companion to `docs/SEO_STRATEGY.md` and `pSEO.md`. Those describe the plan; this describes what the
plan actually produced and where it went wrong.

---

## 1. Headline numbers

| Metric | Value |
| --- | --- |
| Impressions | 875 |
| Clicks | 14 (1.6% CTR) |
| Days of data | 128 (index begins 2026-04-21) |
| Prerendered pages | 38 |
| Pages with **zero** impressions | **25 of 38** |
| Non-brand average position | **52–88** |
| Mobile / desktop position | 6.93 / 23.21 |

---

## 2. What we rank for

GSC reports 25 queries above threshold, covering 276 of 875 impressions (32%). Bucketed:

| Pile | Queries | Impressions | Share | Clicks |
| --- | ---: | ---: | ---: | ---: |
| Our brand (`dailyok`, `daily ok`, `ok daily`) | 8 | 191 | 69% | 4 |
| **Someone else's brand** (`daily keeper`, `dailykeeper`) | 7 | 35 | 13% | 0 |
| Real non-brand demand | 10 | 50 | 18% | 0 |

Every non-brand query, with average position:

| Query | Impr. | Position |
| --- | ---: | ---: |
| daily check in app | 20 | 61.9 |
| daily check-in app | 9 | 58.9 |
| daily check in app for seniors | 7 | 84.9 |
| checking in on elderly parent daily | 4 | 79.8 |
| daily check on seniors | 4 | 85.8 |
| daily check in for seniors | 2 | 52.0 |
| daily check in apps | 1 | 52.0 |
| elderly daily check in | 1 | 81.0 |
| daily check-in calls for seniors | 1 | 86.0 |
| daily check in calls for seniors | 1 | 88.0 |

All page 6–9. All contain the literal string *daily* — Google is matching the brand name, not the
page content. Same reason we surface for `daily keeper`, an unrelated company.

We rank **2.13** for `dailyok`, our own exact brand name.

**Correction (2026-08-29) — the cause is not what this document first assumed.** The
original reading was that the brand ranking suffered from naming inconsistency between
the store listing and the site. That is at best secondary. The name is genuinely
**contested**: `Daily OK` and `DailyOK` were both already taken on the App Store (which
is why the listing carries the `: Senior Check-In` suffix), and `dailyok.com` is
registered to someone else. Other entities legitimately use this name, and one of them
is what outranks us.

This matters for expectations. `alternateName` schema (US-WEB012) helps Google
disambiguate us where it is *uncertain*, but it cannot win a name another party also
uses. **Position 1 for `dailyok` is probably not attainable**, so brand queries — 69% of
current visibility — have a ceiling. That is an argument for the non-brand strategy in
§6, not against it: the welfare-check cluster and the problem-moment pages are the only
traffic we can actually own.

---

## 3. Findings, ranked by traffic impact

### 1. The homepage cannibalises the three cornerstone commercial pages — BLOCKING

Homepage: 479 impressions at average position 16.95. Decomposed: ~191 brand impressions at ~pos 2.5
plus the remainder at ~pos 26 averages 16.6 — matching the reported 16.95. So **the homepage is the
page ranking at position 52–88 for `daily check in app`**, not `/daily-check-in-app-for-seniors`,
which has zero impressions.

Cause: `/check-in-app-for-elderly`, `/daily-check-in-app-for-seniors` and
`/peace-of-mind-app-for-elderly-parents` are linked **only from the footer** (`src/components/Footer.tsx`).
No homepage body link, no link from the `/what-to-do/*` pages that actually earn impressions. Google
treats footer-only links as boilerplate.

### 2. The entire blog is invisible to Google — BLOCKING

Three faults stack:

- `pages/+onBeforePrerenderStart.ts` does not prerender blog posts — they are fetched from Supabase
  at runtime (`src/pages/BlogPost.tsx`).
- `scripts/generate-sitemap.mjs` builds the sitemap by walking prerendered
  `dist/client/**/index.html`, so no post is ever listed.
- `public/_redirects` contains `/blog/* / 200` — every post URL is served **the homepage's
  prerendered HTML**, homepage `<title>` and homepage canonical included, before any JS runs.

`/blog` itself prerenders to 145 words with **no canonical tag** and no links to any post, because it
also fetches its list client-side. There is no discovery path into the blog at all. Confirmed by GSC:
not one `/blog/*` URL in four months.

### 3. Ten of thirteen pages are split across two URL variants — DILUTING

`/pricing` (114 impr) and `/pricing/` (14 impr) are indexed separately. Same for `/terms`, `/privacy`,
`/support`, `/dmca`, `/elderly-care`, `/child-safety`, `/compare/daily-ok-vs-mobilehelp`,
`/what-to-do/elderly-father-not-answering-phone`, and `/`.

Canonicals in `src/components/SEO.tsx` all specify the no-slash form; Google indexed the
trailing-slash form anyway, meaning the canonical is being overridden by what the server serves.
23 indexed URLs where there should be 13.

### 4. The `/what-to-do` template tripped duplicate filtering — DILUTING

Twelve pages, same template, same launch date (2026-05-17). Three earn impressions; nine earn zero.
Google treats *mom / dad / elderly mother / grandma / grandpa* not answering the phone as one intent
and picked representatives semi-arbitrarily — keeping *elderly father* and *grandpa* while dropping
the higher-volume *mom*.

This is the risk `pSEO.md` itself flagged as "#1 flagged risk". The content is genuinely
differentiated (1,000–1,300 words each, hand-written per relationship); it is still too close at the
query level.

### 5. The articles are the only thing working — and get no clicks — WORKING

The three visible `/what-to-do` pages account for **333 impressions, 38% of all site visibility**, at
average position 8.6 (page one). Everything else ranks 50s–80s.

But 333 impressions → 1 click = 0.3%, against ~2% expected at that position. Position 8–9 on a "my
parent isn't answering" query sits below an AI Overview and a People Also Ask block. Titles also
closely match competing results. Highest-leverage CTR work available.

### 6. Desktop ranks 3× worse than mobile — DILUTING

Mobile 529 impressions at pos 6.93; desktop 338 at pos 23.21. Worth confirming desktop CWV and
layout rather than assuming.

---

## 4. Page-level data

Pages that earned impressions (URL variants merged):

| Page | Impr. | Clicks |
| --- | ---: | ---: |
| `/` | 479 | 11 |
| `/what-to-do/elderly-father-not-answering-phone` | 138 | 1 |
| `/what-to-do/teenage-daughter-not-answering-phone` | 135 | 0 |
| `/pricing` | 128 | 0 |
| `/terms` | 64 | 1 |
| `/what-to-do/grandpa-wont-pick-up` | 60 | 0 |
| `/privacy` | 41 | 1 |
| `/support` | 34 | 0 |
| `/compare/daily-ok-vs-mobilehelp` | 23 | 0 |
| `/dmca` | 19 | 2 |
| `/elderly-care` | 17 | 0 |
| `/child-safety` | 7 | 0 |
| `/blog` | 6 | 0 |

`/terms`, `/privacy` and `/dmca` have earned more clicks (4) than every commercial page combined (0).

**Zero impressions (25):** all three cornerstone pages; nine of ten `/compare/*`; nine of twelve
`/what-to-do/*`; plus `/compare`, `/what-to-do`, `/accessibility`, `/cookies`.

Note: prerendering itself is **working correctly**. Verified by local build — unique titles, unique
canonicals, 1,000–1,560 words of real content per page. The zero-impression pattern is an authority
verdict, not a rendering bug.

---

## 5. The keyword export is aimed at the wrong product

All 166 keywords bucketed:

| Cluster | Keywords | Volume/mo | Avg. competition | Avg. top-of-page bid |
| --- | ---: | ---: | ---: | ---: |
| GPS / tracker hardware | 126 (76%) | 65,100 | **90** | $3.45 |
| Check-in / welfare check | 33 | 3,000 | **33** | **$5.90** |
| Other | 7 | 300 | 79 | $2.40 |

The tracker cluster has 21× the volume, 3× the competition, and pays **40% less per click** — a
commodity race against Amazon listings and affiliate review sites. Daily OK has no GPS, no tracker,
no wearable, and says so on the homepage. Searchers for `gps tracker for elderly` have already
decided they want to *track* a person; our entire pitch is the refusal to do that.

The check-in cluster is the inverse shape: **low competition, high bid** — advertisers value the
clicks and few compete. That is the strongest signal in the file, and it sits in the 20% of the
export easily skipped past.

**Honest constraint:** the whole category is ~3,000 searches/month. Ranking first for all 33 terms
yields a few hundred clicks/month. Worth having; not a growth plan. Growth has to come from the
anxiety *around* the category — where `/what-to-do` already reaches page one.

---

## 6. Strategy: three shifts

1. **Stop selling the category, start answering the panic.** Our own data ran the experiment:
   commercial category pages sit at 52–88 with zero impressions; problem-moment articles sit at 8.6
   with 38% of all visibility. Nobody wakes up wanting a "daily check-in app" — they wake up because
   mom didn't pick up. Commercial pages become the destination we link *to*, not the pages we rank.

2. **Take the welfare-check cluster, which is completely uncovered.** `elderly welfare check`,
   `elderly wellness check` and `wellness check on elderly` are 500/mo *each* at competition index
   6–13 with bids of $5.46–6.18 — the best value-to-difficulty ratio in the file. These phrases
   appear as passing mentions in eight source files and **no page targets them**. SERP is Griswold,
   Elder Guru, AgingCare, LegalClarity and a competitor blog — beatable. Our unique angle: everyone
   explains how to *request* a welfare check; we can also credibly explain how to never need one.

3. **Earn authority — we have none.** Position 52–88 with correct pages is a trust verdict; more
   content does not change it. "Best tools for long-distance caregiving" roundups name Snug Safety,
   CarePredict and MedMinder, never Daily OK. ~5–7m Americans are long-distance caregivers and those
   roundups are how they shop. Ten listings beat ten more articles.

### Explicitly do not

- Chase tracker keywords — wrong product, unwinnable, hostile intent.
- Publish more `/what-to-do` variants — nine of twelve are already filtered.
- Build city/state pages (pSEO templates #2, #4) until something ranks. Thin location pages on a
  zero-authority domain are the fastest route to a manual action.
- Write anything before fixing the plumbing — posts published today are invisible by construction.

---

## 7. Target terms

### Tier 1 — welfare-check hub (build first; ~1,800/mo, competition 0–24, bids $5.46–7.32)

| Keyword | Vol/mo | Comp. | Top bid |
| --- | ---: | ---: | ---: |
| elderly welfare check | 500 | 6 | $6.18 |
| elderly wellness check | 500 | 13 | $5.46 |
| wellness check on elderly | 500 | 13 | $5.46 |
| check on elderly / check on the elderly | 100 | 16 | $7.32 |
| wellness check elderly | 50 | 16 | $6.14 |
| senior citizen wellness check | 50 | 24 | $6.05 |
| senior welfare check | 50 | 3 | — |
| anonymous welfare check on elderly | 50 | 3 | — |
| social services welfare check for elderly | 50 | 7 | — |
| welfare check elderly / on elderly person | 100 | 0 | — |
| senior citizen welfare check | 50 | 2 | — |
| police welfare check on elderly | 50 | — | — |

**Build as:** one deep pillar at `/welfare-check-on-elderly-parent` — what a welfare check is, exactly
what to say when calling, what happens when police arrive, cost, what to do if they find nothing —
then the prevention argument. Three or four supporting pages for the anonymous / social-services /
police angles. Q&A schema throughout; these queries carry AI Overviews.

### Tier 2 — service intent (~500/mo; highest bids in the file)

| Keyword | Vol/mo | Comp. | Top bid |
| --- | ---: | ---: | ---: |
| senior check in service | 50 | 58 | $7.29 |
| service to check on elderly | 50 | 58 | $7.29 |
| daily check in for seniors | 50 | 48 | $6.96 |
| daily check in service for seniors | 50 | 35 | $5.85 |
| elderly check in service | 50 | 65 | $5.49 |
| best daily check in service for seniors | 50 | 58 | $4.42 |
| daily check in calls for seniors | 50 | 38 | $3.69 |
| check in calls for seniors | 50 | 52 | — |
| senior daily check in service | 50 | 71 | $3.53 |
| elderly check in app | 50 | 29 | — |
| app to check on elderly | 50 | 50 | — |

**The nuance:** most say *service* and *calls* — searchers picture a human phoning their mother daily
at $30–70/mo. Nobody has written the honest comparison: telephone reassurance service vs app, what
each costs, who each suits, when a volunteer calling programme is genuinely better. Write it fairly
and it earns the cluster and the links.

### Tier 3 — the "won't wear it" wedge (unvalidated volume; near-zero competition, high intent)

- `mom won't wear medical alert`, `elderly parent refuses medical alert`
- `medical alert without pendant`, `medical alert that isn't a necklace`
- `alternative to life alert for someone who won't wear it`
- `how to check on elderly parent without being annoying`
- `check on mom without her feeling watched`, `non-invasive way to monitor elderly parent`
- `elderly parent doesn't want a caregiver`, `mom says she's fine but I'm worried`

These searchers have already rejected the competitors' entire product shape.

### Tier 4 — new problem-moments (distinct intents, not more phone variants)

- `how often should you check on an elderly parent` — snippet-shaped, currently answered by forums
- `who to call to check on an elderly person`
- `how to check on an elderly neighbor` — several neighbour variants at competition 0 in the export
- `what to do if you can't reach your elderly parent`
- `elderly parent won't answer the door`
- `how to get someone to check on my mom in another state`
- `signs your elderly parent shouldn't live alone` — high volume, assisted-living lead-gen dominated;
  we offer the step *before* moving them
- `how to stop worrying about elderly parents`

### Tier 5 — fix the brand terms

`dailyok`, `daily ok`, `ok daily` and `day ok` should resolve to us as clearly as possible — but see
the correction in §2: the name is contested (both App Store variants taken, `dailyok.com` owned by
someone else), so **position 1 is likely unattainable and should not be a target**. What is winnable
is disambiguation: making sure Google knows which "Daily OK" we are, and recovering the 35
impressions bleeding to `daily keeper`, which is simple confusion rather than a rival claim. Fix via
tightened `Organization` / `WebSite` schema with `alternateName` (done in US-WEB012) and consistent
naming across surfaces. Note that the App Store listing name cannot be changed to match the site
exactly — it must stay unique store-wide.
Note the `wellvo` / `Daily OK` / `dailyok.net` split documented in `CLAUDE.md` is a live
entity-consolidation risk if wellvo ever gets a public surface.

---

## 8. Order of work

**Week 1 — unblock.** Nothing published counts until this is done.
- Prerender blog posts in `+onBeforePrerenderStart.ts` from published Supabase slugs at build time;
  drop the `/blog/* / 200` rewrite. Prerender `/blog`'s post list so links exist in the HTML.
- Pick one URL form, verify which returns 200, make canonical + sitemap + internal links agree; 301
  the other.
- Link the three cornerstone pages from the homepage body and every `/what-to-do` page, in context.
- Fix the brand SERP.

**Weeks 2–4 — build the welfare-check hub.** Pillar + 3–4 supporting pages, Q&A schema, each linking
to `/daily-check-in-app-for-seniors` with prevention as the bridge.

**Weeks 2–6 (parallel) — rescue what ranks.** Merge the nine zero-impression `/what-to-do` variants
into the three Google selected and 301 the rest. Rewrite titles/metas to beat an AI Overview rather
than match competing results. Put the "first 30 minutes" checklist first on the page for snippet
capture.

**Ongoing — citations.** Get into long-distance-caregiving and check-in-app roundups. Participate in
the AgingCare and Reddit threads ranking page one for our category. Publish one piece of original
data (e.g. missed-check-in timing across our own user base) — that gets cited rather than linked to
reluctantly.

**Hold — city / state / condition pages** (pSEO templates #2, #4, #5) until the welfare-check hub is
on page one.

---

## 9. What to expect

Fixing the plumbing gets the existing 38 pages competing at all; expect impressions to move
materially within 6–8 weeks. The welfare-check hub is the first asset with a genuine shot at page
one, 3–5 months from publication.

**The metric to watch is not clicks.** It is **how many of the 38 pages have any impressions at
all** — today 13. If that is not above 30 in two months, the plumbing fixes did not take and nothing
downstream will work.

---

### Caveats

Volume and competition figures are Google's own bucketed estimates; read as bands, not counts.
Tier 3 and Tier 4 keywords are not in the export — they are proposed from SERP inspection and product
differentiators, so their volumes are unvalidated until pulled. The live site could not be fetched
from the analysis environment (egress-blocked), so trailing-slash serving behaviour is inferred from
GSC's indexed URLs and should be confirmed against production before the 301s are written.
