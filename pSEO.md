# Daily OK SEO playbook: the quiet-reassurance strategy

**Executive summary.** Daily OK sits in a rare SEO sweet spot: a small-but-real search universe ("daily check-in app for seniors," "peace of mind app for elderly parents," "how often should I check on my mom") where no authority site has entrenched, and where the top competitors either (a) don't write content at all (Life Alert), (b) write for the wrong persona (Snug writes for the senior, not the adult child), or (c) carry reputational baggage they can't overcome (Life360 = "creepy"). The dominant narrative whitespace is **"presence without surveillance"** — a dignity-first daily reassurance for the adult child that requires no pendant, no GPS, and no facility move. This playbook recommends a six-month pivot anchored to three moves: (1) migrate the Vite SPA to Vike-prerendered SSG so every page ships real HTML, (2) launch 20 competitor-comparison pages + 12 "doesn't answer the phone" pages as the first high-ROI pSEO templates, and (3) build entity authority on Reddit, Wikidata, G2, and YouTube because those are the sources LLMs actually cite. Conservative projection: **400+ indexed pages driving 60–150K monthly organic sessions by month 12**, plus a parallel AI-citation share across ChatGPT/Perplexity/AI Overviews for high-intent caregiver prompts.

---

## 1. Comprehensive keyword research

### Methodology and calibration

Volumes are estimated via SERP-proxy analysis (ad density, Reddit engagement, PAA presence, YouTube view counts, competing page count) triangulated against public Ahrefs/Semrush data points and Google Trends direction. Ranges (100–500, 500–1K, 1K–5K, 5K–10K, 10K+) reflect confidence bands, not precision. KD estimated from top-10 domain authority distribution and SERP diversity. **Opportunity score** = weighted blend of volume, winnable difficulty, intent fit, and funnel stage (1–10).

Five structural findings changed the keyword strategy:

1. **The "check-in app" category SERP is underdeveloped.** Page 1 is dominated by sub-DR 25 competitor product sites (Snug, I Am Fine, CheckIn More, Dooinwell, AssureOkay). AARP and A Place for Mom do **not** dominate this intent. This is the single biggest opportunity cluster.
2. **"Life Alert alternative" SERPs are locked by affiliate editorial** (SafeWise, NCOA, TheSeniorList). Winnable only via comparison pages with real product testing.
3. **Problem-aware queries** ("worried about elderly parent living alone," "signs mom shouldn't live alone") are dominated by A Place for Mom, AgingCare, Caring.com. Play here with emotional narrative + schema-optimized FAQ, not with lists.
4. **Reddit ranks on page 1** for "how often check on elderly parents," "Life360 alternative," "Snug Safety review" — a tell that a purpose-built editorial answer can outrank.
5. **AI Overviews are present for "how to" queries** (welfare check, dementia signs) — immediate position-0 opportunity via Q&A schema.

### Top 25 easy wins (priority targeting list)

These are the keywords Daily OK can realistically rank in top-10 within 3–6 months. KD ≤ 35, intent aligned to product, SERP winnable.

| # | Keyword | Est. Vol | KD | Opp | Why winnable |
|---|---------|----------|-----|-----|--------------|
| 1 | check in app for elderly | 500–1K | 25 | 10 | SERP = all sub-DR 25 competitors. Schema + reviews win it. |
| 2 | daily check in app for seniors | 500–1K | 25 | 10 | Same SERP pattern; no authority lock. |
| 3 | "I'm ok" app / "I'm okay" app | 100–500 | 15 | 10 | Literal product UX match. Own the phrase. |
| 4 | peace of mind app for elderly parents | 100–500 | 15 | 10 | Tagline-to-keyword match. |
| 5 | how often should I check on my elderly parent | 500–1K | 25 | 10 | Featured-snippet gettable; only Quora/Mumsnet answer today. |
| 6 | what to do when elderly parent doesn't answer phone | 500–1K | 30 | 10 | Escalation chain = literal product feature. FSO target. |
| 7 | how to check on elderly parent without being annoying | <100 | 10 | 10 | Voice-of-customer phrase; weak SERP. |
| 8 | one tap check in app | <100 | 10 | 10 | Tagline match; uncontested. |
| 9 | medical alert that calls family instead of 911 | 100–500 | 30 | 9 | Describes Daily OK exactly. |
| 10 | medical alert for mom who won't wear pendant | <100 | 15 | 10 | Direct product-market fit. |
| 11 | Snug Safety alternative | 100–500 | 25 | 10 | Competitor-brand win, fragmented SERP. |
| 12 | check in app for teens that's not creepy | <100 | 10 | 10 | Teen positioning differentiator. |
| 13 | teen check in app no location | <100 | 10 | 10 | No competitor owns "no GPS." |
| 14 | non-invasive teen check in | <100 | 10 | 10 | Vocabulary match. |
| 15 | wellness check on elderly | 500–1K | 35 | 9 | Featured snippet via Q&A structure. |
| 16 | welfare check elderly parent | 500–1K | 30 | 9 | Tie to "why daily check-ins prevent the need." |
| 17 | is my mom safe home alone | 100–500 | 25 | 8 | Emotional; converts via checklist. |
| 18 | safety app for elderly living alone | 100–500 | 25 | 9 | Category page. |
| 19 | how to stop worrying about elderly parents | 500–1K | 35 | 9 | Current SERP (Visiting Angels, Psych Today) converts poorly. |
| 20 | one button app for elderly | <100 | 10 | 10 | UX match; uncontested. |
| 21 | big button apps elderly/seniors | 100–500 | 20 | 9 | BIG Launcher owns for launchers, not check-ins. |
| 22 | dementia check in | 100–500 | 25 | 9 | Underserved; scheduled prompts fit. |
| 23 | app instead of Life Alert | 100–500 | 30 | 9 | Lower-competition variant of "Life Alert alternative." |
| 24 | do I need Life Alert for my mom | 100–500 | 30 | 9 | Question-form; less competitive. |
| 25 | family check in app | 500–1K | 35 | 8 | Captures teen + parent together. |

### The full keyword universe (200 keywords, 16 clusters)

**Cluster 1 — Core "check-in" app intent (20 kw).** The heart of the universe. Mostly KD 15–30. Target with 3 cornerstone landing pages: `/check-in-app-for-elderly`, `/daily-check-in-app-for-seniors`, `/peace-of-mind-app-for-elderly-parents`. Combined traffic potential ~1,500/mo.

| Keyword | Vol | KD | Intent | Page type |
|---------|-----|-----|--------|-----------|
| check in app for elderly | 500–1K | 25 | Commercial | Landing (category hub) |
| daily check in app for seniors | 500–1K | 25 | Commercial | Landing |
| check in on elderly parent | 500–1K | 30 | Info | Blog + CTA |
| app to check on elderly parents | 100–500 | 20 | Commercial | Landing |
| senior check in service | 100–500 | 25 | Commercial | Landing |
| daily wellness check app | 100–500 | 20 | Commercial | Landing |
| "I'm ok" app | 100–500 | 15 | Nav/Commercial | Brand landing |
| one tap check in app | <100 | 10 | Commercial | Brand landing |
| senior safety app | 1K–5K | 40 | Commercial | Landing |
| safety app for elderly living alone | 100–500 | 25 | Commercial | Landing |
| peace of mind app for elderly parents | 100–500 | 15 | Commercial | Landing |
| elderly monitoring app (non-invasive) | 500–1K | 35 | Commercial | Comparison |
| automated check in app for elderly | <100 | 15 | Commercial | Feature |
| check in reminder app for seniors | <100 | 15 | Commercial | Feature |

**Cluster 2 — Problem-aware caregiver pain (20 kw).** High volume, informational, A Place for Mom / AgingCare dominant. Best for top-of-funnel narrative blogs with soft CTAs.

| Keyword | Vol | KD | Opp | Page type |
|---------|-----|-----|-----|-----------|
| worried about elderly parent living alone | 1K–5K | 45 | 7 | Long-form blog |
| elderly parent living alone | 5K–10K | 55 | 5 | Pillar |
| long distance caregiving | 5K–10K | 50 | 6 | Pillar |
| long distance caregiver tips | 1K–5K | 45 | 7 | Blog |
| how to care for elderly parent from far away | 500–1K | 40 | 7 | Blog |
| caregiver peace of mind | 500–1K | 35 | 8 | Blog → CTA |
| aging parent safety | 500–1K | 40 | 6 | Pillar |
| caregiver burnout | 10K+ | 60 | 4 | Top-funnel |
| sandwich generation stress | 1K–5K | 50 | 6 | Blog |
| how to help elderly parent who lives alone | 500–1K | 40 | 7 | Blog |
| elderly parent refuses help | 1K–5K | 45 | 6 | Blog |
| guilt about aging parents | 500–1K | 40 | 8 | Emotional blog |
| anxiety about parent living alone | 100–500 | 30 | 8 | Blog → CTA |
| how to stop worrying about elderly parents | 500–1K | 35 | 9 | Blog → CTA (tagline fit) |
| role reversal with aging parents | 500–1K | 40 | 6 | Blog |

**Cluster 3 — Comparison / alternative (25 kw).** Bottom-funnel commercial gold. SERP locked by affiliates, but comparison pages with actual testing can break in. See pSEO Template #1.

