# Daily OK — Project Configuration

## Overview
Daily OK is a daily check-in app for families. Owners send check-in requests; Receivers tap "I'm OK." Escalation alerts fire if no response.

> **Brand vs. identifier split (load-bearing — US-IOS109).** The product was renamed from "dailyok" to "wellvo" partway through. These two namespaces are BOTH live and must not be conflated:
> - **`com.wellvo.ios`** — the iOS bundle id, App Group (`group.com.wellvo.ios`), shared Keychain group (`com.wellvo.ios.shared`), unified-logging subsystem, and the AASA `appID` prefix (`<TeamID>.com.wellvo.ios`). Extension bundle ids extend it (`com.wellvo.ios.NotificationService`, `…DailyOKWidgets`, `…watchkitapp`). StoreKit product ids are `net.wellvo.*`.
> - **`dailyok` / `dailyok.net`** — the display name ("Daily OK"), website, URL scheme (`dailyok://`), edge-functions host (`functions.dailyok.net`), and the Universal Links domain (`applinks:dailyok.net`). Android Play products are still `net.dailyok.*` (the backend recognizes both namespaces).
>
> When configuring signing, AASA, entitlements, or app groups, use the **`com.wellvo.ios`** identifier — never the `dailyok` brand domain.

## Tech Stack
- **iOS App**: Swift 5.9+, SwiftUI, MVVM, iOS 18+, StoreKit 2 (deliberate floor; all targets + Package.swift pin 18.0 to use Live Activities/Control Center/App Intents without availability gating — US-IOS085)
- **Android App**: Kotlin 1.9+, Jetpack Compose, MVVM, API 26+ (Android 8.0+), Google Play Billing
- **Edge Functions**: Deno (TypeScript), single HTTP server routing to 7 function handlers
- **Database**: PostgreSQL via self-hosted Supabase, RLS, pg_cron
- **Website**: React + TypeScript + Vite, deployed to Cloudflare Pages
- **CI/CD**: GitHub Actions (iOS build, Android build, edge function Docker deploy, Supabase migrations)
- **Hosting**: Contabo VPS via Coolify (Docker)

## Directory Structure
```
ios/                    # iOS app (Xcode project)
  Daily OK/
    App/                # AppDelegate, Daily OKApp, AppState, ContentView
    Models/             # CheckIn, User, Family, ReceiverSettings, etc.
    Services/           # Auth, CheckIn, Subscription, Push, Offline, Analytics
    ViewModels/         # Auth, Dashboard, Onboarding, Receiver
    Views/              # SwiftUI views organized by feature
    Utilities/          # Configuration, Keychain, NetworkRetry
edge-functions/         # Deno edge functions server
  server.ts             # Main HTTP router (CORS, rate limiting, auth, logging)
  shared/               # auth.ts, supabase.ts, apns.ts, sms.ts, rate-limiter.ts, logger.ts
  functions/            # Individual function handlers (7 endpoints)
website/                # React + Vite website
  src/
    pages/              # Home, Pricing, Privacy, Terms, Support, NotFound
    components/         # Header, Footer, Layout, ErrorBoundary
android/                # Android app (Gradle/Kotlin project)
  app/
    src/main/
      java/net/dailyok/android/
        di/             # Hilt dependency injection modules
        data/           # Models, Room entities, DAOs
        network/        # API service, error handling, retry
        services/       # Auth, CheckIn, Family, Location, Push, Offline, Subscription, Analytics
        viewmodels/     # Auth, Dashboard, Onboarding, Receiver, Settings, History, Family
        ui/             # Jetpack Compose screens organized by feature
        util/           # Configuration, SecureStorage, Extensions
supabase/migrations/    # SQL migrations (00001-00006)
.github/workflows/      # CI/CD pipelines
coolify/                # Deployment guide and backup script
```

