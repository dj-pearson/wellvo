# Daily OK — iOS App Store Ranking & ASO Strategy

**Owner:** Pearson Media LLC
**Status:** Approved — seniors-led (decision 2026-06-27; see `docs/SEO_STRATEGY.md`). Web + AI surfaces now match this metadata direction.
**Last updated:** 2026-06-27
**Goal:** Increase App Store **impressions** and organic installs by ranking for more of the searches our buyers actually type, and by converting more of the impressions we already get.

> This plan **supersedes** the metadata values in `docs/APP_STORE_CONNECT_AND_SUPABASE_SETUP.md §1.3` once approved. None of it changes the app binary except the in-app review prompt (§6) and optional Custom Product Page deep links (§5), which ride the normal `develop → release` flow. Everything else is App Store Connect configuration.

---

## 1. Why impressions are low today (diagnosis)

App Store impressions come from three surfaces: **Search** (~65% of installs industry-wide), **Browse** (category/Today/charts), and **Referral** (web/ads). We are starving all three:

| Problem | Evidence (current listing) | Cost |
| --- | --- | --- |
| **Name wastes its strongest ranking field** | `Daily OK — Daily Check-In` repeats "Daily" twice and spends the most heavily-weighted field on no high-intent category words (senior, elderly, safety). | We don't rank for the terms buyers search. |
| **Subtitle is brand fluff, not keywords** | `One tap. Peace of mind.` — the #2 ranking field spent on near-zero-volume words ("one", "tap", "peace", "mind"). | ~23 wasted keyword-weighted chars. |
| **Keyword field duplicates name/subtitle & uses phrases** | `...daily check...` (dup of name), `...peace of mind` (dup of subtitle), and multi-word phrases ("family safety", "senior safety", "teen check in") burn characters Apple would otherwise let us spend on *more tokens*. Apple auto-combines single tokens across fields. | ~30 of 100 chars wasted; missing tokens like elderly, alone, fall, reminder, caregiver, wellbeing, SOS. |
| **Only one keyword field exists** | App is **English (U.S.) only**, **US storefront only**. | Leaving ~200 extra indexable keyword characters on the table (see §4). |
| **Screenshots have no caption headlines** | `screenshots/src/screens.ts` renders bare device UI — no value-prop text above the frame. The first 2–3 screenshots show in search results *without a tap*. | Low tap-through → low install conversion → Apple suppresses rank → fewer impressions. Downward flywheel. |
| **No paid amplification** | No Apple Search Ads. | No way to bootstrap the download velocity that lifts organic rank in a competitive niche. |
| **Thin ratings volume** | No in-app `SKStoreReviewController` prompt. | Rating count + average is both a ranking signal and the single biggest CVR lever; Snug Safety has thousands. |

**The flywheel we're fighting:** rank is driven by *relevance* (keywords) **×** *conversion* (tap-through + install rate) **×** *velocity* (recent downloads) **×** *retention/ratings*. Low CVR and low velocity cap our rank even on terms we're relevant for, which caps impressions, which caps velocity. We break the loop by fixing relevance + CVR + buying initial velocity simultaneously.

---

## 2. Strategic decision: who we optimize the *metadata* for

The product serves seniors, teens, and any loved one. **ASO metadata can't be all things to all people** — it must capture the largest, highest-intent search demand. That is unambiguously the **aging-parent / senior-safety** segment (the same audience our pSEO and `website/src/data/competitors/*` already target, and the 53M-caregiver demographic in our review notes).

- **Recommended:** lead the **name + subtitle** with senior/elderly/safety language. Keep teens/couples/long-distance in the **description body** and dedicated **Custom Product Pages** (§5), so we lose no positioning — we just stop diluting the highest-weight fields.
- **Alternative (if leadership wants to stay broad):** use the broad name variant in §3 and accept lower search relevance per term.

Everything below assumes the recommended path. **Decision (2026-06-27): approved — seniors-led.** The web marketing site, `llms.txt`/`llms-full.txt`, structured data, and `robots.txt` were transitioned to match (see `docs/SEO_STRATEGY.md`); teen/couples positioning is retained in the description body, Custom Product Pages, and the still-indexed `/child-safety` web funnel.

---

## 3. New metadata (ready to paste) — *fixes Search relevance*