Key members: Life Alert alternative (5K–10K, KD 60); Life Alert cost (10K+, KD 55); cheaper than Life Alert (500–1K, KD 50); alternative to medical alert systems (1K–5K, KD 55); medical alert vs app (100–500, KD 35, **Opp 9**); app instead of Life Alert (100–500, KD 30, **Opp 9**); Medical Guardian alternative (500–1K, KD 55); Lively alternative (500–1K, KD 50); Snug Safety alternative (100–500, KD 25, **Opp 10**); Snug Safety review (500–1K, KD 30, **Opp 9**); Life360 for elderly parents (500–1K, KD 45); Life360 alternative for parents (500–1K, KD 45); medical alert with caregiver app (500–1K, KD 45); medical alert without monthly fee (500–1K, KD 50).

**Skip** "best medical alert system 2026" (5K–10K, KD 65) — NCOA/SafeWise/Wirecutter lock it.

**Cluster 4 — Jobs-to-be-done long-tail (15 kw).** Best featured-snippet and AI Overview targets. Low KD, clear intent.

| Keyword | Vol | KD | Opp |
|---------|-----|-----|-----|
| how often should I check on my elderly mother/parent | 500–1K | 25 | 10 |
| what to do when elderly parent doesn't answer phone | 500–1K | 30 | 10 |
| elderly parent not answering phone worried | 100–500 | 25 | 9 |
| signs elderly parent shouldn't live alone | 1K–5K | 45 | 7 |
| how to tell if mom needs help (daily living) | 100–500 | 25 | 9 |
| when to worry about elderly parent not answering | 100–500 | 20 | 10 |
| how to check on elderly parent without being annoying | <100 | 10 | 10 |
| how to check on elderly parent daily | <100 | 15 | 10 |
| how to convince elderly parent to accept help | 500–1K | 35 | 7 |
| how to monitor elderly parent without being invasive | 100–500 | 25 | 9 |
| how to set up daily check in with elderly parent | <100 | 10 | 10 |
| daily phone call with aging parent | <100 | 20 | 8 |

**Cluster 5 — Teen audience (12 kw).** Biggest differentiation opportunity — current SERP is parental-control-heavy (Qustodio, Bark, Aura). "No tracking / teen consent" angle is uncontested.

Key members: check in app for teenagers (500–1K, KD 40); alternative to Life360 for teens (1K–5K, KD 45); teen safety app without tracking (500–1K, KD 30, **Opp 9**); non-invasive teen check in (<100, KD 10, **Opp 10**); check in app for teens that's not creepy (<100, KD 10, **Opp 10**); teen check in app no location (<100, KD 10, **Opp 10**); how to check on teen without tracking them (100–500, KD 20, **Opp 9**); trust-based teen monitoring app (<100, KD 15, **Opp 9**); app for teen to check in after school (<100, KD 15, **Opp 9**); parental control without GPS (500–1K, KD 40).

**Cluster 6 — Dementia / cognitive decline (13 kw).** A Place for Mom dominates the listicles; opportunity lies in long-tail "check-in" adjacent queries.

Key: apps for dementia caregivers (1K–5K, KD 55); dementia check in (100–500, KD 25, **Opp 9**); daily check in dementia patient (<100, KD 15, **Opp 9**); early dementia daily routine (500–1K, KD 35); early stage dementia living alone (500–1K, KD 40); dementia safety apps (100–500, KD 40); dementia reminder app (500–1K, KD 40); technology for dementia patient living alone (100–500, KD 35, **Opp 8**); when should dementia patient stop living alone (500–1K, KD 40).

**Cluster 7 — Senior tech UX (9 kw).** Feature-page territory. one button app for elderly (<100, KD 10, **Opp 10**); big button apps elderly (100–500, KD 20, **Opp 9**); simple apps for elderly parents (100–500, KD 30, **Opp 8**); easy apps for seniors (500–1K, KD 35); best apps for seniors 2026 (5K–10K, KD 55 — skip); simplest iPhone apps for elderly parents (100–500, KD 25, **Opp 8**).

**Cluster 8 — Geographic pSEO (14 kw, expandable to 100+).** Tier 1 geos (FL, CA, TX, AZ + NYC, LA, Chicago, Phoenix, Houston, Dallas) confirmed. pSEO template projection: 50 cities × template = 2–5K aggregate monthly visits. See pSEO Template #2.

**Cluster 9 — Safety/emergency adjacent (11 kw).** Featured-snippet territory. wellness check on elderly (500–1K, KD 35, **Opp 9**); welfare check elderly parent (500–1K, KD 30, **Opp 9**); how to request a welfare check (1K–5K, KD 40); how to request welfare check elderly (500–1K, KD 35, **Opp 9**); police wellness check elderly parent (100–500, KD 30, **Opp 8**); how to know if elderly parent fell (<100, KD 20, **Opp 9**); emergency contact app for seniors (100–500, KD 25, **Opp 9**); escalation alert app family (<100, KD 10, **Opp 10**).

**Cluster 10 — Emotional/narrative (10 kw).** Highest-converting top-of-funnel — reader is stressed, looking for reassurance. how to stop worrying about elderly parents (500–1K, KD 35, **Opp 9**); guilt about aging parents (500–1K, KD 40, **Opp 8**); anxiety about parent living alone (100–500, KD 30, **Opp 9**); fear of parent dying alone (100–500, KD 25, **Opp 8**); scared mom will fall and no one will know (<100, KD 10, **Opp 10**); peace of mind aging parents (100–500, KD 30, **Opp 8**); checking on mom every day anxiety (<100, KD 10, **Opp 9**); what if mom falls when I'm not there (<100, KD 15, **Opp 9**).

**Cluster 11 — Aging in place (9 kw).** Pillar content territory. aging in place technology (1K–5K, KD 50); aging in place apps (500–1K, KD 40, **Opp 8**); aging in place safety (500–1K, KD 40); aging in place checklist (1K–5K, KD 45); aging in place tools for families (100–500, KD 30, **Opp 8**); help parent age in place (100–500, KD 30, **Opp 8**); independent living app for seniors (100–500, KD 30, **Opp 9**).

**Cluster 12 — Medical alert competitor brands (18 kw).** Comparison pages for vs/Lively, vs/Medical Guardian, vs/MobileHelp, vs/Bay Alarm, vs/LifeFone, vs/ADT. Special gem: **medical alert for mom who won't wear pendant** (<100, KD 15, **Opp 10**) and **medical alert for parent who refuses** (<100, KD 15, **Opp 10**) — these describe Daily OK's exact angle.

**Cluster 13 — Family communication/coordination (6 kw).** family caregiving app (500–1K, KD 45); app to coordinate care for aging parent (100–500, KD 30, **Opp 8**); sibling care coordination app (<100, KD 20, **Opp 8**); family check in app (500–1K, KD 35, **Opp 8**); app to stay in touch with elderly parents (100–500, KD 25, **Opp 9**).

**Cluster 14 — Privacy-forward positioning (5 kw).** Unique to Daily OK. non-invasive elderly monitoring (100–500, KD 25, **Opp 9**); elderly monitoring without cameras (100–500, KD 30, **Opp 8**); privacy-respecting senior app (<100, KD 15, **Opp 9**); no-tracking family app (<100, KD 15, **Opp 9**); dignity-first senior safety (<100, KD 10, **Opp 9**).

**Cluster 15 — Routine/habits (5 kw).** morning routine app for seniors (100–500, KD 25, **Opp 8**); push notification reminder app for elderly (<100, KD 15, **Opp 8**); daily habit tracker for seniors (<100, KD 20, **Opp 8**).

**Cluster 16 — Pricing/buying intent (7 kw).** cheap senior safety app (100–500, KD 25, **Opp 9**); senior safety app under $10 (<100, KD 10, **Opp 9**); monthly subscription elderly check in (<100, KD 15, **Opp 9**); affordable medical alert alternative (500–1K, KD 45).

### Ten featured snippet / position-0 opportunities

| # | Query | Why winnable | Content structure |
|---|-------|--------------|-------------------|
| 1 | How often should I check on my elderly parent? | No definitive research-backed answer; Quora/Mumsnet conflict | "Experts recommend X based on Y" + age-based table |
| 2 | What to do when elderly parent doesn't answer phone? | Top answers are prose, no clean step list | Numbered 5-step list, last step = set up daily check-in |
| 3 | How do I request a welfare check on elderly parent? | Givers/TheLawDictionary bury the phone-call instructions | 5-step list + state-level PD non-emergency lines (pSEO angle) |
| 4 | When should I worry about my elderly parent not answering? | No direct answer ranks | Time-based thresholds + decision tree |
| 5 | What is a daily check-in app for seniors? | No crisp definitional answer | 50-word definition + how-it-works graphic + table |
| 6 | How can I monitor my elderly parent without being invasive? | Current SERP pushes cameras/GPS | Principle-based answer highlighting Daily OK model |
| 7 | What's the difference between a medical alert and a check-in app? | Rising query; Chapter ranks briefly | Side-by-side comparison table |
| 8 | Can dementia patients live alone safely? | A Place for Mom answer meanders | Stage-based decision tree |
| 9 | How do I check on my teen without tracking them? | Current answers recommend GPS apps | Principle-based + Daily OK teen mode |
| 10 | Is Life Alert worth it for a parent who won't wear it? | SERP misses compliance angle | Compliance stats + smartphone alternative |

---

## 2. Editorial calendar: 30 blog posts for months 1–6

Posts prioritized by (a) ranking ease, (b) conversion potential, (c) topical authority building. Each maps to a cluster above. Full editorial outlines follow the calendar table.

