# Compliance Audit — Wellvo / Daily OK

**Audit date:** 2026-07-23
**Scope:** Required legal documents & pages, ADA/WCAG 2.1 AA accessibility, and GDPR + US state privacy law (CCPA/CPRA and equivalents), across the website (`website/`), edge functions (`edge-functions/`), Supabase schema (`supabase/migrations/`), and the iOS/Android apps.
**Prepared on branch:** `claude/compliance-audit-docs-accessibility-ts5wp7`

> This document records the state of compliance at audit time, the fixes applied in this branch, and the remaining items that require a business/legal decision or real data before they can be closed. Severity legend: 🔴 Critical · 🟠 Serious · 🟡 Moderate · 🟢 Minor / informational.

---

## 1. Executive summary

The product is in **good overall shape**: a full set of legal pages exists, the privacy program is thoughtfully written (data minimization, no ad SDKs, SMS/A2P disclosures, US multi-state rights), and the core data-subject-rights plumbing (data export RPC, in-app account deletion on both platforms, retention cron jobs, thorough RLS) is largely built.

However, the audit found **one critical legal contradiction** and **two material backend defects** that should be resolved before claiming "full compliance":

| # | Issue | Area | Severity | Status |
|---|-------|------|----------|--------|
| A | **Google Analytics (GA4) loads on every page with no consent banner**, directly contradicting the Privacy Policy & Cookie Notice ("no tracking cookies", "Cloudflare only", "no consent prompt required") | GDPR / ePrivacy / FTC | 🔴 Critical | **Needs decision** (§6.1) |
| B | **Account deletion never deletes the `auth.users` identity row** — email, phone, password hash, and OAuth identities survive "deletion" | GDPR Art. 17 / CCPA | 🔴 Critical | **Documented, fix proposed** (§5.1) |
| C | **Data export omits location history, care notes, and wellness signals** | GDPR Art. 15/20 | 🟠 Serious | **Documented, fix proposed** (§5.2) |
| D | Primary-button and link **color contrast failed WCAG AA** site-wide (2.1:1 / 3.1:1) | ADA / WCAG 1.4.3 | 🔴→✅ | **Fixed in this branch** (§4) |
| E | **Placeholder business address** (`1234 Example Street`) in Privacy, Terms, DMCA, and footer | GDPR Art. 13 / CCPA | 🟠 Serious | **Needs real data** (§6.2) |
| F | Nested `<main>` landmarks, missing reduced-motion, SPA focus, heading skips | ADA / WCAG | 🟡→✅ | **Fixed in this branch** (§4) |
| G | Undisclosed processors: Google Analytics, **Sentry** | GDPR Art. 13 transparency | 🟠 | Sentry **disclosed in this branch**; GA pending decision A |
| H | **No age gate / COPPA enforcement** despite Kid Mode and family targeting | COPPA | 🟠 | **Needs decision** (§6.3) |
| I | No EU/UK **Article 27 representative** appointed | GDPR Art. 27 | 🟡 | **Needs decision** (§6.4) |

---

## 2. Required documents & pages — inventory

All of the documents a consumer app of this type is expected to publish **exist and are routed** (`website/src/App.tsx`):

| Document | Route | Present | Notes |
|----------|-------|:-------:|-------|
| Privacy Policy | `/privacy` | ✅ | Thorough; GDPR + CCPA/CPRA + 20-state disclosures, legal bases, retention, sub-processors, SMS/A2P. See gaps A, E, G. |
| Terms of Use | `/terms` | ✅ | Arbitration + class-action waiver + opt-out, Apple EULA terms, subscription/auto-renew disclosures. See gap E. |
| Cookie Notice | `/cookies` | ✅ | Claims cookieless analytics — **contradicted by GA** (gap A). |
| Accessibility Statement | `/accessibility` | ✅ | Claims WCAG AA + reduced motion; brought into line with reality this branch. |
| DMCA / Copyright Policy | `/dmca` | ✅ | §512 agent, counter-notice, repeat-infringer. See gap E. |
| Support / Contact | `/support` | ✅ | Email + FAQ; account deletion & cancellation documented. |
| Child & Teen Safety | `/child-safety` | ✅ | Policy text only; no technical age enforcement (gap H). |

