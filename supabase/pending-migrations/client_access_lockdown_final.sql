-- Daily OK: final client-access lockdown (STAGED — not yet a migration).
--
-- DO NOT move this into supabase/migrations/ until the conditions in
-- supabase/pending-migrations/README.md hold. It removes access that installed
-- builds below those versions still use, which CLAUDE.md "Backward
-- Compatibility" forbids in the same release that stops using it.
--
-- What 00063_client_access_lockdown left open, and why it can close now:
--
-- 1. Direct INSERT into checkins (policy "Receivers can insert own checkins",
--    00002, plus the 5-column INSERT grant from 00063 §2a). Only iOS
--    1.0.3-1.0.6 offline replay used it; 1.0.7+ replay through
--    process-checkin-response (commit 95fc15b). No Android build ever
--    inserted checkins directly. Once those iOS builds are below the floor,
--    every check-in goes through the edge function (service role).
--
-- 2. trg_checkins_client_insert_resolve / resolve_requests_on_client_checkin
--    (00063): resolved pending requests after that same direct insert. With
--    no client INSERT privilege left it can never fire (its WHEN is
--    is_client_role()), so it is dropped rather than left as dead code.
--
-- 3. transfer_family_ownership v1 (00045). It still accepts a receiver as
--    the new owner. iOS builds up to 1.0.9 (main at 3c4ff42) call only v1;
--    later iOS builds and Android call transfer_family_ownership_v2 (00058)
--    and fall back to v1 only on a server without v2. EXECUTE is revoked from
--    clients (the function is kept, so this is reversible with one GRANT and
--    the service role can still call it).
--
-- Not included: the users / families column revokes. They are staged
-- separately in member_column_privileges.sql (step 2 of 00067).
--
-- VERIFICATION (expected values after applying):
--   SELECT count(*) FROM pg_policies
--    WHERE tablename = 'checkins' AND cmd = 'INSERT';                        -- 0
--   SELECT has_table_privilege('authenticated','checkins','INSERT'),          -- f
--          has_column_privilege('authenticated','checkins','receiver_id','INSERT'), -- f
--          has_column_privilege('authenticated','checkins','mood','UPDATE'),  -- t (unchanged)
--          has_function_privilege('authenticated',
--              'transfer_family_ownership(uuid,uuid)','EXECUTE'),            -- f
--          has_function_privilege('authenticated',
--              'transfer_family_ownership_v2(uuid,uuid)','EXECUTE'),         -- t
--          has_function_privilege('service_role',
--              'transfer_family_ownership(uuid,uuid)','EXECUTE');            -- t
--   SELECT count(*) FROM pg_trigger
--    WHERE tgname = 'trg_checkins_client_insert_resolve';                    -- 0

BEGIN;

-- 1. No direct client check-in inserts.
DROP POLICY IF EXISTS "Receivers can insert own checkins" ON checkins;
REVOKE INSERT (receiver_id, family_id, checked_in_at, mood, source)
    ON checkins FROM authenticated;
REVOKE INSERT ON checkins FROM anon, authenticated;

-- 2. The compatibility trigger for that insert path.
DROP TRIGGER IF EXISTS trg_checkins_client_insert_resolve ON checkins;
DROP FUNCTION IF EXISTS resolve_requests_on_client_checkin();

-- 3. Ownership transfer only through v2 for clients.
REVOKE EXECUTE ON FUNCTION transfer_family_ownership(UUID, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION transfer_family_ownership(UUID, UUID) TO service_role;

COMMIT;