All strings below are **character-counted against Apple's hard limits**. Tokens are never repeated across fields (Apple indexes the union of Name + Subtitle + Keywords + IAP display names), use **singular** forms (Apple matches plurals), and the keyword field uses **commas with no spaces** (every space is a wasted character).

### App Name — 25/30
```
Daily OK: Senior Check-In
```
*Broad alternative (25/30):* `Daily OK: Family Check-In`
Adds tokens: **senior, check, in** (or family). Keeps the "Daily OK" brand first.

### Subtitle — 28/30
```
Elderly safety & care alerts
```
Adds tokens: **elderly, safety, care, alerts** — all high-intent, none duplicated in the name.

### Keywords (English U.S.) — 98/100
```
aging,parent,family,caregiver,reminder,alone,fall,wellbeing,mood,emergency,sos,loved,safe,wellness
```
Rules applied: no word already in Name/Subtitle, single tokens (Apple builds the phrases, e.g. *senior* × *safe* × *aging* × *parent* → "senior safety", "safe aging parent"), no `app`, no category names, **no competitor trademarks** (Snug/Life360/Papa as keywords risk rejection — we bid on those in Search Ads instead, see §7).

**Net effect:** the indexed token set jumps from ~12 phrase-fragments to ~25+ single tokens that recombine into hundreds of long-tail phrases ("check in app for aging parent", "elderly fall alert", "senior wellness reminder", "safety app for mom alone", etc.).

### Promotional Text — editable anytime, **not** indexed (drives CVR, not rank)
Replace the unverifiable `The #1 daily check-in app...` (an App-Review-risky superlative) with a benefit CTA:
```
Set up a daily check-in for someone you love in under 2 minutes. Get an alert the moment they miss one. No tracking — just peace of mind.
```

> **Submission note:** Name, Subtitle, Keywords, and Screenshots changes require a new **version** in review, but can **reuse the current build** (metadata-only update). Promotional Text updates need no review. Bundle §3 + §5 screenshots into one metadata-only version submission.

---

## 4. Localization keyword expansion — *the highest-ROI, lowest-effort lever for impressions*

Apple indexes the keyword fields of **English (U.K.)** and **English (Australia)** for searches **in the U.S. storefront**, and **Spanish (Mexico)** Spanish keywords are indexed for U.S. searchers too. Today we have **one** English (U.S.) field. Adding two more English localizations (reusing the same screenshots/description, only the keyword field differs) roughly **triples our indexed keyword surface — ~98 → ~291 characters — with no new build and no new creative.**

> Caveat (honesty): Apple has never formally documented the en-GB/en-AU cross-indexing and it has been narrowed over the years. It costs ~30 minutes to add and is fully reversible, so we treat it as a **measured experiment**, not a guarantee. Track impression lift in App Store Connect → Analytics by keyword over the 2 weeks after adding.

### English (U.K.) keyword field — 96/100
```
checkup,welfare,distress,dementia,independent,living,vulnerable,relative,grandparent,reassurance
```

### English (Australia) keyword field — 97/100
```
carer,housebound,frail,disabled,recovery,anxiety,worry,neighbour,support,connection,checkin,nudge
```

### Phase 2 — Spanish (Mexico), once core is validated
Add a Spanish keyword field (e.g. `cuidado,ancianos,mayores,abuela,abuelo,seguridad,recordatorio,bienestar,familia,emergencia,solo,salud`) and Spanish screenshots/description. Captures the large U.S. Hispanic-caregiver market that English metadata can't reach.

**Action:** in App Store Connect, add the en-GB and en-AU localizations to the existing version, paste the keyword fields above, reuse U.S. screenshots/description (light British spelling on the en-GB description is a nice-to-have, not required).

---

## 5. Conversion-rate (CVR) overhaul — *turn the impressions we get into installs*

Higher CVR both lifts installs **and** lifts rank (Apple rewards it), so this compounds with §3–4.

### 5.1 Screenshots — add caption headlines (biggest CVR lever)
Current screenshots are bare app UI. Top-ranking apps put a **bold 3–6 word headline above the device frame**. The first **2–3 portrait screenshots render in search results without a tap** — they must sell the value instantly. Extend `screenshots/src/screens.ts` to render a caption band (brand Calm Green `#2ECC71` / Deep Slate `#1E293B`, Inter Bold) above each device.