**Verdict:** No required document is *missing*. The gaps are in **accuracy** (GA contradiction, placeholder address, undisclosed processors) and **backing mechanisms** (deletion/export completeness), not in coverage.

---

## 3. Methodology

- Manual read of every legal page, the layout/header/footer, the HTML shell generator (`pages/+onRenderHtml.tsx`), `_headers` (CSP/security), and global CSS.
- Two parallel deep-dive audits:
  - **Accessibility** — component-by-component WCAG 2.1 AA review of the marketing site.
  - **Privacy/GDPR mechanisms** — traced deletion, export, consent, retention, processors, COPPA, and security across edge functions, migrations, and both mobile apps.
- Contrast ratios computed against WCAG relative-luminance formula.

---

## 4. Accessibility (ADA / WCAG 2.1 AA)

### 4.1 What was already correct
`<html lang>` set · compliant viewport (zoomable, no `maximum-scale`) · skip link wired to `#main-content` · global `:focus-visible` ring · per-page `<title>`/meta · nav `aria-current`/`aria-label` · emoji decorations use `role="img"` + label · correct `<a>` vs `<button>` semantics · no public-facing forms (Support/Pricing use `mailto:` + native `<details>`), so labeling SC 3.3.2 does not apply.

### 4.2 Findings and fixes applied in this branch