## Build Commands
```bash
# Website
cd website && npm install && npm run build    # Build
cd website && npm run dev                     # Dev server

# Edge Functions (requires Deno)
cd edge-functions && deno run --allow-net --allow-env server.ts

# Docker (edge functions)
docker compose up --build

# iOS (requires Xcode on macOS)
xcodebuild -project ios/Daily OK.xcodeproj -scheme Daily OK build

# Android (requires JDK 17+)
cd android && ./gradlew assembleDebug         # Debug build
cd android && ./gradlew assembleRelease       # Release build
cd android && ./gradlew test                  # Unit tests
```

## Key Architecture Decisions
- Edge functions run as a single Deno HTTP server (not Supabase-hosted Edge Functions)
- CORS restricted to https://dailyok.net (configurable via ALLOWED_ORIGIN env var)
- Rate limiting is in-memory (resets on container restart, single-instance deploy)
- iOS app reads Supabase URL/keys from BuildConfig.xcconfig → Info.plist
- pg_cron triggers edge functions via HTTP with service role key
- Migrations require GitHub environment approval + pre-migration backup

## Common Gotchas
- iOS: Supabase config comes from Info.plist, injected via BuildConfig.xcconfig
- Android: Supabase config comes from BuildConfig fields, set in build.gradle.kts from local.properties
- Android: EncryptedSharedPreferences replaces iOS Keychain for secure storage
- Android: FCM replaces APNs — edge functions must support both platforms (check push_tokens.platform)
- Android: WorkManager for background tasks (heartbeat, location) — minimum 15-min interval
- Android: POST_NOTIFICATIONS runtime permission required on Android 13+ (API 33)
- Edge functions: Deno, not Node.js — use Deno APIs and import maps (deno.json)
- CORS: Native apps (iOS + Android) don't send Origin headers; CORS logic must allow missing Origin
- Rate limiter: In-memory, not shared across instances (fine for current single-container setup)
- Website: Cloudflare Pages reads _headers and _redirects from public/ directory
- Migrations: Each migration wraps in BEGIN/COMMIT; verify with table/RLS/trigger counts

## Task Tracking
- `prd.json` — User stories with `passes: true/false` status (Ralph loop format)
- `progress.txt` — Append-only log with story status and iteration details
- PRD: `Daily OK-PRD-v1.md` — Full product requirements document

---

## Critical Rules

These rules override default behavior. Claude MUST follow them.

### 1. Branch first, code second

**Before writing or pushing code on any non-trivial task, Claude must confirm the target branch with the user.** A "non-trivial task" is anything that edits committed code, migrations, workflows, or app config — i.e. anything that would end up in a commit. Pure read/research is exempt.

The check is one short question to the user before the first Edit/Write/commit. Map common request phrasings to branches as follows:

| If the user says something like…                                                | Branch from | Target branch          |
| ------------------------------------------------------------------------------- | ----------- | ---------------------- |
| "production bug", "users are broken right now", "hotfix", "critical", "P0"      | `main`      | `hotfix/<short-desc>`  |
| "new feature", "add X", "let's build…", "experiment", "WIP", "POC"              | `develop`   | `feat/<short-desc>` or `claude/<short-desc>-XXXX` |
| "fix bug" (not customer-down), "refactor", "cleanup", "docs", "test"            | `develop`   | `feat/<short-desc>` or `claude/<short-desc>-XXXX` |
| "release prep", "cut a release", "version bump", "App Store / Play submission"  | `develop`   | `release/<x.y.z>`      |
| "rebase release branch", "merge develop into release"                           | n/a         | existing `release/*`   |

If the request is ambiguous between hotfix and feature (e.g. "fix the wonky onboarding copy"), default to **feature off `develop`** and ask. Never start work directly on `main`, `develop`, or an unrelated `release/*`/`hotfix/*` branch.

### 2. Never push to protected branches

Never push directly to `main`, `develop`, `release/*`, or `hotfix/*` (the branch itself is protected against force-push and deletion; hotfix branches do allow direct commits while the hotfix is being built, but the merge to `main` must be a PR). Always open a PR.

### 3. Database & API migrations are forward-only across releases

See "Backward Compatibility" below. Any destructive change must be split into at least two releases.

---

## Branching & Release

The branching model is a slimmed-down Git Flow adapted to Daily OK's surfaces (iOS App Store, Google Play, edge functions on Coolify, website on Cloudflare Pages, self-hosted Supabase).