Recommended sequence (screen → headline):
1. `receiver-checkin` → **"Know they're OK — every single day"**
2. `receiver-done` → **"One tap. They're safe."**
3. *(escalation/alert mock)* → **"Get alerted the moment they miss a check-in"**
4. `owner-dashboard` → **"See everyone you care about at a glance"**
5. *(trust frame)* → **"No tracking. No cameras. No surveillance."**
6. `history-heatmap` → **"Spot worrying patterns early"**
7. `plan-selection`/onboarding → **"Set it up in under 2 minutes"**

Add an **App Preview video** (15–30s) per the storyboard already in the setup guide §1.5.

### 5.2 Product Page Optimization (PPO) — A/B test, don't guess
Apple's built-in PPO lets us test up to **3 treatments** against the live page with statistically-measured install-rate. First tests:
- **Test 1:** caption-overlay screenshots (§5.1) vs. current bare screenshots. *(Expected winner: captions, often +15–35% CVR.)*
- **Test 2:** icon — current heart+check on green vs. a warmth variant (e.g., subtle two-person/family motif). Icon is the most-seen creative in search results.

### 5.3 Custom Product Pages (CPP) — one page per audience/traffic source
Build up to 35 CPPs, each with its own screenshots/captions, and point each traffic source at the matching page:
- **CPP-Senior** ("aging parents living alone") → target for Apple Search Ads senior/elderly ad groups + senior-care pSEO pages.
- **CPP-Teen** ("a respectful check-in for your teen") → teen/kid-mode ad groups + relevant blog posts.
- **CPP-Couples** ("long-distance peace of mind") → couples/long-distance campaigns.
Each CPP CVR is reported separately, and CPP traffic still feeds organic rank.

### 5.4 Category test
Primary is currently **Lifestyle** (huge, generic browse competition). Test **Health & Fitness** as primary — its browse/Today audience is far more intent-aligned with "check-in for a vulnerable parent" (Medical is not an available category). Reassess chart competitiveness after 2 weeks.

---

## 6. Ratings & reviews engine — *ranking + CVR compounding*

Rating **count** and **average** drive both rank and install rate. We currently prompt for neither.

- **Implement `SKStoreReviewController`** (StoreKit) at a genuinely positive moment, e.g. when the Owner first sees a **7-day streak**, or after a Receiver's **5th successful check-in**. Apple caps prompts at **3/year per user** — spend them on high-satisfaction moments only. *(This is the one app-code change; it ships via `feat/* → develop → release`.)*
- **Seed the first 50+ ratings fast:** TestFlight users, the email list, and personal network — count/recency matter most in the first weeks.
- **Respond to every review** in App Store Connect; responsiveness lifts CVR and shows Apple an actively-maintained listing.
- **In-App Events:** publish a seasonal event (e.g. *"Holiday peace of mind"*, *"Caregiver setup week"*) — events get their own search/browse card and extra surface area.

---

## 7. Apple Search Ads — *buy the velocity that bootstraps organic rank*

ASA is the fastest impressions lever and directly feeds the download-velocity signal that lifts organic rank. Use **ASA Advanced** (keyword-level control). Suggested start: **$30–50/day** total, then reallocate to whatever hits target CPI/CPA.

| Campaign | Match | Targets | Purpose |
| --- | --- | --- | --- |
| **Brand defense** | Exact | `daily ok`, `dailyok`, `daily ok app` | Cheap, ~highest CVR; stop competitors poaching our brand searches. |
| **Competitor conquest** | Exact | `snug`, `snug safety`, `life360`, `papa`, `medical guardian`, `lively`, `assureokay`, `checkin bee` | We *can* bid on competitor terms even though we can't use them as keywords. Point at CPP-Senior. |
| **Generic high-intent** | Exact | `senior check in app`, `check in app for elderly`, `daily check in`, `safety app for seniors`, `wellness check app`, `app to check on aging parents`, `fall alert app` | Core demand. |
| **Discovery** | Search Match + Broad | (auto) | Harvest converting terms → feed them into the organic keyword field (§3) and promote winners to Exact. |

**Operating loop:** weekly, pull the Search Terms report → promote converting queries to Exact, add them to the organic keyword fields, and **negative-match** spend-with-no-install terms. ASA both buys installs *and* tells us exactly which organic keywords to chase.

---

## 8. Competitive landscape (who we're ranking against)

