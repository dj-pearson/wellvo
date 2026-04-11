# Wellvo iOS — Pricing Model Research & Recommendation

**Status:** Research / proposal
**Last updated:** 2026-04-11
**Audience:** Product + founder
**Scope:** iOS app pricing only (Android should mirror once validated on iOS)

---

## 1. Why this doc exists

The current v1 pricing was designed for a generic "family check-in" audience:
a Free tier for 1 Receiver, then Family and Family+ tiers scaled by how many
Receivers and Viewers a household has.

In practice, the dominant real-world persona is **one adult child monitoring
one aging parent with dementia** (plus 1–3 siblings who want visibility). The
current model has two problems for that persona:

1. **The Free tier gives away the entire product.** One Receiver with daily
   check-ins is exactly what the dementia caregiver needs. They have no reason
   to ever upgrade — the paid tiers scale a dimension (more Receivers) that
   doesn't apply to them.
2. **The paid tiers are priced for a use case they don't have.** A Family
   tier that includes 2 Receivers feels wasteful to someone who only needs 1,
   and pushes them back toward Free.

The goal of this doc is to recommend a pricing structure where:

- Every tier is paid (no permanent free tier).
- There's a meaningful trial so users can experience the check-in loop before
  paying.
- The lowest tier matches the dementia-caregiver persona exactly (1 Receiver,
  a few Viewers).
- Prices cover infrastructure costs with healthy margin and sit in the
  competitive band set by comparable apps.

---

## 2. Current pricing (for reference)

Source: `website/src/pages/Pricing.tsx`, `docs/APP_STORE_CONNECT_AND_SUPABASE_SETUP.md`,
`Wellvo-PRD-v1.md` §5.1.

| Tier         | Monthly | Yearly   | Receivers | Viewers | Notes                                   |
| ------------ | ------- | -------- | --------- | ------- | --------------------------------------- |
| Free         | $0      | $0       | 1         | 0       | 7-day history, basic escalation         |
| Family       | $4.99   | $39.99   | 2         | 2       | Full escalation, mood, 90-day history   |
| Family+      | $7.99   | $59.99   | 5         | 5       | Critical Alerts, PDF export, unlimited  |
| +Receiver    | $1.99   | —        | +1        | —       | Add-on, Family/Family+ only             |
| +Viewer      | $0.99   | —        | —         | +1      | Add-on, Family/Family+ only             |

Trials: 7-day on monthly, 14-day on yearly (Family and Family+ only).

---

## 3. Cost analysis — what we have to cover

### 3.1 Fixed infrastructure (amortized across all users)

| Item                        | Monthly cost        | Source                             |
| --------------------------- | ------------------- | ---------------------------------- |
| Contabo VPS (Coolify host)  | ~$5–15              | Contabo pricing page (4 vCPU/8 GB) |
| Domain + Cloudflare         | ~$1                 | Cloudflare free tier               |
| APNs (Apple push)           | $0                  | Included with Apple Developer      |
| Apple Developer Program     | $8.25/mo ($99/yr)   | Fixed                              |
| Backup storage              | ~$1                 | Contabo object storage             |
| **Fixed monthly total**     | **~$15–25**         |                                    |

At 100 paying users: **~$0.15–$0.25 / user / month** in fixed infra.
At 1,000 paying users: **~$0.015–$0.025 / user / month**.

The single-VPS + Coolify architecture scales well — expect to stay under $50/mo
fixed infra well past 1,000 users before needing a second node.

### 3.2 Variable costs per Owner

| Item                          | Per-user / mo    | Assumptions                                       |
| ----------------------------- | ---------------- | ------------------------------------------------- |
| Twilio SMS escalation         | $0.02–$0.15      | 2–15 SMS/mo @ ~$0.012/segment (base + carrier fee)|
| Twilio SMS invite (onboarding)| $0.012 one-time  | 1 invite per Receiver                             |
| Twilio number + 10DLC         | ~$0.002          | $1.15/mo number + ~$1.50/mo campaign ÷ user base  |
| Database + storage            | negligible       | Check-in rows are tiny                            |
| Bandwidth                     | negligible       | Cloudflare-fronted                                |
| **Variable, per Owner**       | **~$0.05–$0.20** |                                                   |

The SMS cost is the only meaningful variable lever. A Receiver who never
misses a check-in costs basically nothing. A Receiver who triggers the full
escalation chain (2 reminders + Owner SMS + 2 Viewer SMS) costs ~$0.06 per
incident. A chronic misser could push $0.50/mo.

### 3.3 Apple's cut

Apple takes **15%** under the Small Business Program (< $1M/yr revenue), which
Wellvo will qualify for from day one. Once past $1M it becomes 30% on net-new
subscribers and 15% on subscribers in year 2+.

