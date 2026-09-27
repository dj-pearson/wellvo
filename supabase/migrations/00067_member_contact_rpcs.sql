-- Daily OK: self-profile and family phone-number RPCs.
-- Migration: 00067_member_contact_rpcs
--
-- ─── WHAT AND WHY ────────────────────────────────────────────────────────────
-- Family members can read each other's whole `users` row (00002 "Family
-- members can read each other"), so any member can pull another member's
-- email, phone and is_system_admin with users(*) or select=*. The same goes
-- for families.billing_* through select=* on families.
--
-- This is step 1 of 2. The apps now send explicit column lists that leave
-- email and phone out when they read OTHER people's rows, and get what they
-- still need through two functions:
--
--   get_my_profile()               the caller's own full users row.
--   family_contact_numbers(uuid)   phone numbers the caller may see:
--       - an active owner or co-caregiver (viewer) of a family gets the
--         numbers of every active member of that family;
--       - a receiver gets the numbers of that family's caregivers only
--         (owner and viewers), for "Call" / "Text <owner>";
--       - everyone gets their own number.
--     NULL family id means every family the caller belongs to (the
--     notification "Call" action only knows the receiver id).
--
-- Step 2, staged in supabase/pending-migrations/member_column_privileges.sql,
-- revokes column-level SELECT on users.email / phone / is_system_admin /
-- digest_last_sent_at and on families.billing_original_transaction_id /
-- billing_platform / billing_verified_at. It waits until the version floors cut off builds that
-- still read those columns directly (see that folder's README).
--
-- ─── BACKWARD COMPATIBILITY (CLAUDE.md §A) ───────────────────────────────────
-- Additive only: two new functions, no table, policy or grant on existing
-- objects changes. Every shipped build keeps working exactly as before.
--
-- Idempotent: safe to replay.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- The caller's own profile, every column. SECURITY DEFINER so it keeps
-- working after step 2 revokes column SELECT on email / phone /
-- is_system_admin (column privileges bind the row's owner too, and RLS can't
-- give them back). SETOF so "no profile yet" is an empty array, not an error.
CREATE OR REPLACE FUNCTION public.get_my_profile()
RETURNS SETOF public.users
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT u.* FROM public.users u WHERE u.id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.get_my_profile() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_profile() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_profile() TO authenticated, service_role;

COMMENT ON FUNCTION public.get_my_profile() IS
    'The caller''s own users row (all columns). Self-reads go through this so '
    'column-level SELECT on users.email/phone/is_system_admin can be revoked.';


-- Phone numbers the caller may see. Only ACTIVE members, like the users RLS
-- policy; an owner with no family_members row (older onboarding) is found
-- through families.owner_id. Blank numbers are left out.
CREATE OR REPLACE FUNCTION public.family_contact_numbers(p_family_id UUID DEFAULT NULL)
RETURNS TABLE (user_id UUID, family_id UUID, role public.user_role, phone TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH my_families AS (
        -- Families the caller is in, with the caller's role there. Owning the
        -- family wins over any membership row.
        SELECT f.id AS family_id,
               CASE WHEN f.owner_id = auth.uid() THEN 'owner'::public.user_role
                    ELSE fm.role END AS my_role
        FROM public.families f
        LEFT JOIN public.family_members fm
               ON fm.family_id = f.id
              AND fm.user_id = auth.uid()
              AND fm.status = 'active'
        WHERE auth.uid() IS NOT NULL
          AND (f.owner_id = auth.uid() OR fm.id IS NOT NULL)
          AND (p_family_id IS NULL OR f.id = p_family_id)
    ),
    people AS (
        SELECT m.user_id, m.family_id,
               CASE WHEN m.user_id = f.owner_id THEN 'owner'::public.user_role
                    ELSE m.role END AS role
        FROM public.family_members m
        JOIN public.families f ON f.id = m.family_id
        WHERE m.status = 'active'
          AND m.family_id IN (SELECT mf.family_id FROM my_families mf)
        UNION
        SELECT f.owner_id, f.id, 'owner'::public.user_role
        FROM public.families f
        WHERE f.id IN (SELECT mf.family_id FROM my_families mf)
    )
    SELECT DISTINCT ON (p.family_id, p.user_id)
           p.user_id, p.family_id, p.role, btrim(u.phone)
    FROM people p
    JOIN my_families mf ON mf.family_id = p.family_id
    JOIN public.users u ON u.id = p.user_id
    WHERE NULLIF(btrim(u.phone), '') IS NOT NULL
      AND (
            p.user_id = auth.uid()                       -- your own number
         OR mf.my_role IN ('owner', 'viewer')            -- caregivers: everyone
         OR p.role IN ('owner', 'viewer')                -- receivers: caregivers only
      )
    ORDER BY p.family_id, p.user_id,
             CASE p.role WHEN 'owner' THEN 0 WHEN 'viewer' THEN 1 ELSE 2 END;
$$;

REVOKE ALL ON FUNCTION public.family_contact_numbers(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.family_contact_numbers(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.family_contact_numbers(UUID) TO authenticated, service_role;

COMMENT ON FUNCTION public.family_contact_numbers(UUID) IS
    'Phone numbers the caller may see: all active members for an active '
    'owner/co-caregiver, caregivers only for a receiver, plus the caller''s '
    'own. NULL family = every family the caller is in.';

COMMIT;
