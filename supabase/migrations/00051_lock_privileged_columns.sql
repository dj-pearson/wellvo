-- Daily OK: Stop signed-in users writing columns only the server may write.
-- Migration: 00051_lock_privileged_columns
--
-- ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
-- Several RLS policies grant UPDATE on a whole row with no column restriction,
-- so any signed-in user could call PostgREST directly and:
--   * users:     set is_system_admin = true (global read of every user, check-in
--                and request via the 00022 admin policies, plus the edge admin
--                gate), change their own role, or set `phone` to someone else's
--                number — which auto-join then trusted to hand them that
--                person's pending invite.
--   * families:  set subscription_tier / subscription_status / max_receivers /
--                max_viewers themselves (a free paywall bypass), and call
--                increment_max_receivers / increment_max_viewers directly for
--                free add-on slots (EXECUTE now revoked from clients).
--   * family_members: insert a row for ANY user_id (attach a stranger to a
--                family) or reactivate/promote receivers past the plan limit.
--   * checkins:  rewrite checked_in_at / response_type / family after the fact.
--   * checkin_requests: clear their own escalation clock or snooze counter,
--                bypassing snooze_checkin_request's limits.
--
-- ─── APPROACH ────────────────────────────────────────────────────────────────
-- BEFORE triggers that only act when the statement runs as a client role
-- (`authenticated` / `anon`, i.e. PostgREST on behalf of an app user). The edge
-- functions (service_role), pg_cron (postgres) and SECURITY DEFINER RPCs (run as
-- their owner) are untouched, so every server write path keeps working.
--
-- For columns a shipped app might still send (e.g. the iOS profile upsert sends
-- `phone`, the iOS family insert sends `subscription_tier = 'free'`) the trigger
-- silently keeps the server's value instead of raising, so no installed build
-- starts failing. Only writes no shipped client performs raise an error.
--
-- ─── BACKWARD COMPATIBILITY (CLAUDE.md §A) ───────────────────────────────────
-- Audited every client write to these tables in ios/ and android/:
--   users:            display_name, email, timezone, digest_* (still allowed);
--                     phone only on first profile create, from the verified OTP
--                     number (still allowed — it matches auth.users.phone).
--   families:         insert with name/owner_id (+ free/active/1/0 on iOS) and
--                     update of data_retention_days (still allowed).
--   family_members:   the owner's own membership row on family create (still
--                     allowed); Android transfer-ownership role flips (allowed).
--   checkins:         mood / location_label / kid_response_type (still allowed).
--   checkin_requests: none.
-- New trigger functions and REVOKEs only; no column, policy or RPC signature is
-- removed. Idempotent: safe to replay.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- True when the current statement runs on behalf of an app user through
-- PostgREST. Inside a SECURITY DEFINER function current_user is the function
-- owner, so trusted server-side RPCs are never caught by this.
CREATE OR REPLACE FUNCTION is_client_role()
RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT current_user IN ('authenticated', 'anon');
$$;

-- The phone number Supabase Auth verified (via SMS OTP) for the CALLER only.
-- SECURITY DEFINER because clients cannot read auth.users; takes no argument so
-- it cannot be used to look up anyone else's number.
CREATE OR REPLACE FUNCTION auth_verified_phone()
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, auth AS $$
    SELECT phone FROM auth.users
    WHERE id = auth.uid() AND phone_confirmed_at IS NOT NULL;
$$;

-- Same number, ignoring formatting and an optional NANP leading 1.
-- auth.users stores "15551234567"; the apps send "+15551234567".
CREATE OR REPLACE FUNCTION phones_match(a TEXT, b TEXT)
RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    WITH d AS (
        SELECT regexp_replace(COALESCE(a, ''), '\D', '', 'g') AS x,
               regexp_replace(COALESCE(b, ''), '\D', '', 'g') AS y
    )
    SELECT x <> '' AND y <> '' AND (
        x = y
        OR (length(x) = 11 AND left(x, 1) = '1' AND substr(x, 2) = y)
        OR (length(y) = 11 AND left(y, 1) = '1' AND substr(y, 2) = x)
    )
    FROM d;
$$;

-- =============================================================================
-- users
-- =============================================================================
CREATE OR REPLACE FUNCTION guard_users_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        NEW.is_system_admin := FALSE;
        NEW.role := 'owner';  -- column default; role changes are server-only
        IF NEW.phone IS NOT NULL AND NOT phones_match(NEW.phone, auth_verified_phone()) THEN
            NEW.phone := NULL;
        END IF;
    ELSE
        NEW.id := OLD.id;
        NEW.is_system_admin := OLD.is_system_admin;
        NEW.role := OLD.role;
        IF NEW.phone IS DISTINCT FROM OLD.phone
           AND NEW.phone IS NOT NULL
           AND NOT phones_match(NEW.phone, auth_verified_phone()) THEN
            NEW.phone := OLD.phone;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_guard_client_write ON users;
CREATE TRIGGER users_guard_client_write
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION guard_users_client_write();