Applied to the current tiers (monthly, SBP 15%):

| Tier    | Gross   | Apple 15% | Net to Wellvo | Variable cost | **Margin**   |
| ------- | ------- | --------- | ------------- | ------------- | ------------ |
| Family  | $4.99   | $0.75     | $4.24         | ~$0.15        | **~$4.09**   |
| Family+ | $7.99   | $1.20     | $6.79         | ~$0.20        | **~$6.59**   |

On yearly plans, per-month net is lower (Family yearly nets ~$2.83/mo after
Apple's cut) but churn is drastically lower and no payment processing ping-pong.

**Bottom line:** at any price above ~$1.99/mo, Wellvo is profitable on
variable costs. The question isn't "can we cover costs" — it's "what price
captures value without suppressing conversion."

---

## 4. Competitive landscape — what people pay for similar apps

| App              | Free tier? | Lowest paid  | Premium       | Notes                              |
| ---------------- | ---------- | ------------ | ------------- | ---------------------------------- |
| Snug Safety      | Yes (core) | $17.99/yr    | $19.99/mo     | Free = 1 check-in; $19.99 adds dispatch call |
| Life360          | Yes        | $4.99/mo     | $14.99/mo     | Location-heavy, different category |
| Memory Lane Games| No         | $9.99/mo     | —             | Dementia-specific                  |
| Carely           | Free/low   | —            | —             | Care coordination, not check-in    |
| Medical Guardian | No         | ~$30/mo      | ~$50/mo       | Hardware + monitoring              |
| Life Alert       | No         | ~$50/mo      | ~$90/mo       | Hardware + monitoring              |
| Generic caregiver| Mixed      | $9.99/mo     | $10–15/mo     | Per search results                 |

**Takeaways:**

- The **$4.99–$9.99/mo band** is where app-only caregiver tools live.
- Hardware-based medical alerts ($30–50/mo) anchor the high end and make a
  $5–10/mo software-only alternative feel cheap by comparison. This is the
  positioning to lean on.
- Snug Safety's free tier is the closest direct competitor. It's relevant
  because it proves people will use a free daily check-in — but Snug's
  $19.99/mo upsell is a phone dispatcher, not more features, so they haven't
  figured out software monetization. Wellvo can.
- No competitor has a dedicated "1 parent with dementia" tier. This is a
  positioning gap.

---

## 5. Trial strategy — what the data says

From Adapty's *State of In-App Subscriptions 2026*, RevenueCat, and Phiture
benchmarks:

- **Median trial conversion across subscription apps: ~45%.**
- **7-day trials convert at ~40%** — popular because of urgency, but not
  optimal for apps that require habit-building.
- **5–9 day trials are the sweet spot** (52% of apps, 45% median conversion).
- **17–32 day trials convert slightly higher (45.7%) but cancel far more often**
  (51% cancel vs. 26% for 3-day trials). Net is roughly a wash.
- **Habit-building apps benefit from longer trials on annual plans.**
  Headspace famously uses 7 days on monthly and 14 days on annual — the longer
  trial is a tool to push users onto the higher-LTV annual plan.

**Implication for Wellvo:** The check-in loop takes at least a week to feel
real — you need to experience a scheduled check-in, an on-demand ping, and
ideally one "near-miss" to understand the escalation value. A 7-day monthly
trial is the minimum viable length. A 14-day yearly trial is the right carrot
to push users to annual.

The current trial structure (7-day monthly, 14-day yearly) is correct. **Keep it.**

---

## 6. Recommendation — new pricing structure

### 6.1 Three paid tiers, no permanent free

| Tier        | Monthly  | Yearly   | Receivers | Viewers | Key features                                                                 |
| ----------- | -------- | -------- | --------- | ------- | ---------------------------------------------------------------------------- |
| **Caregiver** (new) | **$3.99** | **$29.99** | **1**     | **3**   | Full check-in loop, full escalation, mood, 90-day history                    |
| **Family**  | **$6.99** | **$54.99** | **3**     | **5**   | Everything in Caregiver + pattern alerts, PDF export, 1-year history         |
| **Family+** | **$9.99** | **$79.99** | **6**     | **10**  | Everything in Family + Critical Alerts, unlimited history, priority support  |

Add-ons (unchanged in spirit, slight reprice to match cost of SMS escalation):

| Add-on                | Price       | Notes                                  |
| --------------------- | ----------- | -------------------------------------- |
| +1 Receiver           | $2.49/mo    | Family and Family+ only                |
| +1 Viewer             | $0.99/mo    | Family and Family+ only                |

### 6.2 Why this shape

**Caregiver tier ($3.99/mo) — the dementia persona's home.**

This is the tier that the majority of your users will actually buy.

- **1 Receiver, 3 Viewers** maps exactly to the dominant family shape: one
  parent with dementia being monitored by the primary caregiver child, with
  2–3 siblings watching read-only.
- **$3.99 is a "frictionless" price point** — under $4, under $48/yr, feels
  like a Netflix add-on, not a recurring commitment.
- **$29.99/yr is a 37% discount** — aggressive enough to pull habit-formed
  trial users onto annual, which is where LTV lives.
- **Full escalation, mood, and 90-day history ship at this tier**, which is
  critical for the dementia use case. Pattern alerts are the one feature
  withheld — they require more data, feel premium, and give Family an upsell
  reason.
- Margin: $3.99 − $0.60 (Apple 15%) − $0.15 (variable) = **~$3.24 net/mo**,
  or ~$39/yr per user. That covers your VPS fixed cost with ~5 paying users.

**Family tier ($6.99/mo) — the "multi-parent" household.**

- **3 Receivers** covers both-parents households (dementia parent + healthier
  spouse) or a couple managing an elderly parent *and* a teenager.
- **5 Viewers** handles extended family — cousins, adult grandchildren, a
  home-health aide.
- **Pattern alerts + PDF export + 1-year history** are the upsell hooks.
  Pattern alerts in particular are high-value for dementia progression
  tracking (a caregiver showing a doctor "check-in time drifted 90 minutes
  over 30 days" is real clinical signal).
- $6.99/mo lands inside the generic caregiver-app competitive band ($9.99).
- Margin: ~$5.79 net/mo.

**Family+ tier ($9.99/mo) — the power-user / multi-family ceiling.**

- Rounded-up "caregiver app" market price.
- **Critical Alerts** (iOS DND bypass) is the real differentiator here and
  the single feature that justifies $10/mo. This should be marketed as
  "peace of mind while you sleep" — directly addresses the 3 AM missed
  check-in fear that dementia caregivers live with.
- **Unlimited history** matters for long-term progression tracking.
- 6 Receivers + 10 Viewers is deliberately generous so the handful of
  blended/extended-family power users can commit.
- Margin: ~$8.29 net/mo.

### 6.3 Trial structure

Keep the current structure, extend to the new Caregiver tier:

| Plan                | Trial length |
| ------------------- | ------------ |
| Caregiver Monthly   | 7 days       |
| Caregiver Yearly    | 14 days      |
| Family Monthly      | 7 days       |
| Family Yearly       | 14 days      |
| Family+ Monthly     | 7 days       |
| Family+ Yearly      | 14 days      |

Onboarding should **default the trial selection to Caregiver Yearly** — it's
the highest-LTV plan and the 14-day trial gives enough time to experience a
real near-miss. An explicit "Compare plans" link lets power users up-select.

### 6.4 What happens to the existing Free tier

Remove it. Anyone currently on Free gets a grandfathered free tier for 90
days with a clear migration prompt pointing at the $29.99/yr Caregiver plan.
This is the most forgiving deprecation path and won't generate App Store
review issues as long as current paying subscribers are unaffected.

### 6.5 What this does to revenue

Quick sensitivity check assuming 1,000 Owners at the new structure with a
realistic mix:

| Tier        | % mix | Avg net/mo/user | Contribution/mo |
| ----------- | ----- | --------------- | --------------- |
| Caregiver   | 70%   | $3.24           | $2,268          |
| Family      | 20%   | $5.79           | $1,158          |
| Family+     | 10%   | $8.29           | $829            |
| **Total**   |       |                 | **~$4,255 MRR** |

Compare to the current model at 1,000 Owners assuming 80% Free / 15% Family /
5% Family+: ~$2,145 MRR. **Killing Free and introducing Caregiver roughly
doubles MRR at the same user count**, because the 80% on Free that would
never have converted now convert to the cheapest paid tier that exactly fits
their need.

---

## 7. Risks and open questions

1. **Conversion cliff when removing Free.** Some fraction of the "would-have-
   been-Free" audience won't convert even to $3.99. Mitigation: make the
   trial the entry point, not a paywall. Onboarding shouldn't show pricing
   until after the user has set up a Receiver and seen the dashboard. The
   trial should feel like "start using Wellvo" not "start your subscription."
2. **App Store review risk.** Apple will scrutinize a trial-first flow to
   make sure the paywall is honest. The paywall must clearly show: trial
   length, price after trial, auto-renewal, cancellation instructions. This
   is standard and StoreKit 2 handles it — just don't try to hide the price.
3. **Receiver accessibility regression.** The Receiver experience must stay
   free-forever from the Receiver's perspective — they should never see a
   paywall, period. This is already the case (Owner-pays architecture) but
   worth re-asserting in the subscription webhook tests.
4. **Downgrade path from Family+/Family to Caregiver.** If an Owner with 4
   Receivers downgrades to Caregiver, which Receiver "wins"? Need the same
   soft-deactivation flow already specified in PRD §5.2 — just extend it to
   cover the new tier's 1-Receiver limit.
5. **Price anchoring.** $9.99/mo Family+ should feel cheap next to $30–50/mo
   medical alert devices. Marketing on the pricing page should explicitly
   make this comparison.
6. **Pattern alerts as a Caregiver feature?** There's an argument that
   pattern alerts should ship in Caregiver (because they're *most* valuable
   for dementia tracking). The counter-argument is that Caregiver needs
   *something* to upsell from. Recommend: ship pattern alerts in Caregiver,
   ship "pattern alerts + shareable clinician PDF export" in Family. The PDF
   export is what a doctor actually wants, and that's a cleaner upsell.

---

## 8. Implementation checklist (if this is approved)

- [ ] Create 6 new StoreKit products in App Store Connect:
  - `net.wellvo.caregiver.monthly` ($3.99)
  - `net.wellvo.caregiver.yearly` ($29.99)
  - `net.wellvo.family.monthly` ($6.99) — reprice
  - `net.wellvo.family.yearly` ($54.99) — reprice
  - `net.wellvo.familyplus.monthly` ($9.99) — reprice
  - `net.wellvo.familyplus.yearly` ($79.99) — reprice
- [ ] Add `caregiver` case to `SubscriptionTier` enum
  (`ios/Wellvo/Models/Family.swift:3`).
- [ ] Add Caregiver product IDs + tier mapping to
  `ios/Wellvo/Services/SubscriptionService.swift:17` (`ProductIDs` struct) and
  update `updateCurrentTier()` to include `caregiver`.
- [ ] Update `hasAccess(to:)` precedence: `familyPlus` > `family` > `caregiver`
  > `free`. Keep `free` as a grandfather-only state.
- [ ] Add a new `00007_add_caregiver_tier.sql` migration:
  `ALTER TYPE subscription_tier_enum ADD VALUE 'caregiver';` plus updated
  `max_receivers`/`max_viewers` defaults in the families-provisioning trigger.
- [ ] Update `edge-functions/functions/subscription-webhook/index.ts` tier
  mapping to recognize the new product IDs.
- [ ] Rewrite `website/src/pages/Pricing.tsx` plans array to match §6.1
  table (and update `Pricing.css` grid to handle 3 equal-weight tiers).
- [ ] Update `docs/APP_STORE_CONNECT_AND_SUPABASE_SETUP.md` §3.1–3.4 with
  new product IDs, prices, and introductory offers.
- [ ] Update `Wellvo-PRD-v1.md` §5.1 pricing table.
- [ ] Grandfather-plan migration job: for existing Free users, set a
  `free_tier_expires_at` 90 days from the migration date and trigger a push
  campaign pointing at Caregiver.
- [ ] Update Android mirroring in
  `android/app/src/main/java/net/wellvo/android/services/SubscriptionService.kt`.
- [ ] Update subscription unit tests in
  `ios/WellvoTests/SubscriptionServiceTests.swift` and
  `android/app/src/test/java/net/wellvo/android/services/SubscriptionServiceTest.kt`.

---

## 9. Sources

- [Contabo VPS pricing (2026)](https://contabo.com/en-us/pricing/)
- [Twilio SMS pricing — United States](https://www.twilio.com/en-us/sms/pricing/us)
- [Twilio SMS API cost breakdown (2026)](https://apidog.com/blog/twilio-sms-api-cost/)
- [Life360 plans & pricing](https://www.life360.com/en-us/plans-pricing)
- [Snug Safety — daily check-in for people who live alone](https://www.snugsafe.com/how-snug-works-for-people-who-live-alone)
- [Adapty — Free Trial to Paid Conversion Rates for Apps in 2026](https://adapty.io/blog/trial-conversion-rates-for-in-app-subscriptions/)
- [RevenueCat — The right trial length isn't 7 days](https://www.revenuecat.com/blog/growth/7-day-trial-subscription-app/)
- [Business of Apps — App Subscription Trial Benchmarks (2026)](https://www.businessofapps.com/data/app-subscription-trial-benchmarks/)
- [Adapty — State of In-App Subscriptions 2026](https://adapty.io/state-of-in-app-subscriptions/)
- [StoryPoint — Best Caregiver Apps for 2026](https://www.storypoint.com/resources/senior-living/caregiver-apps/)
- [A Place for Mom — Dementia Apps for Seniors and Caregivers](https://www.aplaceformom.com/caregiver-resources/articles/dementia-apps)