### Branch map

| Branch / pattern                | Branches from           | Merges into             | Deploys to                                                                                                       | Purpose                                                                 |
| ------------------------------- | ----------------------- | ----------------------- | ---------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `main`                          | —                       | —                       | **Production**: App Store / Play Store builds, edge functions Docker image to ghcr.io, Supabase migrations against prod, Cloudflare Pages prod site | Merge-only. Every merge is a release candidate. Tagged on release.      |
| `develop`                       | `main` (initial)        | `release/*`, `hotfix/*` back-merge | **Staging** *(not wired up yet — see follow-ups)*: TestFlight internal, Play internal track, staging edge functions, staging Supabase, CF Pages preview | Long-lived integration branch. Where feature PRs land.                  |
| `feat/<short-desc>` or `claude/<short-desc>-XXXX` | `develop`               | `develop`               | Per-branch CF Pages preview only. No mobile builds, no migrations run.                                            | Single feature or fix. Squash-merge into `develop`.                     |
| `release/<x.y.z>`               | `develop`               | `main` (then back-merge to `develop`) | Release candidate builds: TestFlight external, Play closed/open testing, staging edge functions for final smoke   | Stabilization branch for a specific version. Only bug fixes + version bumps; no new features. |
| `hotfix/<short-desc>`           | `main`                  | `main` (then back-merge to `develop` and any open `release/*`) | Production after merge. Same deploy targets as `main`.                                                            | Emergency prod fix that skips queued features on `develop`.             |

### Release flow

1. **Feature work** → branch off `develop` as `feat/foo` or `claude/foo-abcd`. PR back into `develop`. CI runs build + tests on the PR. Squash-merge.
2. **Cut a release** → branch `release/x.y.z` off `develop`. Bump versions (iOS `MARKETING_VERSION`, Android `versionName`/`versionCode`, edge functions if you tag them). Submit iOS to App Store Connect, Android to Play Console. Fix any review feedback only on `release/x.y.z` (cherry-pick to `develop` or back-merge).
3. **Release ships** → PR `release/x.y.z` → `main`. After merge, tag `vx.y.z` on `main`. Back-merge `main` → `develop` so any release-only fixes return to integration.
4. **Hotfix** → branch `hotfix/foo` off `main`. Commit fixes directly on the hotfix branch (allowed by ruleset). PR `hotfix/foo` → `main`. After merge, tag, then back-merge `main` → `develop` AND `main` → any open `release/*`.

### Rules of thumb

- **Hotfixes always branch from `main`, never from `develop`.** `develop` may contain unreleased features that aren't ready to ship.
- **Web-only changes during mobile review** — ship them via a normal `feat/* → develop → release/web-only → main` flow (or just `feat/* → develop`, then a release PR `develop → main` that only touches `website/` paths). The mobile workflows are path-filtered to `ios/**` and `android/**`, so they won't fire.
- **Edge-function-only changes** — same: `feat/* → develop`, then `develop → main` via PR; the edge-functions workflow is path-filtered to `edge-functions/**`.
- **Supabase migrations** — see "Backward Compatibility" below. Migrations land on `develop`, then ride to `main` in a release. **Migrations that are not backward-compatible with the currently-shipped mobile builds must wait** until `MIN_SUPPORTED_*_VERSION` catches up.
- **Never force-push** `main`, `develop`, `release/*`, or `hotfix/*` (ruleset enforces this).
- **Never merge `develop` → `main` directly outside a `release/*` or `hotfix/*` PR.** Always go through a release branch so there's a stabilization window.
- **Never delete** `main`, `develop`, `release/*`, or `hotfix/*` (ruleset enforces this). Delete `feat/*` / `claude/*` after merge as normal.
- **Don't pile features into `release/*`.** If new work is needed, it goes to `develop`; `release/*` only takes bug fixes and version bumps for that release.

### Versioning

