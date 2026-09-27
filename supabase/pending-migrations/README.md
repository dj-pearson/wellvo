# Staged migrations (not applied)

Files here are **not** migrations yet. `.github/workflows/supabase-migrations.yml`
triggers on `supabase/migrations/**` and runs only `supabase/migrations/*.sql`,
so nothing in this folder reaches any database until a person moves it.

Each file removes access that older installed builds still use, so it waits
until the version floors cut those builds off (CLAUDE.md, "Backward
Compatibility": add new shape, move readers, raise the floor, then retire the
old shape).

## client_access_lockdown_final.sql

Finishes `00063_client_access_lockdown`:

- drops the policy `"Receivers can insert own checkins"` and revokes the
  remaining 5-column `INSERT` grant on `checkins` from `authenticated`
  (and `anon`)
- drops the compatibility trigger `trg_checkins_client_insert_resolve` and its
  function `resolve_requests_on_client_checkin()` (they only served that insert)
- revokes `EXECUTE` on `transfer_family_ownership` (v1, 00045) from clients.
  The function stays, and `service_role` can still call it.

### Apply only when both floors are raised

1. **`MIN_SUPPORTED_IOS_APP_VERSION` >= the first App Store version that
   contains commit `4c8adff`**, where the app calls `transfer_family_ownership_v2`.
   `main` already ships `MARKETING_VERSION = 1.0.9` and still calls v1, so this
   branch has to go out as **1.0.10 or later**. Use that exact number, and bump
   `MARKETING_VERSION` on the release branch first (it still reads 1.0.9 here).
   This also covers the checkins insert: iOS 1.0.3 to 1.0.6 replay offline
   check-ins by inserting into `checkins` directly, and 1.0.7 and later don't.
2. **`MIN_SUPPORTED_ANDROID_APP_VERSION` >= the Play `versionName` that
   contains this branch.** No Android build on `main` inserts into `checkins`
   or calls transfer v1: `git grep` on main finds only `UPDATE`s of
   mood/location_label/kid_response_type, and no transfer RPC at all. So this
   floor is a safety margin, not a hard dependency. `versionName` is `1.0.0`
   on both `main` and this branch, so bump it (for example to `1.0.1`, with
   `versionCode` 10001) before you rely on it.

### Why raising the floor is what makes this safe

- Current builds send `X-App-Version` and `X-App-Platform` on every edge call.
  iOS has sent them since commit `41f5d2e`, which is in 1.0.8 and possibly in
  late 1.0.7 builds. Android sends them from this branch on. Current builds
  also read `GET /app-config` at launch and on foreground. A build below the
  floor gets the blocking update screen, and every edge call it makes returns
  `426 {"error":"update_required","update_url":...}`.
- Older builds (iOS 1.0.6 and earlier, Android before this branch) send no
  version header, so the edge server can't identify them and lets them through.
  Those are exactly the builds that use the access this file removes. For them,
  **applying this file is the enforcement**: their direct check-in insert and
  their v1 transfer start failing with `permission denied`. Raise the floors,
  let the update screen move current users forward, then apply.

### How to apply

1. In Coolify, set `MIN_SUPPORTED_IOS_APP_VERSION` and
   `MIN_SUPPORTED_ANDROID_APP_VERSION` on the edge-functions service and
   redeploy. They default to `0.0.0`, which means no floor. Check the new
   values with `curl https://functions.dailyok.net/app-config`.
2. `git mv supabase/pending-migrations/client_access_lockdown_final.sql
   supabase/migrations/000NN_client_access_lockdown_final.sql`. Use the next
   free number: 00064 was skipped and the highest today is 00066, so this
   would be 00067 unless others land first.
3. Merge through the normal `develop` → `release/*` → `main` flow. The
   migrations workflow applies it after the production approval and the
   pre-migration backup.
4. Run the VERIFICATION block at the top of the file against prod.

Tested on a scratch Postgres 16. After migrations 00001–00066, a receiver's
direct insert and an owner's v1 transfer worked. After this file, both got
`permission denied`. v2 transfer, receiver mood updates and service-role
check-in inserts kept working. Running the file a second time does no harm.