| Competitor | Shape | Our wedge |
| --- | --- | --- |
| **Snug Safety** | Free daily check-in, 20M+ check-ins, AARP/Forbes; paid dispatch $19.99/mo | We're **multi-receiver / family-managed** (one payer manages everyone; receivers never see billing), have **escalation chains + mood/pattern alerts**, and are far cheaper than dispatch tiers. |
| **AssureOkay / CheckIn More / CheckinBee** | SMS/voice check-ins, no-smartphone-required, low price | We own the **native-app + push** experience with a one-tap UI designed for 13–95, plus dashboard/history. |
| **Life360** | Location-tracking family app | We are explicitly **not surveillance** — no location/cameras. Different intent; we conquest their brand term but position as the privacy-respecting alternative. |
| **Medical Guardian / Lively / Bay Alarm** | Hardware medical-alert devices, $$$ | We're **app-only, no hardware, no contract**, a fraction of the price — the "before you need a medical alert" product. |

Differentiation themes to carry through captions, CPPs, and ad copy: **family-managed (not single-user), privacy-first (not tracking), escalation that actually alerts you, designed for every age, no hardware/contract.**

---

## 9. 30 / 60 / 90-day rollout

**Days 0–30 — Relevance + CVR foundation (do these first, highest ROI):**
- [ ] Get sign-off on the §2 repositioning decision.
- [ ] Ship new Name / Subtitle / Keywords (§3) as a metadata-only version (reuse current build).
- [ ] Add en-GB + en-AU keyword localizations (§4).
- [ ] Build caption-overlay screenshots (§5.1) + App Preview video.
- [ ] Update Promotional Text (§3) — live immediately, no review.
- [ ] Stand up Apple Search Ads: Brand + Competitor + Generic + Discovery (§7).
- [ ] Implement `SKStoreReviewController` prompt (§6) — into `develop`, ride next release.

**Days 30–60 — Optimize what's live:**
- [ ] Launch PPO Test 1 (captions vs. bare) and Test 2 (icon) (§5.2).
- [ ] Build CPP-Senior / CPP-Teen / CPP-Couples and wire ASA ad groups to them (§5.3).
- [ ] Weekly ASA search-terms harvest → promote winners into organic keywords.
- [ ] Test Primary category = Health & Fitness (§5.4).
- [ ] Push ratings drive to 50+ (seed + in-app prompt live).

**Days 60–90 — Scale & expand:**
- [ ] Roll out PPO winners to the default page.
- [ ] Add Spanish (Mexico) localization + screenshots (§4 Phase 2).
- [ ] Publish first In-App Event (§6).
- [ ] Expand availability beyond the U.S. (currently US-only) to open more storefronts/keyword fields once metadata is proven.
- [ ] Reallocate ASA budget to lowest-CPA campaigns; consider scaling spend.

---

## 10. KPIs to watch (App Store Connect → Analytics)

| Metric | Where | Target trend |
| --- | --- | --- |
| **Impressions** (Search vs. Browse split) | Analytics → Acquisition | ↑ — primary goal |
| **Product Page Views** | Analytics | ↑ |
| **Conversion Rate** (impression→install) | Analytics + PPO | ↑ (PPO measures lift precisely) |
| **Keyword rankings** | ASA reports / 3rd-party (AppFigures/SensorTower) | More terms in top 10 |
| **Ratings count & average** | App Store Connect | 50+ then climbing; avg ≥ 4.5 |
| **ASA CPI / CPA & TTR/CR** | Search Ads dashboard | CPA ≤ target; reallocate weekly |
| **Organic vs. paid install mix** | Analytics | Organic share ↑ over time (proof the flywheel is turning) |

---

## 11. Compliance & process notes

- **Backward compatibility (`CLAUDE.md`):** §3–5, §7–8 are App Store Connect configuration — **no binary, no API, no DB change**, so no migration concerns. The only on-device code is the §6 review prompt (additive, safe) and optional §5.3 CPP deep-link handling — both ship via `feat/* → develop → release/*`.
- **No competitor trademarks in metadata** (Name/Subtitle/Keywords/Description). Conquest only via Apple Search Ads bids, which is permitted.
- **Avoid superlatives** ("#1", "best") in indexed/marketing text — App Review rejection risk; our Promotional Text rewrite removes the existing one.
- This document supersedes the metadata in `docs/APP_STORE_CONNECT_AND_SUPABASE_SETUP.md §1.3`; update that file once the §2 decision is approved so there's a single source of truth.