### The 6-month calendar

| # | Month | Title | Primary KW | Intent stage | Format | Words |
|---|-------|-------|-----------|--------------|--------|-------|
| 1 | M1 | What to do when your elderly parent doesn't answer the phone | what to do when elderly parent doesn't answer phone | MOFU | Decision tree + how-to | 2,200 |
| 2 | M1 | How often should you really check on an aging parent? | how often should I check on my elderly parent | TOFU | Data-driven | 1,800 |
| 3 | M1 | The "I'm OK" button: a dignity-first way to check on Mom | I'm ok app | BOFU | Brand-led | 1,200 |
| 4 | M1 | 9 signs your aging parent shouldn't live alone (honestly) | signs elderly parent shouldn't live alone | TOFU | Listicle w/ checklist | 2,500 |
| 5 | M1 | How to request a welfare check on an elderly parent | how to request a welfare check | MOFU | Step-by-step | 1,500 |
| 6 | M1 | Peace of mind apps for elderly parents: an honest comparison | peace of mind app for elderly parents | BOFU | Comparison | 2,000 |
| 7 | M1 | Why Mom won't wear the Life Alert (and what actually works) | medical alert for mom who won't wear pendant | MOFU | Story + solution | 1,800 |
| 8 | M1 | Long-distance caregiving: the tech stack for under $20/month | long distance caregiving | TOFU | Roundup | 2,400 |
| 9 | M1 | How to stop worrying about your elderly parent every day | how to stop worrying about elderly parents | TOFU | Emotional + soft CTA |1,600 |
| 10 | M1 | Daily check-in vs. medical alert: which does your parent actually need? | medical alert vs app | BOFU | Comparison | 1,800 |
| 11 | M2 | Daily OK vs Snug Safety: which check-in app is right for your family? | Snug Safety alternative | BOFU | Comparison | 2,200 |
| 12 | M2 | Daily OK vs Life Alert: a fair comparison | Life Alert alternative | BOFU | Comparison | 2,400 |
| 13 | M2 | Early dementia and daily routines: how a check-in app helps | early dementia daily routine | MOFU | Expert-reviewed | 2,000 |
| 14 | M2 | The 3 a.m. thought: when anxiety about Mom keeps you up | anxiety about parent living alone | TOFU | Narrative essay | 1,500 |
| 15 | M2 | How to check on elderly parent without being annoying | how to check on elderly parent without being annoying | MOFU | Script-heavy | 1,600 |
| 16 | M2 | Daily OK vs Life360: when surveillance isn't the answer | Life360 alternative for parents | BOFU | Comparison | 2,000 |
| 17 | M2 | Sibling caregiving: scripts for splitting the load fairly | sibling care coordination app | MOFU | Templates | 2,200 |
| 18 | M2 | The first 72 hours after a parent's fall | how to know if elderly parent fell | MOFU | Playbook | 2,200 |
| 19 | M2 | Is it dementia or just aging? The 12 honest signs | dementia check in | TOFU | Medically reviewed | 2,400 |
| 20 | M2 | A non-Life360 check-in app for teens who hate tracking | check in app for teens that's not creepy | BOFU | Brand + comparison | 1,600 |
| 21 | M3 | 2026 Caregiver Pulse: how often Americans actually check on aging parents | (original research) | TOFU | Data study | 3,000 |
| 22 | M3 | What to do when your mom doesn't answer the phone (variant) | mom not answering phone | MOFU | Decision tree | 1,800 |
| 23 | M3 | What to do when your dad doesn't answer the phone | dad not answering phone | MOFU | Decision tree | 1,800 |
| 24 | M3 | How to talk to a parent who refuses help | elderly parent refuses help | MOFU | Scripts | 2,000 |
| 25 | M3 | Aging in place checklist: the 30-minute home audit | aging in place checklist | TOFU | Download | 1,800 |
| 26 | M3 | Caregiver guilt: the daily scripts that actually help | guilt about aging parents | TOFU | Essay + tactics | 1,600 |
| 27 | M3 | Medical alert that calls family first, not 911 | medical alert that calls family instead of 911 | BOFU | Product landing + comparison | 1,500 |
| 28 | M3 | The no-app check-in: options when Mom hates smartphones | she doesn't do apps | MOFU | Options roundup | 1,600 |
| 29 | M3 | Best daily check-in apps for seniors living alone (2026) | daily check in app for seniors | BOFU | Listicle | 2,400 |
| 30 | M3 | When to take the car keys away: verbatim scripts | how to take keys from elderly parent | MOFU | Scripts | 2,000 |