-- =============================================================================
-- families
-- =============================================================================
CREATE OR REPLACE FUNCTION guard_families_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- A new family always starts on the base allowance; the subscription
        -- webhook (service_role) upgrades it once a purchase is verified.
        NEW.subscription_tier := 'free';
        NEW.subscription_status := 'active';
        NEW.subscription_expires_at := NULL;
        NEW.free_tier_expires_at := NULL;
        NEW.max_receivers := 1;
        NEW.max_viewers := 0;
    ELSE
        NEW.id := OLD.id;
        -- Ownership moves only through transfer_family_ownership() (00045).
        -- Raise rather than silently keep: the RLS WITH CHECK already rejected
        -- this write, and a quiet no-op would tell the caller it had worked.
        IF NEW.owner_id IS DISTINCT FROM OLD.owner_id THEN
            RAISE EXCEPTION 'Use transfer_family_ownership to change the owner'
                USING ERRCODE = 'insufficient_privilege';
        END IF;
        NEW.subscription_tier := OLD.subscription_tier;
        NEW.subscription_status := OLD.subscription_status;
        NEW.subscription_expires_at := OLD.subscription_expires_at;
        NEW.free_tier_expires_at := OLD.free_tier_expires_at;
        NEW.max_receivers := OLD.max_receivers;
        NEW.max_viewers := OLD.max_viewers;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS families_guard_client_write ON families;
CREATE TRIGGER families_guard_client_write
    BEFORE INSERT OR UPDATE ON families
    FOR EACH ROW EXECUTE FUNCTION guard_families_client_write();

-- Add-on slots: take the RPCs away from clients (an owner could call them
-- directly for free seats). The bodies are deliberately left as they were
-- (auth.uid() must equal p_owner_id), which the service-role webhook call can
-- never satisfy — so add-on purchases still grant nothing, exactly as before
-- this migration. Making them work needs an idempotent, receipt-verified
-- webhook first: /subscription-webhook trusts the client's product_id and is
-- replayed on every launch, so a working increment would hand out unlimited
-- seats. Tracked as a follow-up.
REVOKE EXECUTE ON FUNCTION increment_max_receivers(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION increment_max_viewers(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION increment_max_receivers(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION increment_max_viewers(UUID) TO service_role;

-- =============================================================================
-- family_members
-- =============================================================================
CREATE OR REPLACE FUNCTION guard_family_members_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_max INT;
    v_active INT;
BEGIN
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- An app only ever inserts the owner's own membership when creating a
        -- family. Everyone else joins through an invite (server-side).
        IF NEW.user_id IS DISTINCT FROM auth.uid() THEN
            RAISE EXCEPTION 'Members join a family through an invite'
                USING ERRCODE = 'insufficient_privilege';
        END IF;
    ELSE
        NEW.id := OLD.id;
        NEW.family_id := OLD.family_id;
        NEW.user_id := OLD.user_id;
    END IF;

    -- Becoming an active receiver must fit the plan.
    IF NEW.role = 'receiver' AND NEW.status = 'active'
       AND (TG_OP = 'INSERT' OR OLD.role <> 'receiver' OR OLD.status <> 'active') THEN
        SELECT max_receivers INTO v_max FROM families WHERE id = NEW.family_id;
        SELECT count(*) INTO v_active
        FROM family_members
        WHERE family_id = NEW.family_id
          AND role = 'receiver'
          AND status = 'active'
          AND id <> NEW.id;
        IF v_active >= COALESCE(v_max, 0) THEN
            RAISE EXCEPTION 'Receiver limit reached for your subscription tier'
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS family_members_guard_client_write ON family_members;
CREATE TRIGGER family_members_guard_client_write
    BEFORE INSERT OR UPDATE ON family_members
    FOR EACH ROW EXECUTE FUNCTION guard_family_members_client_write();

-- =============================================================================
-- checkins — apps may annotate (mood, location label, kid response), never
-- move or re-attribute a check-in.
-- =============================================================================
CREATE OR REPLACE FUNCTION guard_checkins_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NOT is_family_member(NEW.family_id) THEN
            RAISE EXCEPTION 'Not a member of this family'
                USING ERRCODE = 'insufficient_privilege';
        END IF;
    ELSE
        NEW.id := OLD.id;
        NEW.receiver_id := OLD.receiver_id;
        NEW.family_id := OLD.family_id;
        NEW.checked_in_at := OLD.checked_in_at;
        NEW.response_type := OLD.response_type;
        NEW.source := OLD.source;
        NEW.slot_key := OLD.slot_key;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS checkins_guard_client_write ON checkins;
CREATE TRIGGER checkins_guard_client_write
    BEFORE INSERT OR UPDATE ON checkins
    FOR EACH ROW EXECUTE FUNCTION guard_checkins_client_write();

-- =============================================================================
-- checkin_requests — the escalation clock and snooze counters are server-owned
-- (snooze goes through snooze_checkin_request, which is SECURITY DEFINER).
-- =============================================================================
CREATE OR REPLACE FUNCTION guard_checkin_requests_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() OR TG_OP <> 'UPDATE' THEN
        RETURN NEW;
    END IF;

    NEW.id := OLD.id;
    NEW.family_id := OLD.family_id;
    NEW.receiver_id := OLD.receiver_id;
    NEW.requested_by := OLD.requested_by;
    NEW.type := OLD.type;
    NEW.created_at := OLD.created_at;
    NEW.escalation_step := OLD.escalation_step;
    NEW.next_escalation_at := OLD.next_escalation_at;
    NEW.snoozed_until := OLD.snoozed_until;
    NEW.snooze_count := OLD.snooze_count;
    NEW.slot_key := OLD.slot_key;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS checkin_requests_guard_client_write ON checkin_requests;
CREATE TRIGGER checkin_requests_guard_client_write
    BEFORE UPDATE ON checkin_requests
    FOR EACH ROW EXECUTE FUNCTION guard_checkin_requests_client_write();

COMMIT;