- Tag releases on `main` as `v<major>.<minor>.<patch>`.
- iOS marketing version + Android `versionName` should match the tag. Build numbers (`CFBundleVersion`, `versionCode`) are monotonically increasing per platform regardless of marketing version.
- Edge functions: optional `edge-vYYYY.MM.DD.N` tag for traceability; Docker images on ghcr.io are tagged with the commit SHA already.

---

## Backward Compatibility (load-bearing surfaces)

Daily OK has live users with installed iOS and Android apps that may lag the latest store version by weeks or months. **Any client an active user still runs is a constraint on the backend.** Define and respect:

```
MIN_SUPPORTED_IOS_APP_VERSION       // bump only when force-update is shipped
MIN_SUPPORTED_ANDROID_APP_VERSION   // bump only when force-update is shipped
```

(Currently these are not defined as constants. Follow-up: add to `edge-functions/shared/config.ts` and have the auth/checkin endpoints reject older builds with a force-update payload. Until that exists, treat the *oldest store-approved build* as the floor.)

The multi-release deprecation flow applies to **every** persistent shape below:

> **Add new shape → dual-write/dual-read → migrate readers off old shape → wait ≥1 store release at the new `MIN_SUPPORTED_*_VERSION` → retire old shape**

### A) Supabase / PostgreSQL

**Always safe (single release):**
- `CREATE TABLE` (new table)
- `ADD COLUMN ... NULL` with a safe default (no `NOT NULL` on existing data yet)
- `CREATE INDEX CONCURRENTLY` (use `CONCURRENTLY` to avoid locks)
- New RLS policies that are additive (more permissive paths), not replacements
- New `RPC` (Postgres function) — never modify an existing one's signature
- New pg_cron job
- New enum value **at the end** of the enum (`ALTER TYPE ... ADD VALUE 'foo'`)

**Never do in a single release:**
- `DROP COLUMN` — first stop writing it, then stop reading it, ship that, *then* drop in a later release
- `DROP TABLE`
- `RENAME COLUMN` / `RENAME TABLE` — clients reference these by name; split into add-new + dual-write + migrate-readers + drop-old across 2+ releases
- Adding `NOT NULL` or tightening `CHECK` constraints on existing columns — backfill first in release N, enforce in release N+1
- Changing a column's type (`ALTER COLUMN ... TYPE ...`) when the on-the-wire JSON shape changes
- Removing or renaming enum values (`ALTER TYPE ... RENAME VALUE` / dropping a value via re-creation) — clients may still send them
- Reducing the parameter list of an existing RPC, or removing an RPC entirely — apps in the wild still call it
- Tightening RLS so previously-allowed reads/writes now fail
- Deleting a pg_cron job that an in-flight client expects to have run
- Tightening foreign keys (`ON DELETE` behavior change) without verifying existing data

**Migration discipline:**
- Each file in `supabase/migrations/` is numbered sequentially and wrapped in `BEGIN; ... COMMIT;`.
- Migrations only run from `main` (via `supabase-migrations.yml` workflow + production environment approval + pre-migration backup).
- A migration that is destructive against currently-shipped clients must not merge to `main` until the prerequisite client release is at or below `MIN_SUPPORTED_*_VERSION`.

### B) Edge function HTTP API

The edge functions are a public API consumed by installed iOS and Android apps. Treat the request/response JSON shapes as a versionless public contract.

**Always safe:**
- New endpoints
- New **optional** request fields (server tolerates missing)
- New response fields (clients ignore unknown keys — verify the iOS/Android decoders do this; Swift `Decodable` ignores extras by default; Kotlin/Moshi requires `@JsonClass(generateAdapter = true)` with non-strict)
- Looser auth requirements (e.g. allow anonymous on an endpoint that previously required auth) — only if intentional
- Adding response fields with a safe default

**Never do in a single release:**
- Remove or rename an endpoint
- Remove or rename a request/response field
- Tighten a required request field (e.g. make optional → required, or narrow accepted enum values)
- Change a field's type (`string` → `number`, `array` → `object`)
- Change the meaning of an HTTP status code (e.g. previously `200 {ok: false}`, now `400`)
- Tighten rate limits below what an in-flight client may legitimately hit on its retry schedule