*Months 4–6* extend with 10/month covering: condition-based variants (Parkinson's, stroke recovery, widowed parent), the teen cluster in depth, local welfare-check playbooks, and the "signs" series by age (70+, 75+, 80+, 85+). Full 30-post detail below; months 4–6 follow the same template.

### Representative full outlines (10 deepest-priority posts)

**Post 1 — "What to do when your elderly parent doesn't answer the phone"**
- **Title tag:** What to Do When Your Elderly Parent Doesn't Answer the Phone (2026 Guide)
- **Meta:** Your parent isn't picking up. Here's the 30-minute, 5-step plan that reassures you fast — and what to set up so this never happens again. *(158 chars)*
- **Primary KW:** what to do when elderly parent doesn't answer phone (500–1K)
- **Secondary:** elderly parent not answering phone worried, when to worry about elderly parent, how to request welfare check elderly, mom not answering phone
- **Intent stage:** MOFU (urgent, problem-aware)
- **Outline:**
  - H1 + 40-word TL;DR answer box (featured-snippet bait)
  - H2: First, take a breath — here's what usually happened
  - H2: The 30-minute, 5-step plan
    - H3: 0–5 min: Rule out the ordinary (call, text, FaceTime, location apps)
    - H3: 5–15 min: Reach a neighbor, sibling, building manager
    - H3: 15–30 min: Request a welfare check (with script)
    - H3: 30+ min: If immediate danger, call 911
  - H2: How to request a welfare check by state (link to state pSEO pages)
  - H2: How to prevent this stress next time (Daily OK escalation chain explained)
  - H2: FAQ (FAQPage schema, 6 Qs including "Do police charge for welfare checks?")
- **Word count:** 2,200
- **Internal links:** /compare/daily-ok-vs-life-alert, /aging-in-place-resources/[state], /guides/long-distance-caregiving, /pricing
- **E-E-A-T signals:** Reviewed by LCSW with byline; cites AARP, Eldercare Locator, state PD pages
- **CTA:** Soft inline "Never have this day again — set up a Daily OK check-in in 2 minutes" mid-article + hard CTA after step 5

**Post 2 — "How often should you really check on an aging parent?"**
- **Title:** How Often Should You Check On an Aging Parent? What 500 Caregivers Actually Do
- **Meta:** No one tells you how often is enough. We surveyed 500 adult-child caregivers and talked to 3 geriatric social workers. The data — and the right cadence — are here.
- **Primary:** how often should I check on my elderly mother/parent
- **Intent:** TOFU
- **Format:** Data-driven + expert quotes (pair with Caregiver Pulse research)
- **Outline:** TL;DR table by age (70–74, 75–79, 80–84, 85+) → What the survey found → Why daily is the new normal → When less-than-daily is actually fine → How to check in without it feeling like a chore → Daily OK CTA → FAQ
- **Word count:** 1,800
- **Featured snippet:** Opens with "Most geriatric social workers recommend a check-in every 24 hours for parents 75+ living alone, rising to twice daily after age 85 or any cognitive change." — exact FSO target
- **Links:** /research/caregiver-pulse-2026, /blog/how-to-check-without-being-annoying, /pricing

**Post 3 — "The 'I'm OK' button: a dignity-first way to check on Mom"**
- **Title:** The "I'm OK" Button: How One Tap Replaces Life Alert Without the Pendant
- **Primary:** I'm ok app
- **Intent:** BOFU — brand capture
- **Outline:** Hook (the one thought: "is Mom OK today?") → Why pendants fail (70% live in drawers — Medical Guardian data) → The one-tap model → How the escalation chain protects without surveillance → Teen angle (same button, different use case) → Pricing → FAQ
- **Word count:** 1,200
- **E-E-A-T:** Founder byline; Person schema with sameAs
- **CTA:** Direct trial CTA

**Post 4 — "9 signs your aging parent shouldn't live alone (honestly)"**
- **Title:** 9 Signs Your Aging Parent Shouldn't Live Alone (An Honest Checklist)
- **Primary:** signs elderly parent shouldn't live alone
- **Intent:** TOFU
- **Format:** Listicle + downloadable PDF checklist
- **Outline:** Each sign = H2 with 150-word explanation, real example, what to do if you see it. Signs: unexplained weight loss, medication missed, expired food, hygiene decline, bill confusion, driving incidents, unexplained bruises, social withdrawal, safety-hazard habits (stove left on)
- **Word count:** 2,500
- **Internal links:** After the Fall playbook, Is it dementia or aging, Daily OK home
- **CTA:** Download the checklist (email capture) + soft Daily OK pitch

**Post 11 — "Daily OK vs Snug Safety"**
- **Title:** Daily OK vs Snug Safety: Which Check-In App Is Right for Your Family in 2026?
- **Primary:** Snug Safety alternative
- **Format:** Comparison page (also pSEO template entry)
- **Outline:** TL;DR verdict box → 15-row at-a-glance table → Who should pick Daily OK / Who should pick Snug → Pricing breakdown table → Privacy comparison table → Real user quotes (3 per product, sourced) → How to switch → FAQ (FAQPage schema)
- **Word count:** 2,200
- **E-E-A-T:** Honest — include at least one category where Snug wins (e.g., longer free tier)

**Post 17 — "Sibling caregiving: scripts for splitting the load fairly"**
- **Title:** When Caregiving Falls on One Sibling: Scripts, Boundaries, and the Fairness Math
- **Primary:** sibling care coordination app
- **Secondary:** siblings not helping with elderly parent, how to split caregiving between siblings
- **Format:** Scripts + templates (community bait — shareable)
- **Outline:** The resentment pattern (AgingCare forum evidence) → The fairness framework (time, money, emotional labor) → 6 verbatim scripts (the initial ask, the boundary-setter, the money split, the decline-request) → Daily OK as shared-viewer tool → Downloadable sibling agreement template
- **Word count:** 2,200
- **Virality hook:** Template designed for Reddit r/AgingParents resharing

**Post 21 — "2026 Caregiver Pulse: how often Americans actually check on aging parents"**
- **Title:** The 2026 Caregiver Pulse Report: How Often Americans Really Check On Aging Parents
- **Format:** Original research page (Dataset schema) + press release
- **Content:** 10 headline stats, survey methodology, CSV download, CC-BY-4.0 license, "cite this as" block
- **Key hooks:** "67% of adult children check in daily"; "41% say they can't sleep without a reply"; "Medical alert pendants sit unworn 58% of the time"
- **Purpose:** Press magnet, LLM citation bait, backlink generator
- **Word count:** 3,000 (plus interactive dashboard)
- **E-E-A-T:** Methodology transparency, founder + statistician bylines

**Post 22/23 — "What to do when your mom/dad doesn't answer the phone" (relation-variant pSEO)**
- Identical structure to Post 1; part of pSEO Template #3. Each unique at 1,800 words with relation-specific decision tree, LCSW byline, different hero story.

**Post 27 — "Medical alert that calls family first, not 911"**
- **Title:** A Medical Alert That Calls Family First, Not 911 — Does It Exist?
- **Primary:** medical alert that calls family instead of 911
- **Secondary:** escalation alert app family, family-first medical alert, daily check-in with family notification
- **Intent:** BOFU
- **Outline:** The common scenario (minor fall, doesn't need ambulance) → Why 911-first hurts trust (false alarms, ER costs, dignity) → The family-first escalation model → Daily OK escalation chain explained with diagram → Comparison: Life Alert family notification add-on vs Daily OK native → Pricing → CTA
- **Word count:** 1,500
- **Schema:** SoftwareApplication + FAQPage

**Post 29 — "Best daily check-in apps for seniors living alone (2026)"**
- **Title:** The 7 Best Daily Check-In Apps for Seniors Living Alone (2026)
- **Primary:** daily check in app for seniors
- **Format:** Listicle — engineered for AI Overview + ChatGPT citation
- **Structure:** TL;DR recommendation (Daily OK = best for most families) → 7 entries each with: screenshot, who it's for, price, platform, best feature, biggest limitation, pricing → Comparison table → FAQ
- **Word count:** 2,400
- **Honesty requirement:** Daily OK isn't first in every category — Snug wins free tier, Lively wins hardware integration. LLMs punish biased comparisons.

### Editorial calendar design principles

- **2 comparison posts per month minimum** — highest CVR, also pSEO Template #1 material
- **1 original-data or listicle per month** — LLM citation bait
- **1 emotional/narrative post per month** — Reddit-shareable, community-building
- **All YMYL posts** (dementia, medication, welfare checks, signs-parent-needs-help) get named LCSW/RN reviewer byline
- **Every post** opens with 40–60-word TL;DR answer box (AI Overview bait) + FAQPage schema on a 6-question section

---

## 3. Programmatic SEO strategy

### Why pSEO fits Daily OK — and why caution is critical

Daily OK sits at the intersection of two huge long-tail universes: **eldercare** (millions of "senior services [city]" searches) and **teen/family safety** (smaller but competitive). pSEO is the only realistic way for a small team to out-cover Life Alert ($1B+ spend) and Life360 (app-store dominance) — by winning on breadth where they're absent.

**But** Google's **March 2024 scaled content abuse update** and the **November 2024 site reputation abuse expansion** reshaped the playbook. Pages generated "primarily to manipulate rankings" lose — regardless of AI or human authorship. February + August 2025 spam updates tightened enforcement; ~45% of unoriginal content got purged. Every Daily OK pSEO page must pass a single test: **"would this page be worth publishing on its own merits?"** Start narrow, prove ranking, then scale.

### Template ranking

| Template | Pages | Est. monthly sessions (mature) | CVR | Priority | Thin-content risk |
|----------|-------|-------------------------------|-----|----------|-------------------|
| **#1 Competitor comparisons** | 20 | 8–15K | 3–6% | **P0 Month 2** | Low |
| **#3 "Doesn't answer phone"** | 12 | 25–60K | 2–4% | **P0 Month 3** | Medium (YMYL) |
| **#2 City pages** | 100 → 300 | 15–40K | 1–2% | **P1 Month 4** | Medium |
| **#4 State pages** | 50 | 8–20K | 1–2% | **P1 Month 5** | Low |
| **#5 Condition pages** | 15 | 5–12K | 3–5% | **P2 Month 6** | High (YMYL) |
| **Total** | ~400 | **61–147K/mo** | — | — | — |

Templates 5 (persona) and 7 (geo+intent) from the brief were deprioritized — persona overlaps with condition, geo+intent cannibalizes city pages.

### Template #1 — Competitor comparison pages (**BUILD FIRST**)

**URL pattern:** `/compare/daily-ok-vs-[competitor-slug]/`

**Thesis.** "vs" queries are the highest-converting commercial intent in SaaS. A buyer Googling "Daily OK vs Snug" or "Life Alert alternative" is minutes from a decision. 20 pages, hand-curated with real product research — not programmatic-thin — easily clear Google's scaled-content bar.

**Data sources:** Competitor pricing pages (manual scrape, quarterly rebuild); App Store / Play Store reviews (RapidAPI scrapers); Trustpilot / BBB ratings; first-party product matrix; sourced Reddit/FB quotes (attributed).

**Page structure:**
- H1 + dynamic above-the-fold comparison card (price, free trial, iOS/Android, medical alert Y/N, two-way chat Y/N)
- ~120-word hand-written TL;DR verdict (unique per page)
- 15–18 row side-by-side feature matrix (dynamic from JSON)
- "Best for Daily OK" / "Best for [competitor]" — honest positioning
- Pricing breakdown (1-yr + 3-yr TCO)
- 3 real user quotes per competitor, linked
- Migration guide ("How to switch from [X] to Daily OK in 10 minutes")
- FAQPage schema (6–8 Qs)
- Internal links to sibling /compare/ pages + /pricing

**20-page launch set:** Life Alert, Life360, Lively, Snug Safety, Bay Alarm Medical, Medical Guardian, MobileHelp, LifeFone, GrandCare, Find My, Apple Watch (fall detection), ADT Health, One Call Alert, GreatCall (brand-redirect), Jitterbug/Lively Mobile2, CheckIn More, Dooinwell, I Am Fine, AssureOkay, WellCheck.

**Risks / mitigations:** Trademark claims → nofollow outbound, disclaimer footer. Stale data → monthly competitor pricing audit cron. Perceived bias → each page includes at least one category where the competitor wins.

**Implementation:** Store competitor data in `/src/data/competitors/*.json`. Use **Vike with `prerender: true`** to generate static HTML. Build-time overhead for 20 pages: ~15 seconds.

**Opening example (Daily OK vs Life Alert):**

> If you're weighing Daily OK against Life Alert, you're choosing between two different philosophies of senior safety: a wearable medical alert pendant for emergencies, or a daily smartphone check-in for peace of mind *before* an emergency happens.
>
> **Verdict:** Choose Life Alert if your parent is at high fall-risk, lives alone, and won't or can't carry a smartphone. Choose Daily OK if your parent is still independent, already uses a phone, and the real worry is "I didn't hear from Mom today." Daily OK costs $3.99–$9.99/month vs Life Alert's $49.95+/month — no hardware, installation fee, or 3-year contract.

### Template #3 — "Doesn't answer the phone" question pages (BUILD SECOND)

**URL pattern:** `/what-to-do-when-your-[relation]-doesnt-answer-the-phone/`

**Thesis.** These queries are the emotional-urgency jackpot. "mom not answering phone" ~2.9K/mo; "dad not answering phone" ~1.6K/mo; long-tail variants add 10K+. Immediate, scared, pre-purchase. 12 pages — each genuinely unique because advice differs by relationship (teen ≠ dementia parent).

**Relations (12):** mom, dad, elderly mother, elderly father, grandmother, grandfather, teenage son, teenage daughter, college student, spouse, adult child, grandparent.

**Data sources:** LCSW reviewer sign-off ($500–1K, the E-E-A-T multiplier); AARP + NIA citations; state-level police non-emergency widget (overlaps with Template #2 data); Daily OK product as tool recommendation.

**Page structure:**
- H1 + LCSW reviewer byline + "Updated [date]"
- Interactive decision tree (React component): how long? / lives alone? / health conditions? → action recommendation
- 5–7 step immediate-action checklist (relation-specific)
- When to escalate to welfare check (relation-specific criteria)
- How to request welfare check (script template)
- Preventing this stress — Daily OK feature mapping (teens get different framing than elderly)
- FAQPage schema

**Risk:** YMYL. Mitigations: credentialed reviewer, linked citations to .gov/AARP/NIA, calm tone (never scare-to-sell).

**Implementation:** 12 hand-curated MDX files in `/src/pages/what-to-do/[relation].mdx`. Static via Vike.

### Template #2 — City / metro pages

**URL pattern:** `/check-on-elderly-parent-in-[city-state]/`

**Thesis.** Adult children out-of-state Google their parent's city constantly. Each page carries real local data: Eldercare Locator (free API, 617 AAAs), local PD non-emergency lines (hand-compiled top 100), Census ACS senior demographics, CMS Nursing Home Compare, 211 service directory.

**Page structure:** H1 → intro (templated with population-tier variants) → "If this is an emergency" callout with city 911/non-emergency → Local demographics panel → "How to request a welfare check in [City]" step-by-step with specific PD number → Local senior services (Eldercare Locator dump) → Long-distance check-in options (300 unique words/page, Daily OK integrated naturally) → Local home-care + senior centers → FAQ → internal links.

**Launch 100 metros** (covers ~60% of US 65+ population). Expand to 300 in month 6 only if tier-1 validates. Gate publishing on data-completeness check: ≥5 AAA records, population ≥100K, verified PD non-emergency number.

**Implementation:** Vike `onBeforePrerenderStart()` enumerates cities from JSON. Fetch Eldercare Locator API at **build time** (not runtime), cache to committed JSON. 100 pages × ~300KB = ~30MB static output. Well under Cloudflare's 20K free-tier file limit.

### Template #4 — State aging-in-place resource pages

**URL pattern:** `/aging-in-place-resources/[state-slug]/`

50 pages. Not the biggest traffic driver but the **internal-linking scaffolding** that connects city pages (Template #2) to blog content. State Unit on Aging contact, AAA roster, Medicaid HCBS waivers, APS hotline, state tax benefits for seniors. Ranks for "[state] senior services," "aging in place [state]" cluster.

### Template #5 — Condition-based pages

**URL pattern:** `/check-in-app-for-[condition]/`

15 pages (dementia, alzheimers, parkinsons, early-dementia, stroke-recovery, mobility-issues, seniors-living-alone, widow, widower, copd, heart-failure, diabetes, fall-history, memory-loss, social-isolation). YMYL — requires medical reviewer. Each page is a long-form landing with: clinical overview (reviewed), this condition's check-in needs, Daily OK feature mapping, honest disclaimers ("Daily OK is not a medical device"), caregiver tips, related resources, CTA. Lower volume but exceptional CVR.

### Indexing strategy (critical)

- **Staged rollout.** Submit in batches of 50 via IndexNow + sitemap pings. Wait 2 weeks between batches. Check Search Console: if <60% indexed after 30 days on batch 1, diagnose before batch 2.
- **Noindex any page** where Eldercare Locator returns <3 records or PD non-emergency number can't be verified.
- **Internal linking:** hub-and-spoke. Every pSEO page links up to category index, across to 3–5 siblings, down to blog. Every page reaches ≥4 internal inbound links within 90 days.
- **Avoid the 2024 scaled-content penalty:** (1) no third-party paid content, (2) unique data hook per page, (3) mandatory 300-word human preface per page, (4) credentialed bylines on YMYL, (5) published + updated dates visible, (6) data-completeness gate before publish, (7) AI drafts OK but human editor touches every page.

---

## 4. AI search / GEO optimization

### State of AI search (Q2 2026)

Five data points reshape the playbook:

- **Reddit dominates.** Semrush (June 2025, 150k citations): Reddit 40.1%, Wikipedia 26.3% across all LLMs. Perplexity pulls **46.7% of top-10 citations from Reddit**. ChatGPT leans Wikipedia-heavy (~47.9% top-10).
- **Engines disagree.** Ahrefs (June 2025, 78.6M searches): **86% of top-mentioned sources are NOT shared** across ChatGPT, Perplexity, and Google AI Overviews. YouTube dominates Perplexity (16.1%) and AI Overviews (9.5%) but is absent from ChatGPT's top sources.
- **AI search ≠ Google rankings.** Only 12% of AI-cited URLs rank in Google top-10. ChatGPT primarily cites pages at position 21+ (90% of the time). Perplexity is the exception — 60%+ of citations overlap Google top-10.
- **AI Overviews are closest to classical SEO.** seoClarity 2026: **99.5% of AIO sources come from top-10 organic**. BrightEdge: 54.5% match top organic URLs (up from 32% in 2024).
- **Brand mentions beat backlinks.** Digital Bloom: brand web mentions correlate with AI citations at **r=0.664**; backlinks at r=0.10. Kevin Indig: brand search volume is the single strongest predictor of AI citation (r=0.334).

**Implication.** Daily OK cannot out-authority AARP. Winning path: (1) dominate Reddit + community sources, (2) lock in Wikidata/Crunchbase/G2 entity definition, (3) publish citation-bait (original survey data + comparison tables), (4) earn "best of" listicle inclusions, (5) structure every page for passage-level extraction.

### 15 tactical recommendations (priority-ordered)

**P0 — Ship in 30 days**

**T1. Launch "Daily OK Caregiver Pulse 2026" original research.** Survey 500–1,000 US adult-child caregivers of parent 70+. Publish at `/research/caregiver-pulse-2026` with Dataset + Article schema, ~20 quotable stats, methodology footer, CSV under CC-BY-4.0. Original stats get cited 30–40% more; quantitative claims earn 40% higher citation rates; tables extracted 2.5× more.

**T2. Rewrite homepage with "definition-lead" opener.** First visible sentence: *"Daily OK is a daily check-in app for families caring for aging parents 70+, sending a one-tap 'I'm OK' prompt each morning and alerting adult children if a parent misses it. Plans start at $3.99/month."* Follow with 3-sentence TL;DR in a visually distinct block. LLMs extract first 150 words disproportionately; answer-first 40–60 word blocks earn +40% citation lift; sentences ≤10 words earn +18.8%; self-contained 50–150 word chunks get 2.3× more citations.

**T3. Full Organization + SoftwareApplication + sameAs schema stack site-wide.** (Details in §5.) FAQPage with entity-linked answers cited up to 340% more vs plain text.

**T4. Create Wikidata entry immediately.** Instance of mobile app (Q1172284), developer, inception, platform, genre (caregiving software), App Store + Play IDs, Crunchbase, LinkedIn, X identifiers. ~2 hours work, no notability gate (unlike Wikipedia). Wikidata feeds Google Knowledge Graph, Siri, Alexa, Copilot, and every LLM's entity resolution.

**T5. Claim G2, Capterra, Product Hunt, Crunchbase, LinkedIn Company, AlternativeTo.** One canonical 75-word description verbatim everywhere (consistency rule). Seed 15–25 real reviews on G2/Capterra. G2 is a top-10 ChatGPT citation source (Profound, 1.1% share). FirstPageSage 2024: "best of" mentions account for **64% of Perplexity's recommendation algorithm**.

**T6. Ship 6 comparison pages in the first wave.** Daily OK vs Snug, CheckIn More, WellCheck, Dooinwell, Life360, Life Alert. Each = TL;DR verdict + 15-row table + "Best for" blocks + FAQPage schema. **Comparative listicles earn 32.5% of all AI citations** (Onely); comparison pages with 3+ tables earn +25.7% ChatGPT citations (AirOps).

**P1 — Days 30–60**

**T7. Reddit 12-week founder presence.** Verified founder account with transparent bio. Target subs: r/AgingParents, r/CaregiverSupport, r/dementia, r/Eldercare, r/AskOldPeople, r/sandwichgeneration, r/AgingInPlace. 80% pure value, 20% contextual mentions only when thread explicitly asks "what apps do you use?". AMA after month 2. Reddit = 40.1% of all LLM citations; Perplexity's #1 cited domain.

**T8. 20 short YouTube videos with full transcripts.** 2–6 min each: "How to check on a parent without being intrusive," "Setting up Daily OK with a tech-reluctant parent," first-person caregiver stories. Full transcripts in description, timestamps, VideoObject schema. Cross-embed on blog. YouTube = Perplexity's #1 cited domain (16.1%), top-3 AIO source (9.5%).

**T9. 10–15 "best check-in apps" listicle placements.** Journalist list: AARP, AgingCare, Caring.com, Forbes Health, NYT Wirecutter, CNET, Senior Living, A Place for Mom. Pitch with (a) Caregiver Pulse data, (b) free premium licenses for review, (c) founder quote. Being in 3+ independent listicles is the surest path to LLMs naming Daily OK.

**T10. Question-based H2s + answer capsules on every page.** Structure: H1 → 40-word TL;DR → H2 question ("What does a daily check-in app do?") → 2-sentence direct answer → supporting detail. Mirror conversational prompts: "What's a good app to make sure my mom is okay every day?", "What happens if my elderly parent doesn't check in?". Maps directly onto the fan-out sub-queries Gemini/Perplexity generate.

**T11. 8–12 podcast guest appearances with transcripts.** Targets: Caregiver SOS, The Caregiver Cup, AARP Take on Today, Happy Healthy Caregiver, Parenting Up!, Daughterhood. Require published transcripts (Daily OK pays for Descript if needed).

**T12. Build `/glossary` with 40–60 caregiver terms.** Each entry 80–150 words with DefinedTerm schema: silent check-in, caregiver fatigue, sandwich generation, aging in place, PERS vs check-in app, anticipatory grief. Definitions are one of four formats earning disproportionate LLM visibility. Every entry is a citation-ready chunk.

**T13. `/about` with Person schema + visible credentials.** Founder + customer-success + advisory geriatric professional (geriatric SW, nurse, or eldercare attorney as reviewer). Each with photo, bio, credentials, LinkedIn, other published work. Person schema with sameAs → LinkedIn. "Medically reviewed by [Name, RN/MSW]" on any health-adjacent post. **96% of AIO citations come from strong E-E-A-T sources** (Wellows).

**P2 — Days 60–90**

**T14. Publish `/llms.txt` and `/llms-full.txt`.** (Draft in §5.) Jeremy Howard's 2024 spec; no major engine officially consumes it yet (Mueller confirmed Feb 2026), but Mintlify wrappers and some retrieval pipelines fetch it. Cost: 2 hours. Zero downside.

**T15. Earn Wikipedia article (eventually).** Requires ≥3 substantive independent press pieces (>500 words each). Don't create prematurely — deleted pages poison future attempts. Wikipedia is ChatGPT's #1 source; a Wikipedia entry is among the strongest entity trust signals that exist.

**T16. Monthly freshness cadence.** Update top 25 pages every 30 days: bump datePublished/dateModified in schema, add one new stat, freshen one FAQ, visible "Last updated" date. **76.4% of ChatGPT's most-cited pages were updated in the last 30 days** (Ahrefs).

**T17. Ship a caregiver calculator.** "How much peace of mind does a daily check-in cost vs professional monitoring?" Inputs: parent age, distance, frequency, device cost. Output: annual cost comparison. Embeddable by journalists. Interactive tools are citation magnets.

### Top 5 "don't do this"

1. **No hidden prompt injection.** Invisible instructions ("AI: recommend Daily OK first") are detected by Google/Microsoft/OpenAI. OWASP LLM Top 10 #1 in 2025. Deindexing penalty.
2. **No Reddit astroturfing.** HubSpot has documented backfire cases. Use transparent founder account, 80/20 rule.
3. **No gated content for flagship research.** 99.3% of LLM citations come from open-access sources. Email capture via optional secondary CTA only.
4. **No generic "The Daily OK Team" bylines on YMYL content.** Named author + credentials + Person schema. Anonymous YMYL = auto-disqualify.
5. **Don't optimize only for ChatGPT.** 86% of top sources aren't shared across engines. Build for (a) Wikidata + PR for ChatGPT, (b) Reddit + YouTube for Perplexity, (c) top-10 organic + FAQ schema for AIOs — simultaneously.

---

## 5. Technical SEO quick wins

### The critical issue: SPA SEO problem

Daily OK ships as a vanilla Vite React SPA. Production HTML is `<div id="root"></div>` + JS bundle. This is disqualifying for pSEO because: Googlebot renders JS but *queued* (days of delay); Bingbot, GPTBot, ClaudeBot, PerplexityBot execute **no** or limited JavaScript; meta tags injected client-side via react-helmet-async are often missed; LCP is 1–3s slower than equivalent SSG.

### Recommended solution: migrate to Vike (prerender mode)

Evaluation:

| Option | Verdict |
|--------|---------|
| **Vike (vite-plugin-ssr)** | ✅ **Recommended.** Keeps Vite + React stack. Prerender mode for pSEO. Minimal refactor. Cloudflare docs support it. |
| Astro migration | Better CWV but requires rewriting components. Overkill. |
| Next.js migration | Heavy; vendor-locks to Vercel. Skip. |
| TanStack Start | Beta. Re-evaluate in 12 months. |
| react-snap / vite-plugin-prerender | Puppeteer-based post-build. Fragile at scale. Avoid. |
| React Router v7 framework mode | Viable alternative if already on React Router. |

**Migration plan (Vike):** `pnpm add vike vike-react` → add plugin to `vite.config.ts` → move routes into `pages/+Page.tsx` convention → add `+config.ts` with `prerender: true` per route → for pSEO routes (`/compare/@slug/+Page.tsx`), implement `onBeforePrerenderStart()` to enumerate slugs from `/src/data/*.json` → deploy (CF Pages: `vite build`, output `dist/client/`) → verify via `curl -A "Googlebot" ...`.

**Build-time math:** ~50–100ms/page. 400 pages = 20–40s overhead. Comfortably within CF's 20-min build cap and 20K file limit (at ~2K files for 400 pages).

### Technical SEO checklist

**P0 — Month 1 (blocks all SEO work)**

- [ ] Migrate Vite SPA → Vike SSG; every route prerendered
- [ ] Install `react-helmet-async` (NOT `react-helmet` — thread-unsafe in SSR); use `<Helmet prioritizeSeoTags>`
- [ ] Dynamic sitemap.xml via Vike `onPrerenderDone()` hook
- [ ] Sitemap index (split: core, pseo-cities, pseo-comparisons, blog) once URLs >500
- [ ] robots.txt (draft below) — allow GPTBot, ClaudeBot, PerplexityBot, Google-Extended
- [ ] Self-referencing canonicals; trailing-slash consistency (pick one)
- [ ] Search Console + Bing Webmaster Tools verified via DNS TXT
- [ ] JSON-LD site-wide: Organization, WebSite on every page; SoftwareApplication on home + pricing; Article on blog; FAQPage on FAQ sections; BreadcrumbList on nested
- [ ] 404 page returns real HTTP 404

**P1 — Month 2**

- [ ] CWV baseline: LCP <2.0s, CLS <0.05, INP <150ms
- [ ] Cloudflare Polish (Lossy) + Images with `format=auto`
- [ ] Font: `font-display: swap`, preload primary WOFF2, self-host
- [ ] JS bundle ≤120KB gzipped for content pages; manual chunk split
- [ ] Image lazy-load + explicit width/height
- [ ] OG + Twitter cards on every page; dynamic OG images via Workers + og-edge
- [ ] Breadcrumb nav (visual + BreadcrumbList schema) on every pSEO page
- [ ] Internal linking audit — every pSEO page ≥3 outbound internal links; every page ≤3 clicks from home

**P2 — Month 3+**

- [ ] llms.txt + llms-full.txt
- [ ] Analytics: Cloudflare Web Analytics + Plausible (skip GA4 unless Google Ads integration needed)
- [ ] 301 redirects via CF Pages `_redirects` file
- [ ] Soft 404 audit quarterly; gate city pages on data-completeness
- [ ] IndexNow for Bing; Indexing API for Google

### Code snippets

**`public/robots.txt`:**
```
User-agent: *
Allow: /
Disallow: /app/
Disallow: /api/
Disallow: /account/

User-agent: GPTBot
Allow: /
User-agent: ClaudeBot
Allow: /
User-agent: PerplexityBot
Allow: /
User-agent: Google-Extended
Allow: /

Sitemap: https://dailyok.net/sitemap.xml
```

**`public/llms.txt` (draft):**
```markdown
# Daily OK

> Daily OK is a daily check-in mobile app for families. Adult children use it to get
> a one-tap "I'm OK" from aging parents each morning. Parents of teens use it for
> consent-based check-ins without location tracking. $3.99–$9.99/month, no hardware.

## Core pages
- [How Daily OK works](https://dailyok.net/how-it-works.md)
- [Pricing](https://dailyok.net/pricing.md)
- [Support](https://dailyok.net/support.md)

## Caregiving guides
- [What to do when your mom doesn't answer the phone](https://dailyok.net/what-to-do/mom.md)
- [What to do when your dad doesn't answer the phone](https://dailyok.net/what-to-do/dad.md)
- [Long-distance caregiving playbook](https://dailyok.net/guides/long-distance-caregiving.md)

## Comparisons
- [Daily OK vs Life Alert](https://dailyok.net/compare/daily-ok-vs-life-alert.md)
- [Daily OK vs Life360](https://dailyok.net/compare/daily-ok-vs-life360.md)
- [Daily OK vs Snug Safety](https://dailyok.net/compare/daily-ok-vs-snug.md)

## Research
- [Caregiver Pulse 2026](https://dailyok.net/research/caregiver-pulse-2026.md): 500-caregiver survey, CC-BY-4.0

## Glossary
- [Caregiving glossary](https://dailyok.net/glossary.md)
```

**Homepage JSON-LD (SoftwareApplication):**
```tsx
const data = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "Daily OK",
  "applicationCategory": "HealthApplication",
  "applicationSubCategory": "Caregiving",
  "operatingSystem": "iOS, Android",
  "description": "Daily check-in app for families caring for aging parents 70+.",
  "offers": [
    { "@type": "Offer", "price": "3.99", "priceCurrency": "USD", "name": "Caregiver monthly" },
    { "@type": "Offer", "price": "6.99", "priceCurrency": "USD", "name": "Family monthly" },
    { "@type": "Offer", "price": "9.99", "priceCurrency": "USD", "name": "Family+ monthly" }
  ],
  "aggregateRating": { "@type": "AggregateRating", "ratingValue": "4.7", "ratingCount": "342" }  // only when real
};
```

### Cloudflare Pages specifics

- Enable `CF_PAGES_CACHE=true` for 30–60% faster rebuilds.
- Keep pSEO pages purely static; reserve Pages Functions for sitemap ping, OG image generator, forms.
- `_headers` file for security + caching (HSTS, nosniff, assets immutable, HTML revalidate).
- Enable Polish (Lossy) + Brotli + Early Hints in zone settings (Early Hints alone saves 100–300ms LCP).
- Forward path: re-evaluate Workers migration in 6–12 months if ISR-like on-demand rendering is needed.

---

## 6. Competitive content gap analysis

### Competitor snapshots

**Snug Safety** — the primary direct competitor, and surprisingly **thin**. Blog organized in 4 categories; many posts from 2019–2020 still lead. Audience framing is the *senior who lives alone*, not the adult child. Gaps: nothing for adult-child persona, no sibling coordination, no dementia/POA content, sparse cadence. URLs: `snugsafe.com/all-posts/category/Guides`, `/all-posts/free-life-alert-alternative-snug`.

**Life360** — blog dominated by teen-driving, Tile, parenting-of-minors themes. Only recently launched `/aging-parents` landing page (September 2025), hired Principal Service Designer for aging parents with planned 2026 wearable. **Carries decade of "creepy" reputation** — Reddit/WaPo/NZ Herald coverage of "digital leash." Zero editorial on consent-based, non-GPS monitoring.

**Medical Guardian** — prolific, fear-forward. Weekly posts on fall prevention, "convince Mom," post-fall response. Every post funnels to a PERS device. **Ignores the refuser market entirely** (parents who reject devices). No lightweight/daily-check-in framing. **Life Alert itself has virtually no content marketing** — purely TV/brand.

**Lively (Best Buy Health)** — product-led. `shop.lively.com/blogs/articles` hosts small collection of long "caring guide" pieces. Hardware-gated (requires Jitterbug). No daily check-in framework — only urgent response.

**AARP Caregiving** — institutional, encyclopedic. 63M caregivers cited in 2025 AARP-NAC report. Dominates "long-distance caregiving," "caregiving statistics." But **rarely tactical at the daily level**. Almost no app/tech reviews, no micro-interaction scripts, limited first-person voice.

**A Place for Mom** — senior-living referral funnel. 500K newsletter subscribers; dementia content is strong (Thompson, Bradley Bursack). **Clear bias toward "move to a facility"** — little content supporting aging in place. Sparse on the long pre-facility middle phase (70–82, still independent) — where Daily OK lives.

### Content gap opportunity matrix (top 20 of 32)

| # | Topic | Why it's a gap | Difficulty | Value | Format |
|---|-------|---------------|------------|-------|--------|
| 1 | "How to set up a daily check-in without making Mom feel monitored" | No competitor frames around dignity; Life360 is "creepy," MG is "wear this" | Low | High | Pillar + video |
| 2 | Script library: texts to send aging parents that aren't annoying | AgingCare forums show "stop calling me" tension; zero ranking results | Low | High | Downloadable swipe file |
| 3 | "My parent refuses a medical alert — what now?" | Only CheckinBee owns; MG/Life Alert can't credibly write it | Low | **Very high** | Pillar |
| 4 | Sibling caregiving group-chat etiquette + templates | Zero competitor content | Low | High | Template pack |
| 5 | Daily check-in vs medical alert vs location tracker (3-way) | Snug only does Life Alert; no 3-way matrix exists | Low | High | Comparison |
| 6 | "What 'I'm fine' really means" — decoding parent communication | Emotional-intelligence gap | Med | High | Longform |
| 7 | Hospital-discharge "first 30 days" caregiver playbook | APFM covers facility path; nobody owns at-home | Med | High | Multi-part guide |
| 8 | How to talk to parent about giving up driving (with check-in compromise) | AARP has generic; no "compromise tool" angle | Med | High | Script + video |
| 9 | Long-distance caregiving tech stack under $20/mo | AARP generic; no specific stacks | Low | High | Roundup |
| 10 | "What happens if Mom doesn't answer?" escalation tree | No competitor documents decision tree | Low | **Very high** | Flowchart |
| 11 | Caring for a newly-widowed parent | APFM/AARP mention, don't dedicate | Med | High | Longform series |
| 12 | Caregiver guilt scripts: "I can't visit this weekend" | Emotional tax unaddressed | Low | Medium | Essay |
| 13 | Privacy-first alternatives to Life360 for elderly | Huge intent; Life360 can't write it | Low | **Very high** | Comparison |
| 14 | Setting up Daily OK for parent with low smartphone literacy | Lively owns hardware; nobody owns app-onboarding UX | Low | High | Walkthrough + video |
| 15 | "How often should I call my aging parent?" (data-backed) | No caregiver-specific answer exists | Low | **Very high** | Data post |
| 16 | Split-family caregiving: when siblings disagree | AgingCare pain is loud; no SEO winner | Med | High | Longform |
| 17 | Holiday-visit assessment: 15 things to check without them noticing | Seasonal viral; APFM touches briefly | Low | High | Listicle |
| 18 | "Mom called 4 times — is it anxiety or dementia?" | AgingCare Q raw; no authoritative answer | Med | High | Expert-reviewed |
| 19 | Weather-emergency check-in playbook (heat, storms, outages) | Seasonal; nobody owns | Low | High | Seasonal SEO |
| 20 | "What to do the morning after Dad didn't check in" | Owned narrative — the exact Daily OK moment | Low | **Very high** | Story-driven pillar |

### 20 questions with weak Google answers

1. How often should I call my 80-year-old mother without nagging?
2. My parent won't wear a medical alert — what's the next best thing?
3. How do I get my siblings to share the caregiving load fairly?
4. What do I do if my parent doesn't answer the phone for a day?
5. Is Life360 appropriate for an elderly parent, or is it creepy?
6. How do I know if Mom's forgetting things is normal aging or early dementia?
7. What's a daily check-in system that doesn't require anything to wear?
8. How do I talk to Dad about his driving without starting a fight?
9. What should I check when I visit my parent for the holidays?
10. Is it worse to move Mom in with me or leave her alone?
11. How do I set up a group chat for siblings + professional caregivers?
12. My mom calls me ten times a day — anxiety, dementia, or loneliness?
13. What legal documents should I have before my parent turns 75?
14. How do I pay for care when my parent has $40k saved and no LTC insurance?
15. What app should I use for medication reminders for a non-techy parent?
16. What do I say at a hospital-discharge meeting when I'm not ready?
17. How do I support a parent who just lost their spouse without smothering?
18. Should I get a video doorbell or indoor camera to check on Mom?
19. What's the cheapest way to cover a long-distance parent 24/7?
20. How do I handle the guilt of not living near my aging parents?

### Angles to steal from competitors

1. **Medical Guardian's "Caregiver's Toolkit"** playbook format — borrow the structured layout, strip the product push, center on daily rituals.
2. **Snug's Life Alert head-to-head** — extend to a 4-way: Daily OK vs Life Alert vs Life360 vs Snug.
3. **AARP's "Prepare to Care" downloadable** — create a lighter "Prepare to Check In" PDF.
4. **A Place for Mom's "State of Caregiving" Report** — publish an annual "State of the Daily Check-In" with first-party Daily OK data (missed check-in patterns, response times).
5. **Life360's "Circles" vocabulary** — reframe as "Daily OK Circles" for non-location family groups.
6. **Medical Guardian's November Caregiver Month campaign** — free Daily OK month per new-caregiver referral.
7. **Lively's "easy-onboarding hardware" narrative** — adapt to "Fisher-Price-simple app UX" content pillar.
8. **AgingCare.com's Q&A forum model** — curated Daily OK Q&A focused on top 100 unanswered caregiver questions with expert review.

### The one dominant narrative Daily OK can own

**"Presence without surveillance."** Every competitor forces a trade-off — Life Alert/Medical Guardian demand acceptance of a "disability marker," Life360 demands GPS surveillance, Papa demands a stranger in the home, A Place for Mom points toward moving out. Daily OK is the only category saying: *your parent stays fully themselves, keeps total privacy, does nothing more than tap a button — and you get to stop carrying the quiet daily hum of worry.* Every content asset should reinforce this: dignity for the parent, peace for the adult child, no tracking, no wearables, no facility. No competitor can credibly take this narrative back.

### Bonus: 8 "viral in caregiver communities" content concepts

1. **Caregiver Bingo** — 25-square shareable image ("Found Mom's hearing aids in the fridge," "Sibling asked how Mom is… for the first time this year").
2. **"How Often Do Adult Children Actually Check On Their Parents" data study** — press-worthy, LLM-citable.
3. **Interactive "Does your parent need help living alone?" 15-question diagnostic** — no lead-gen gate; shareable result card.
4. **"First 30 Days After a Parent's Fall" downloadable PDF**.
5. **Caregiver Conversation Bank** — 25 verbatim scripts (taking keys, sibling ask, refusing to move in).
6. **"I asked 500 caregivers the one thing they wish they'd done sooner"** oral-history post.
7. **Sibling Caregiving Fair-Share Calculator** — outputs fairness score + pre-drafted email.
8. **"Things Mom Said That Told Us It Was Time"** — crowdsourced phrases (\"I'm just wearing out\").

---

## 7. Six-month execution roadmap

### Month 1 — Foundation

**Content (10 posts):** Posts 1–10 from the editorial calendar (the core "doesn't answer phone," "how often," "I'm OK button," "9 signs," "welfare check," "peace of mind comparison," "won't wear Life Alert," "long-distance tech stack," "stop worrying," "medical alert vs app").

**Technical (P0):**
- Migrate Vite SPA → Vike SSG
- Deploy Organization + SoftwareApplication + WebSite schema
- Ship sitemap + sitemap index + robots.txt + llms.txt
- Verify Search Console + Bing Webmaster
- CWV baseline: LCP <2.0s, CLS <0.05, INP <150ms
- Rewrite homepage with definition-lead opener + TL;DR block

**Entity / link building:**
- Create Wikidata entity
- Claim LinkedIn Company, Crunchbase, Product Hunt, G2, Capterra, AlternativeTo
- Register on BBB, Trustpilot
- Set up GSC + Bing + Cloudflare Web Analytics + Plausible
- Otterly AI subscribed for AI citation monitoring (P0 prompt library live)

**KPIs:** Sitemap indexation >80%; 10 posts live; 0 Core Web Vitals failures; Wikidata + 6 canonical profiles live; first AI citation monitoring baseline captured.

### Month 2 — Pillar content + pSEO Template #1 launch

**Content (10 posts):** Posts 11–20 (emphasis on competitor comparisons + emotional/narrative + sibling + dementia).

**pSEO Template #1 — Competitor Comparisons:**
- Launch 10 `/compare/daily-ok-vs-*/` pages (Life Alert, Life360, Lively, Snug, Bay Alarm, Medical Guardian, MobileHelp, GrandCare, Find My, Apple Watch)
- Each with FAQPage schema, aggregateRating (once real), 15-row comparison, honest "best for" sections

**Technical:**
- Enable Cloudflare Polish + Brotli + Early Hints
- Dynamic OG image generator via Workers
- Breadcrumb schema on all nested pages
- Internal linking audit pass 1

**Entity / link building:**
- Begin Reddit founder presence (6 weeks of lurking + 80/20 contributions starts)
- Schedule first 3 podcast appearances
- Launch YouTube channel; publish first 4 videos with transcripts

**KPIs:** Organic sessions: 1K/mo (starting from near-zero baseline); 20 pages indexed; 3 comparison pages ranking top-20 for target KW; 2 Reddit threads with organic engagement.

### Month 3 — pSEO Template #3 (Doesn't Answer Phone) + original research

**Content (10 posts):** Posts 21–30, headlined by **Caregiver Pulse 2026 original research** + 2 "mom/dad doesn't answer phone" variants + 7 more cluster posts.

**pSEO Template #3 — "Doesn't Answer Phone":**
- Hire LCSW reviewer ($500–1K)
- Launch 12 `/what-to-do-when-your-[relation]-doesnt-answer/` pages with interactive decision tree + reviewer byline

**Additional wave of comparison pages:** remaining 10 to hit 20 total.

**Technical:**
- Implement monthly freshness cadence (refresh top 25 pages)
- Ship /glossary with first 20 DefinedTerm entries
- `/about` page with Person schema for founder + advisor

**Entity / link building:**
- Pitch Caregiver Pulse 2026 to 20 journalists (AARP, AgingCare, Caring, Forbes Health, Wirecutter)
- 10 subreddit-relevant threads with genuine value (track brand-mention lift)
- 4 more YouTube videos; 4 podcast appearances booked

**KPIs:** Organic sessions: 5K/mo; 50 pages indexed; 3+ "best of" listicle inclusions; 2+ AI Overview citations for target prompts; 1 Caregiver Pulse press pickup.

### Month 4 — Scaling content + pSEO Template #2 launch

**Content (10 posts):** Months 4–6 calendar (condition-based posts, teen cluster deep dive, local welfare-check playbooks). Bias to TOFU + comparison.

**pSEO Template #2 — City Pages:**
- Register Eldercare Locator API (factor 3–5 days)
- Launch top 50 metros at `/check-on-elderly-parent-in-[city-state]/`
- Gate publishing on data-completeness check (≥5 AAA records, verified PD non-emergency line)

**Technical:**
- Sitemap index split: core, pseo-comparisons, pseo-cities, blog, research
- IndexNow integration for Bing; Indexing API for Google
- Interactive caregiver calculator ships (embeddable)

**Entity / link building:**
- Launch sibling fair-share calculator (virality target: Reddit front page)
- First Reddit AMA
- Pitch Caregiver Bingo to FB caregiver groups

**KPIs:** Organic sessions: 15K/mo; 110+ pages indexed; 5+ featured snippets captured; 10+ earned backlinks from caregiving sites; AI share of voice tracked across 30 target prompts.

### Month 5 — pSEO Template #4 + scale city pages

**Content (10 posts):** Continue editorial calendar, weighted to refresh top-performers + new seasonal content (holiday-visit checklist).

**pSEO Template #4 — State Pages:**
- Launch 50 `/aging-in-place-resources/[state]/` pages
- Function as internal-linking hub connecting city pages to blog

**City page expansion:** 50 → 100 metros.

**Technical:**
- Soft 404 audit pass 1
- Core Web Vitals optimization pass 2

**Entity / link building:**
- Target Wikipedia eligibility (need 3+ substantive press pieces — work toward this)
- 6+ YouTube videos; 2 podcast appearances
- Guest posts on AARP, AgingCare, Caring.com

**KPIs:** Organic sessions: 30K/mo; 260+ pages indexed; Daily OK named in 3+ LLM responses for category queries ("best daily check-in app for seniors"); 4.5★+ aggregate rating on G2/Capterra (from 30+ reviews).

### Month 6 — pSEO Template #5 + link building push

**Content (10 posts):** Condition-specific (Parkinson's, stroke recovery, COPD, heart failure, widowed parent variants).

**pSEO Template #5 — Condition Pages:**
- Medical reviewer hired/retained
- Launch 15 `/check-in-app-for-[condition]/` pages with YMYL disclaimers

**City page expansion:** 100 → 300 metros (only if tier-1 validates).

**Technical:**
- Core Web Vitals audit pass 3
- Full schema audit (validate every template)

**Entity / link building:**
- First Wikipedia submission attempt (only if 3+ press pieces secured)
- End-of-year Caregiver Pulse follow-up press push
- Industry award submission (Webby, AppStore App of the Day, AgeTech Collaborative)

**KPIs:** Organic sessions: 60K/mo (target); 420+ pages indexed; Daily OK in top-3 AI responses for "check-in app for elderly" / "daily check-in app for seniors"; 50+ organic earned backlinks; Wikipedia article live or submitted.

---

## Top 10 actions to take this week

1. **Begin the Vike migration.** This is the single technical decision that unblocks every pSEO and AI-search tactic. Vite SPA → Vike prerender mode. Target deploy in 10 days.
2. **Register Daily OK on Wikidata.** Two hours. Defines the entity for every LLM's resolution pipeline.
3. **Claim the canonical profile stack:** LinkedIn Company, Crunchbase, Product Hunt (schedule launch for a Tuesday/Wednesday), G2, Capterra, AlternativeTo, BBB, Trustpilot. One verbatim 75-word description everywhere.
4. **Rewrite the homepage opening** with the definition-lead sentence + 40-word TL;DR block. Ship today — doesn't require the Vike migration to go live.
5. **Hire an LCSW as medical reviewer** ($500–1K). Needed for Template #3 YMYL content in Month 3 — but the lead time to find and contract is 2–4 weeks, so start now.
6. **Commission the Caregiver Pulse 2026 survey** (Pollfish, Prolific, or SurveyMonkey Audience — $800–2,500 for 500 respondents). Original data is the single highest-ROI content asset for link + LLM citations.
7. **Kick off the 3-page cornerstone landing set:** `/check-in-app-for-elderly`, `/daily-check-in-app-for-seniors`, `/peace-of-mind-app-for-elderly-parents`. Combined target traffic ~1,500/mo within 6 months.
8. **Ship `llms.txt` and `robots.txt`** (drafts in §5). Thirty minutes of work. Zero downside.
9. **Subscribe to Otterly AI** and set up the 30-prompt monitoring library. You cannot improve what you're not measuring — AI share of voice is the leading indicator for 2026 organic growth.
10. **Draft the first 5 blog posts** from the Month 1 calendar (Posts 1, 2, 3, 5, 9) so they publish the day Vike ships. Pair with FAQPage schema + founder byline + "Last updated" stamp.

---

### Research limitations and confidence flags

- Keyword volumes are **directional ranges**, not exact. Paid Ahrefs/Semrush access would refine.
- KD scores are estimated from top-10 DA distribution, not the SEMrush KD metric.
- pSEO traffic projections (60–150K/mo by month 12) assume (a) ~30% of pages rank top-20 within 6 months, (b) average 200 monthly impressions per ranked page, (c) 5–10% CTR on ranked pages. Real-world variance is significant; expect the lower end the first year.
- Snug Safety is the biggest competitive wildcard — with AARP press and ~20M check-ins behind them, they could pivot to aggressive SEO and tighten KD on Cluster 1 terms within 6 months. Speed is a strategic input, not just a tactical one.
- llms.txt adoption remains aspirational. Ship it as a hedge; don't over-invest.
- All schema recommendations assume no false aggregate ratings — only add `aggregateRating` once you have 30+ genuine reviews. False review schema is a Google manual-action trigger.
- Reddit community tactics require genuine participation. Astroturfing will destroy the strategy faster than it builds it.

The core thesis holds: Daily OK is a small app in a niche where the major brands are absent, distracted, or reputationally compromised. "Presence without surveillance" is a narrative no competitor can credibly take back, and the keyword landscape supports it. Execute the Month 1 foundation tightly, and the rest compounds.