| ID | SC | Issue | Fix |
|----|----|-------|-----|
| C1 🔴 | 1.4.3 | Primary button: white on `#2ECC71` ≈ **2.1:1** (every CTA site-wide) | Added `--green-accessible: #157F43` (**5.06:1** with white); applied to `.btn-primary`, `.btn-secondary`, and the `ErrorBoundary` button. |
| S1 🟠 | 1.4.3 | Body links: `#22a85c` on white ≈ **3.1:1** | Global `a` color → `--green-accessible`. |
| S2 🟠 | 1.3.1 / 4.1.2 | Nested/duplicate `<main>` (Layout's `<main>` + a second `<main>` in Privacy/Terms/Cookies/DMCA/Accessibility) | Inner `<main>` → `<div>` on all five legal pages. |
| M1 🟡 | 2.4.3 | SPA route change didn't move focus or scroll | Added `RouteFocusManager` in `App.tsx` (scroll-to-top + focus `#main-content`, `tabIndex=-1`) on navigation. |
| M2 🟡 | 2.3.3 | `prefers-reduced-motion` honored nowhere, contradicting the statement | Global reduced-motion media query in `index.css`. |
| M3 🟡 | 1.3.1 / 2.4.10 | Heading skips (Pricing h1→h3, Support h1→h3, Home h2→h4) | Reordered headings + matching CSS selectors on Home/Pricing/Support. |
| M4 🟡 | 1.4.3 | Footer secondary text ≈ 3.7:1; admin link dimmed to ~2:1 | `.footer-note`/`.footer-admin-link` → `--gray-400`; removed opacity. |
| m1 🟢 | 4.1.2 | Menu toggle had no `aria-controls` | Added `id="primary-navigation"` + `aria-controls`. |
| m2 🟢 | 1.1.1 | Blog hero `alt=""` on a meaningful image | `alt={post.title}`. |
| m3 🟢 | — | Statement overstated site conformance (contrast, "dark mode" on web) | Scoped dark-mode claim to the app; other claims now true post-fix. |

### 4.3 Remaining / recommended (not blocking)
- **Mobile-app WCAG** (VoiceOver labels, Dynamic Type to 200%, Voice Control) is asserted in the statement but was **not independently verified** in this pass. Recommend a device pass with VoiceOver + largest Dynamic Type before renewing the claim.
- Consider adding an automated a11y gate (axe-core in Vitest / Playwright) to CI to prevent regressions.

---

## 5. GDPR / CCPA — data-subject-rights mechanisms

### 5.1 🔴 Account deletion does not delete the authentication identity (Right to Erasure)
`delete_user_account()` (`supabase/migrations/00018_security_hardening.sql:139`) deletes from `push_tokens`, `checkins`, `notification_log`, `family_members`, owned `families`, and `public.users`. Child PII tables cascade correctly via `ON DELETE CASCADE`.

**Defect:** the FK is `public.users.id → auth.users(id) ON DELETE CASCADE`, which cascades **auth → public**, *not* public → auth. The RPC only touches `public.users`, so the Supabase **Auth row survives**: email, phone number, bcrypt password hash, Google/Apple OAuth identities, and sign-in metadata persist indefinitely after a user "deletes" their account. This is the most material erasure defect (GDPR Art. 17 / CCPA §1798.105).

**Proposed fix (new forward-only migration):** have `delete_user_account` also remove the auth identity — either `DELETE FROM auth.users WHERE id = p_user_id;` inside the `SECURITY DEFINER` function (which then cascades the public row away), or move deletion to an edge function that calls `supabaseAdmin.auth.admin.deleteUser()` (the admin client already exists — see `edge-functions/functions/auto-join/index.ts`). Signature is unchanged, so this is a safe `CREATE OR REPLACE`.

### 5.2 🟠 Data export is incomplete (Right to Access / Portability)
`export_user_data()` (`00010_gdpr_export_completeness.sql`, hardened in `00018`) returns profile, memberships, check-ins, requests, notification log, invite tokens (redacted), alerts, receiver settings, and push tokens. It was **never updated** for PII tables added later:
- `location_updates` (00012) — location history
- `care_notes` (00041) — free-text notes about receivers
- `wellness_signals` (00042) — health-derived signals

**Proposed fix:** extend the export RPC's JSON to include these three tables (additive, safe `CREATE OR REPLACE`).

### 5.3 Consent management — 🟡 partial
- **Location:** OS permission on-device + server gate `receiver_settings.location_tracking_enabled` (default `false`). Coordinates coarsened to ~110 m before upload (good minimization). *But* the enable toggle is owner-controlled, not held by the data subject being located, and there is **no stored consent record/timestamp**.
- **Analytics:** iOS uses TelemetryDeck (anonymous, hashed) — but there is **no in-app analytics opt-out** and no consent capture.
- **No consent-ledger / versioned ToS-&-Privacy acceptance** table anywhere in the schema.

### 5.4 Retention & minimization — ✅ mostly present
- `enforce_data_retention()` daily — check-ins per family `data_retention_days`, notification log > 90 days, expired invites (`00005`).
- `cleanup_old_location_data()` daily — deletes `location_updates` > 7 days (`00012`). Strong minimization on the most sensitive data.
- **Gap:** `care_notes` (free text) and `users.last_battery_level` / `last_seen_at` have **no purge** — they persist until account deletion.

### 5.5 Third-party processors — identified vs. disclosed
In use: Supabase, Contabo/Coolify, Cloudflare, TelemetryDeck, APNs, FCM, Twilio, Apple/Google billing, **Sentry**, **Google Analytics**.
- **Sentry** — now added to the Privacy Policy sub-processor list in this branch.
- **Google Analytics** — still undisclosed and, more importantly, contradicts the policy outright (§6.1). Also note the `_headers` CSP allows GA endpoints but **omits the Sentry ingest host** (`*.ingest.us.sentry.io`), so browser error reporting is currently blocked by CSP — worth reconciling.

### 5.6 Security of processing — ✅ largely solid
RLS enabled on all core + newer PII tables; `SECURITY DEFINER` functions re-check `auth.uid()`; strict CORS/JWT/webhook-secret auth + rate limiting on the edge server; iOS cert pinning; SMS "STOP"; token secrets redacted in export. Encryption-at-rest is deployment config (not in-repo) and could not be independently confirmed; care-note bodies and phone numbers are stored in plaintext columns.

---

## 6. Items requiring a business / legal decision or real data

### 6.1 🔴 Google Analytics vs. the "no-tracking" promise — **DECISION NEEDED**
`pages/+onRenderHtml.tsx:23-29` unconditionally loads GA4 (`G-J2H67EW9JY`) on every page, and `_headers` whitelists the GA endpoints. GA4 sets `_ga`/`_gid` cookies and transfers data to Google (US). Meanwhile:
- Cookie Notice: *"We do not use … behavioral-tracking cookies … no consent prompt is required."*
- Privacy Policy: *"We do not use third-party advertising or tracking SDKs … our website uses Cloudflare Web Analytics."*

This is both an **ePrivacy/GDPR prior-consent violation** (EU/UK) and a **false statement in a published policy** (FTC §5 / state UDAP exposure). Two clean resolutions:
1. **Remove GA** and rely on the cookieless Cloudflare Web Analytics the policy already describes → statements become true, no banner needed. *(Recommended — matches the brand's privacy-first positioning; also note the Cloudflare beacon token is still the placeholder `YOUR_CF_ANALYTICS_TOKEN`.)*
2. **Keep GA** → add a compliant consent banner (opt-in, GA blocked until consent, with reject-all) **and** rewrite the Cookie Notice + Privacy Policy to disclose GA and Google as a processor.

### 6.2 🟠 Placeholder business address — **REAL DATA NEEDED**
`1234 Example Street, Salt Lake City, UT 84101` appears in `Privacy.tsx`, `Terms.tsx`, `DMCA.tsx`, and `Footer.tsx` (each flagged *"update as required when finalized"*). GDPR Art. 13 and CCPA require the controller's real identity/contact; the DMCA agent address must be real to be effective. Provide the registered business address (and confirm the legal entity — pages say **Pearson Media LLC d/b/a Daily OK**).

### 6.3 🟠 COPPA / age gating — **DECISION NEEDED**
No birthdate field, age gate, or age verification exists, yet **Kid Mode** (`00014`) implies under-18 (potentially under-13) receivers are onboarded by a parent, with optional location + free-text notes about them. Policies state "13+", but nothing enforces it. Decide: add an age gate / parental-consent capture, or formally restrict onboarding to 13+ with an attestation.

### 6.4 🟡 EU/UK Article 27 representative — **DECISION NEEDED**
The Privacy Policy states no EU/UK establishment and relies on SCCs. If EEA/UK residents are actually served, GDPR/UK-GDPR Art. 27 requires **appointing** a representative (naming them in the policy), not merely stating none exists. Either appoint one, or (if not targeting the EEA/UK) make that explicit and reconsider the EEA-facing language.

---

## 7. Prioritized remediation roadmap

**Do before claiming "fully compliant":**
1. Resolve the **Google Analytics contradiction** (§6.1) — remove GA (recommended) or add consent + disclosure.
2. Ship the **`auth.users` deletion** migration (§5.1).
3. Ship the **export-completeness** migration (§5.2).
4. Replace the **placeholder address** everywhere (§6.2).

**Next:**
5. Decide **COPPA** posture and add enforcement/attestation (§6.3).
6. Add an **in-app analytics opt-out** and a **consent-record** table (§5.3).
7. Add **retention** for `care_notes` / battery / last-seen (§5.4).
8. Appoint (or formally decline) an **Art. 27 representative** (§6.4).
9. Reconcile the **CSP** (Sentry ingest host) and set the real **Cloudflare beacon token** (§5.5).

**Ongoing:**
10. Device-level **mobile a11y verification** (§4.3) and an **automated a11y CI gate**.

---

## 8. Changes applied in this branch

**Accessibility (website):** `src/index.css` (accessible green tokens for buttons/links, reduced-motion query, focus-target rule), `src/components/Footer.css` (contrast), `src/components/ErrorBoundary.tsx` (button color), `src/components/Layout.tsx` (focusable main), `src/components/Header.tsx` (`aria-controls`), `src/App.tsx` (`RouteFocusManager`), nested-`<main>`→`<div>` on `Privacy/Terms/Cookies/DMCA/Accessibility`, heading order on `Home/Pricing/Support` (+ CSS), `BlogPost.tsx` (image `alt`).

**Legal accuracy:** `Privacy.tsx` (disclosed **Sentry** processor), `Accessibility.tsx` (scoped dark-mode claim to the app).

**Docs:** this report.

**Verification:** `tsc -b` ✅, `vite build` ✅, targeted ESLint on changed files clean (pre-existing admin/BlogPost data-effect lint warnings are unrelated to these changes).

*Not changed here (require the decisions/data in §6, or are backend migrations warranting the release process in `CLAUDE.md`): Google Analytics, placeholder address, the two GDPR migrations, COPPA enforcement, Art. 27.*