**Versioning approach:** prefer additive evolution over a new path. If you must do a breaking change, add a new endpoint (`/v2/foo`), dual-serve both, migrate clients over `MIN_SUPPORTED_*_VERSION` cycles, then retire `/v1/foo`.

### C) Mobile app on-device state

iOS and Android both persist data on-device (Keychain / EncryptedSharedPreferences, Room DB on Android, UserDefaults on iOS). When the user upgrades, the *new* app reads the *old* app's data.

**Always safe:**
- Adding new keys / new Room columns with `defaultValue` and `@ColumnInfo(defaultValue=…)` / Room auto-migrations
- Adding new optional fields to encoded structs (Codable / Moshi)

**Never do in a single release:**
- Renaming a Room table/column without a migration that copies data
- Renaming a `UserDefaults` / `EncryptedSharedPreferences` key without a one-time read-old-write-new shim on first launch
- Changing the `Codable`/Moshi shape of a value that's already serialized to disk
- Bumping Room `version` without a migration (Room will throw at runtime)

### D) Push notification token / platform contract

`push_tokens.platform` is `'ios' | 'android'`. Never reuse those values or change their meaning. New platforms (e.g. `'web'`) are additive.

### E) Subscription state (StoreKit 2 / Google Play Billing)

- Never delete or rename product IDs in App Store Connect / Play Console; create new ones and migrate.
- The mapping from store product ID → tier is checked in `supabase/migrations` and edge function code; keep all historical product IDs recognized as long as any subscriber may still hold one.

### Authoring checklist for a PR that touches persistent state

- [ ] If it touches `supabase/migrations/**`, is the change in the "always safe" list, or is it split across releases?
- [ ] If it touches `edge-functions/**` JSON shapes, does the oldest still-supported mobile build still parse the response and produce a valid request?
- [ ] If it touches mobile on-device persistence (Room, UserDefaults, Keychain keys), is there a migration / shim for users upgrading from the previous build?
- [ ] If it removes anything, has the deprecation flow run for at least one full release cycle?
- [ ] PR description names which release this is targeted at and which `MIN_SUPPORTED_*_VERSION` it assumes.

<!-- SELVEDGE:START -->
## Pearson Media — shared context

*Managed from the vault. Edit `14 - Resources/Shared CLAUDE Block.md` in the vault; direct edits between these markers are overwritten once a sync exists. Everything outside them is yours and is never touched.*

**The memory vault.** Portfolio-wide memory lives in the **Hermes** vault at `<your-home>\Documents\Hermes` (override with `HERMES_VAULT_PATH`; remote: https://github.com/dj-pearson/Hermes). It holds the profile, the map of every project, and cross-project knowledge. Read `VAULT-INDEX.md` there when a task needs context beyond this repo. This repo's own `CLAUDE.md`, `~/.claude` memory, and skills remain authoritative for work inside it — the vault supplements them, never replaces them.

**Name the project.** Pearson Media runs a portfolio of projects on a shared stack. Never say "the app," "the repo," or "production" without naming which one. A right answer about the wrong project is a wrong answer.

**The shared stack.** React + TypeScript + Vite, Tailwind, shadcn/ui, self-hosted Supabase, Cloudflare Pages, Coolify on Contabo, Stripe. A problem solved in one repo is usually already solved for this one — check the vault before solving it twice.

**Secrets are references, never values.** Never write a password, key, or token value into a note, summary, commit, or setup doc; name where it's stored instead. Loose credential files exist under your `Documents` folder — never read one into a document.

**Never delete what Claude Code relies on.** Repo `CLAUDE.md` files, `~/.claude/projects/*/memory/`, `.claude/skills/`, settings. Copy from them freely; removing or stubbing them is Dj's call alone.

**Evidence only.** Verify state from the actual file or command before claiming anything is done or in place. If unsure, say so and go find out.

**Operating principles.** Distilled from the ADE Hub's design rules (the Server repo's `hub/CLAUDE.md`, with the reasoning in its `docs/engineering-log.md`); they hold in every repo.

