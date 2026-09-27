-- Daily OK: hide members' email / phone / admin flag and families' billing
-- receipt columns from clients (STAGED — not yet a migration).
--
-- DO NOT move this into supabase/migrations/ until the conditions in
-- supabase/pending-migrations/README.md ("member_column_privileges.sql") hold.
-- Installed builds older than the release that shipped 00067 read these
-- columns directly (users(*), select=*, users?select=display_name,phone), and
-- they would fail with "permission denied for table users" (whole request,
-- not just the column).
--
-- Step 2 of 2. Step 1 was 00067_member_contact_rpcs plus the app changes:
-- every client read of users / families names its columns, self-reads use
-- get_my_profile(), and other members' phone numbers come from
-- family_contact_numbers().
--
-- How: PostgreSQL column privileges. Table-level SELECT is revoked and SELECT
-- is granted back on every column except the hidden ones. RLS still decides
-- WHICH rows; the grant decides WHICH columns. Column privileges apply to
-- the row's own user too (RLS can't widen them), which is why self-reads of
-- email / phone go through get_my_profile() (SECURITY DEFINER).
--
-- Hidden from clients (anon + authenticated):
--   users.email, users.phone, users.is_system_admin, users.digest_last_sent_at
--   families.billing_original_transaction_id, families.billing_platform,
--   families.billing_verified_at
--
-- Still readable (explicit lists below): everything the apps and the website
-- select today. families.billing_user_id stays readable: iOS shows a
-- co-caregiver "you pay for this family" / "<ex-owner> pays" from it.
--
-- Not changed: INSERT / UPDATE / DELETE privileges (the guard triggers from
-- 00051/00059 still police writes), service_role (edge functions), and every
-- SECURITY DEFINER function (they run as the owner).
--
-- NOTE for later migrations: a column added to users or families after this
-- runs is NOT readable by clients until it is granted explicitly
-- (GRANT SELECT (new_col) ON public.users TO authenticated).
--
-- VERIFICATION (run against prod after applying):
--   SELECT has_column_privilege('authenticated', 'public.users', 'phone', 'SELECT');           -- f
--   SELECT has_column_privilege('authenticated', 'public.users', 'display_name', 'SELECT');    -- t
--   SELECT has_column_privilege('authenticated', 'public.families', 'billing_platform', 'SELECT'); -- f
--   SELECT has_column_privilege('authenticated', 'public.families', 'billing_user_id', 'SELECT');  -- t
--   SELECT has_table_privilege('authenticated', 'public.users', 'UPDATE');                      -- t
--
-- ROLLBACK (one statement per table):
--   GRANT SELECT ON public.users, public.families TO authenticated;
--
-- Idempotent: safe to replay.

BEGIN;

-- ── users ────────────────────────────────────────────────────────────────────
REVOKE SELECT ON public.users FROM anon, authenticated;
GRANT SELECT (
    id,
    display_name,
    role,
    avatar_url,
    timezone,
    created_at,
    updated_at,
    last_seen_at,
    last_battery_level,
    last_app_version,
    digest_frequency,
    digest_hour
) ON public.users TO authenticated;

-- ── families ─────────────────────────────────────────────────────────────────
REVOKE SELECT ON public.families FROM anon, authenticated;
GRANT SELECT (
    id,
    name,
    owner_id,
    subscription_tier,
    subscription_status,
    subscription_expires_at,
    free_tier_expires_at,
    max_receivers,
    max_viewers,
    created_at,
    data_retention_days,
    billing_user_id
) ON public.families TO authenticated;

COMMIT;
