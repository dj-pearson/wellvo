-- Daily OK: Auth & onboarding — no pairing-code oracle, a self-only Apple link
-- check.
-- Migration: 00060_auth_onboarding_integrity
--
-- ─── WHAT AND WHY ────────────────────────────────────────────────────────────
-- 1. guard_invite_tokens_client_write(): a client INSERT can no longer choose
--    its own pairing_code.
--
--    00016 made pairing_code UNIQUE among unused invites, and the RLS policy
--    "Owners can manage invite tokens" (FOR ALL) lets any owner insert into
--    their own family. Any account can become an owner (a free family is one
--    insert away), and the 00058 INSERT branch left pairing_code as sent. So
--
--        POST /rest/v1/invite_tokens
--        [{family_id: <own>, token: <random>, pairing_code: "000000"}, …]
--
--    failed with 23505 "Key (pairing_code)=(123456) already exists" exactly
--    for the codes some OTHER family's live invite holds. That is an oracle
--    with no rate limit, and it made /redeem-code's per-user and per-IP
--    lockout irrelevant: an attacker only ever submitted confirmed codes, and
--    joined a stranger's family as a receiver or co-caregiver (reads the
--    members' phone numbers, check-ins, location).
--
--    No shipped iOS or Android build inserts invite_tokens directly (invites
--    are minted by /invite-receiver as service_role, which this guard does not
--    touch), so forcing pairing_code to NULL on a client insert changes
--    nothing for any real client. The UPDATE branch already pinned it.
--
-- 2. has_my_apple_identity(): the caller's own Apple link status.
--    has_apple_identity(p_user_id) (00017) answers for ANY user id, despite
--    its comment. New builds call this no-argument version; the old one stays
--    (shipped builds call it with their own id) and can be restricted to
--    p_user_id = auth.uid() once MIN_SUPPORTED_IOS_APP_VERSION covers them.
--
-- ─── COMPATIBILITY ───────────────────────────────────────────────────────────
-- Additive: one trigger function body replaced (client inserts only, which no
-- client makes), one new function. No table, column, policy or signature
-- changes.

BEGIN;

-- =============================================================================
-- 1. invite_tokens: client inserts never carry a pairing code
-- =============================================================================
-- Same body as 00058 except the INSERT branch.
CREATE OR REPLACE FUNCTION guard_invite_tokens_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- No shipped build inserts invites directly (invite-receiver does,
        -- as service_role). Keep a direct insert as harmless as one made
        -- there: unused, live for at most the standard 7 days, and WITHOUT a
        -- pairing code — a chosen code turned the unique index into an
        -- oracle for other families' live codes (00060).
        NEW.used_by := NULL;
        NEW.created_at := NOW();
        NEW.pairing_code := NULL;
        IF NEW.expires_at IS NULL OR NEW.expires_at > NOW() + INTERVAL '7 days' THEN
            NEW.expires_at := NOW() + INTERVAL '7 days';
        END IF;
        RETURN NEW;
    END IF;

    NEW.id := OLD.id;
    NEW.family_id := OLD.family_id;
    NEW.role := OLD.role;
    NEW.token := OLD.token;
    NEW.used_by := OLD.used_by;
    NEW.created_at := OLD.created_at;
    NEW.phone := OLD.phone;
    NEW.pairing_code := OLD.pairing_code;
    NEW.receiver_mode := OLD.receiver_mode;
    IF NEW.expires_at > OLD.expires_at THEN
        NEW.expires_at := OLD.expires_at;
    END IF;
    RETURN NEW;
END;
$$;

-- The trigger itself (00058) is unchanged: BEFORE INSERT OR UPDATE, FOR EACH
-- ROW, EXECUTE FUNCTION guard_invite_tokens_client_write().

-- =============================================================================
-- 2. has_my_apple_identity(): self-only Apple link check
-- =============================================================================
CREATE OR REPLACE FUNCTION public.has_my_apple_identity()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = auth, public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN EXISTS (
        SELECT 1 FROM auth.identities
        WHERE user_id = auth.uid() AND provider = 'apple'
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.has_my_apple_identity() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_my_apple_identity() TO authenticated;

COMMIT;

-- Verification:
--   SELECT proname FROM pg_proc
--   WHERE proname IN ('guard_invite_tokens_client_write', 'has_my_apple_identity');  -- 2 rows
--   -- As an owner (SET ROLE authenticated), inserting an invite with a
--   -- pairing_code another family's live invite holds now succeeds with
--   -- pairing_code NULL instead of failing with 23505.