1. **Unmeasured is not zero, and a real zero stays zero.** A gap reads `Unavailable - <reason>`. A floor is labelled a floor: it can prove a target was hit, never that it was missed. An empty result that could mean "nothing happened" or "the read failed" says which. A total inherits the honesty of its rows, and a cached figure states its age.
2. **Read-only by default; gate on consequence, not on file location.** Anything that starts autonomous work, sends outward or touches a production box waits for approval; storing local config does not. Stopping something is never gated; starting it is.
3. **Never a second, weaker path into production.** Use the repo's own migrator and deploy path.
4. **Report, don't ration.** No cost cap, failure counter or WIP limit that stops work mid-run; report the number and let a person decide.
5. **Report drift; never resolve it silently.**
6. **A fix instruction names a remedy that can work**, and says when it is one example of several.
7. **Declare once and import it, derive what can be derived, and check a table against reality in both directions.** A duplicated literal is how two truths come to disagree.
8. **Measure; never assert a saving.** An estimate says it is one.
9. **Refuse, never truncate.** If what was approved can't be done whole, refuse; doing part of it and reporting success does something nobody approved.
10. **Assert on behaviour, not on wording, and give every negative check a counter-assertion** that proves it still fires. A green unit test on a pure function is not a working feature; look at the rendered page.
11. **Record refusals with their reasoning** so they are not silently re-proposed. A recorded refusal is not a ban: re-propose it openly, with what has changed.

**Write like a person.** Every model was trained on the same corpus, so the default register is recognisable within a sentence and it lands in commits, PR bodies, docs, UI copy and error strings alike. State the point first, then support it. Have an opinion; asked which of two, name one. Use real names and numbers, not categories. Never label your own significance ("important", "crucial", "worth noting", "notably"); if it matters the reader will see it. Banned outright: *delve, dive into, deep dive, unpack, shed light on, pave the way, usher in, tap into, supercharge, unlock, elevate, empower, streamline, curate, showcase, boast, groundbreaking, cutting-edge, transformative, game-changing, innovative, pivotal, invaluable, meticulous, bespoke, vibrant, multifaceted, holistic, testament, tapestry, synergy, cornerstone, treasure trove, plethora, myriad, moreover, furthermore, additionally.* Banned decoratively but fine literally: *navigate, harness, leverage, robust, comprehensive, landscape, realm, journey*; the test is whether a reader could check the claim. Banned phrases: *"In today's…", "It's important/worth noting", "When it comes to", "At its core", "At the end of the day", "This is where X comes in", "Let's break it down", "plays a crucial role", "cannot be overstated", "underscoring the importance of", "highlighting the need for"*, and the whole chat register (*"Great question!", "Absolutely!", "I'd be happy to", "Let me know if you need anything else", "I hope this helps"*). Banned structures, which imitate insight without carrying any: *"not just X, it's Y"*, *"not only X but Y"*, *"this isn't about X, it's about Y"*, *"No X. No Y. Just Z."*, the rule of three that goes abstract on the third item, the rhetorical question as a transition, and closing with a summary of what was just read. **At most one em dash** per piece of writing, never as the default connector; use commas, parentheses and semicolons. Vary sentence and paragraph length deliberately. Uniform 18-word sentences are the signature that survives every word-level edit. Use contractions. Don't restate the question, don't open with a sweeping scene-setter, don't over-format (no emoji as structure, no header on a three-paragraph answer, no table for two rows). The one allowed exception is a **bold lead-in used as a heading** in a reference document like this one; a *run* of "**Bold term:** one sentence" bullets standing in for prose is the tell.

**Plain characters only.** Generated text carries Unicode that renders as ordinary punctuation, as ordinary whitespace, or as nothing at all, and it survives review precisely because it looks correct. **Anything a machine parses is ASCII unless the content requires otherwise**: code, config, JSON, YAML, CSV, SQL, regex, env values, filenames, URLs, commit subjects. Straight quotes `'` `"`, hyphen-minus `-`, three dots for an ellipsis, one ordinary space between words. Never emit curly quotes (U+2018/2019/201C/201D), en/em dashes (U+2013/2014), U+2026 ellipsis, U+2212 minus or U+2032 primes into code; a look-alike character in a PowerShell string or a SQL literal is a runtime failure, which is how `backup-databases.ps1` and `ssl-check.ps1` sat unparseable for months. Never emit a no-break space (U+00A0, and U+202F/2007/2009/2002/2003/3000), which breaks shell word-splitting, `grep` and column parsing while looking exactly like a space, or U+2028/U+2029, which are valid JSON and a syntax error inside a JS string literal. **Never emit an invisible or bidi character anywhere:** U+200B-U+200F, U+2060-U+2064, U+FEFF, U+00AD, U+034F, U+180E, the bidi controls U+202A-U+202E and U+2066-U+2069, and above all the Unicode tag block **U+E0000-U+E007F**, which encodes arbitrary ASCII invisibly and is the usual carrier for text a reviewer cannot see. Avoid homoglyphs (Cyrillic a/e/o/p/c/x, Greek omicron, fullwidth Latin, mathematical alphanumerics for bold): an identifier holding one compares unequal to the identifier it appears to be. Prose may use real typography and real accented names; prose may not carry characters that don't render. The one exception is a deliberate, load-bearing use, which carries a comment saying why. Scan with `rg -n '[\x{0000}-\x{0008}\x{000B}\x{000C}\x{000E}-\x{001F}\x{00A0}\x{00AD}\x{034F}\x{061C}\x{180E}\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{2066}-\x{2069}\x{FEFF}\x{E0000}-\x{E007F}]'`. The C0 control range and the no-break space are in it because the older scan missed a live instance: a stray U+0008 backspace inside a regex in the Server repo's `hub/test/ui-smoke.mjs` disabled a test guard for as long as the guard existed.

**Terminal output is scrollback, not a report.** Answer first — no "I'll start by", no restating the request, no narrating tool calls the transcript already shows. Don't summarise a diff the reader can see or paste back code you just wrote; one line naming what changed and where, with `file:line` because it's clickable. Length matches the question: a yes/no gets a yes/no plus the clause that makes it trustworthy, and under about six lines there are no headers, bullets or tables. Report actual output, not a paraphrase: quote the failing assertion, say what was skipped, say plainly what's verified and what isn't. No emoji and no status theatre; "246 tests, 246 passing" beats "✅ All tests passing!" and is falsifiable. Don't close with an offer of more help or unrequested next steps: ask a real question, or name the real remaining work. Commits are imperative, what and why, no launch copy. PR bodies say what changed, why, how it was verified, and what's still open.

**UI has a craft floor.** Every model trained on the same SaaS templates, so the *default* frontend output is a recognizable handful of tells — and Tailwind + shadcn/ui puts each of them one autocomplete away. Treat the following as the category's defaults rather than as bans: the brief's own words can earn any of them, but reaching for one on a free axis means you were not deciding. Refuse **purple/blue gradients and gradient text** (emphasis comes from weight and size); **Inter or a system default as the type *choice***; a colored **`border-left`/`border-right` above 1px** on cards, list items, callouts or alerts — the single most recognizable tell; grids of **same-size icon-tile + heading + text cards** as the page structure, and **cards nested in cards**; a **1px border under a wide soft shadow** (declare elevation once — border *or* shadow); **gray text on colored surfaces** (tint secondary text from the surface hue or the foreground); **bounce/elastic easing**; **monospace as a costume** for "technical" rather than for code, data or measurement; and a **tracked uppercase eyebrow over every section**. Keep body measure at 65–75ch, tracking no tighter than -0.04em, and card radii at 12–16px.

**Check UI, don't just intend it.** `npx impeccable detect <path>` runs 60 deterministic anti-pattern rules with no install, no API key and no LLM — it works from any repo, so there is no excuse for asserting a UI is clean. Use the `/impeccable` skill (`audit`, `critique`, `polish`, `colorize`, `typeset`) for the judgement calls it cannot make. Source: [Impeccable](https://github.com/pbakaus/impeccable), Apache 2.0.
<!-- SELVEDGE:END -->
