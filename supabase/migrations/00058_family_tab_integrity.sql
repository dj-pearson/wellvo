-- Daily OK: Family tab — ownership goes to a caregiver, removal really stops
-- alerts, and memberships/invites change only through the paths that check
-- them.
-- Migration: 00058_family_tab_integrity
--
-- ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
-- 1. transfer_family_ownership (00045) accepts ANY active member, receivers
--    included. A receiver made owner stops being a receiver: dispatch filters
--    fm.role = 'receiver' (00052), so Mom's daily check-ins silently end, and
--    escalation alerts meant for the owner go to Mom herself. It also demotes
--    the caller with an UPDATE, which does nothing for an owner with no
--    family_members row (00021 says some exist), so the promised "you become
--    a Viewer" left them with no membership at all.
--    New transfer_family_ownership_v2 only hands a family to an active
--    co-caregiver (viewer) and upserts the caller's viewer membership. The
--    00045 function is kept as it is for shipped builds (only its
--    search_path is pinned, a no-op for callers).
--
-- 2. Removing a receiver set family_members.status = 'deactivated' but left
--    their pending check-in request escalating: escalation_tick doesn't look
--    at member status, so owner and viewers kept getting "Mom missed her
--    check-in" for someone no longer in the family. A trigger now stands
--    those requests down (the same stood_down_at marker cancel-escalation
--    writes, 00055) when a member is deactivated or deleted.
--
-- 3. The owner's "FOR ALL" policies let a client PATCH family_members and
--    invite_tokens directly:
--      * flip a receiver to viewer (the viewer limit was never checked), or
--        any member to 'owner' without the family moving;
--      * re-activate someone who was removed, with no new invite or consent;
--      * push an invite's expires_at years ahead or clear used_by, reviving a
--        consumed link and setup code.
--    The 00051 guard is extended for client roles only. Every write a
--    shipped build makes still passes (audited below).
--
-- 4. Expired, unused invites were deleted every night, so an invite nobody
--    used vanished from the owner's "Waiting to join" list and the owner
--    could assume the person had joined. They are now kept 30 days so the app
--    can show "Invite expired — Mom hasn't joined". They stay unredeemable:
--    every join path requires expires_at > NOW().
--
-- ─── BACKWARD COMPATIBILITY (CLAUDE.md §A) ───────────────────────────────────
--   * New RPC, new trigger, a longer retention window. No RLS policy is
--     added, removed or changed; no existing RPC signature changes.
--   * Client writes audited against the new guards:
--       iOS:     family_members SET status='deactivated' (remove);
--                family_members INSERT own owner row (create family);
--                invite_tokens SET expires_at = now / a past date (cancel).
--       Android: family_members SET status='deactivated' (remove);
--                family_members INSERT own owner row;
--                transferOwnership: target SET role='owner', own row SET
--                role='viewer', families.owner_id. The third write already
--                raises since 00051, leaving the family half-transferred.
--                The first write now raises instead, so the transfer fails
--                before changing anything — strictly better. A shipped
--                Android build could not complete a transfer either way.
--     Everything else those builds do goes through SECURITY DEFINER RPCs or
--     service-role edge functions, which the guards ignore.
-- Idempotent: safe to replay.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- =============================================================================
-- 1. Ownership goes to a co-caregiver
-- =============================================================================
ALTER FUNCTION transfer_family_ownership(UUID, UUID) SET search_path = public;

CREATE OR REPLACE FUNCTION transfer_family_ownership_v2(
    p_family_id UUID,
    p_new_owner_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_family families;
    v_caller UUID := auth.uid();
    v_target family_members;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT * INTO v_family FROM families WHERE id = p_family_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Family not found' USING ERRCODE = 'no_data_found';
    END IF;

    IF v_family.owner_id <> v_caller THEN
        RAISE EXCEPTION 'Only the current owner can transfer ownership'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_new_owner_user_id = v_caller THEN
        RAISE EXCEPTION 'You are already the owner' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT * INTO v_target
    FROM family_members
    WHERE family_id = p_family_id AND user_id = p_new_owner_user_id
    FOR UPDATE;

    IF NOT FOUND OR v_target.status <> 'active' THEN
        RAISE EXCEPTION 'New owner must be an active member of this family'
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- A receiver is the person being checked on. Making them owner would stop
    -- their check-ins and send their own missed-check-in alerts to them.
    IF v_target.role <> 'viewer' THEN
        RAISE EXCEPTION 'Ownership can only go to a co-caregiver (viewer)'
            USING ERRCODE = 'check_violation';
    END IF;

    UPDATE families SET owner_id = p_new_owner_user_id WHERE id = p_family_id;

    UPDATE family_members SET role = 'owner' WHERE id = v_target.id;

    -- Upsert, not UPDATE: an owner with no membership row must still end up a
    -- viewer, as the app promised.
    INSERT INTO family_members (family_id, user_id, role, status, joined_at)
    VALUES (p_family_id, v_caller, 'viewer', 'active', NOW())
    ON CONFLICT (family_id, user_id) DO UPDATE
        SET role = 'viewer', status = 'active';

    -- users.role mirrors routing for older readers. The new owner is an owner;
    -- the caller stays an owner only if they still own another family.
    UPDATE users SET role = 'owner' WHERE id = p_new_owner_user_id;
    UPDATE users SET role = 'viewer'
    WHERE id = v_caller
      AND NOT EXISTS (SELECT 1 FROM families WHERE owner_id = v_caller);

    RETURN jsonb_build_object(
        'status', 'transferred',
        'family_id', p_family_id,
        'new_owner_user_id', p_new_owner_user_id
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION transfer_family_ownership_v2(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION transfer_family_ownership_v2(UUID, UUID) TO authenticated;

-- =============================================================================
-- 2. Removing someone stands down their open check-in request
-- =============================================================================
CREATE OR REPLACE FUNCTION stand_down_requests_for_departed_member()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_family UUID;
    v_user UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_family := OLD.family_id;
        v_user := OLD.user_id;
    ELSE
        IF NOT (NEW.status = 'deactivated' AND OLD.status IS DISTINCT FROM 'deactivated') THEN
            RETURN NEW;
        END IF;
        v_family := NEW.family_id;
        v_user := NEW.user_id;
    END IF;

    UPDATE checkin_requests
    SET next_escalation_at = NULL,
        stood_down_at = COALESCE(stood_down_at, NOW())
    WHERE family_id = v_family
      AND receiver_id = v_user
      AND status = 'pending';

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS family_members_stand_down_on_leave ON family_members;
CREATE TRIGGER family_members_stand_down_on_leave
    AFTER UPDATE OF status OR DELETE ON family_members
    FOR EACH ROW EXECUTE FUNCTION stand_down_requests_for_departed_member();

-- =============================================================================
-- 3a. family_members client writes (extends 00051)
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

        -- Roles change through an invite or an ownership transfer (both
        -- server-side). The one client role write that is let through is an
        -- owner demoting their own row to viewer.
        IF NEW.role IS DISTINCT FROM OLD.role
           AND NOT (OLD.role = 'owner' AND NEW.role = 'viewer' AND OLD.user_id = auth.uid()) THEN
            RAISE EXCEPTION 'Roles change only through an invite or an ownership transfer'
                USING ERRCODE = 'insufficient_privilege';
        END IF;

        -- Someone who was removed (or never joined) comes back through a new
        -- invite they accept, never by a PATCH.
        IF NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active' THEN
            RAISE EXCEPTION 'A removed member rejoins through a new invite'
                USING ERRCODE = 'insufficient_privilege';
        END IF;
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

-- (Trigger family_members_guard_client_write from 00051 already calls this.)

-- =============================================================================
-- 3b. invite_tokens client writes
-- =============================================================================
-- Owners may cancel an invite (move expires_at earlier) and nothing else.
-- Silent clamps, not errors, in the 00051/00057 style.
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
        -- there: unused, and live for at most the standard 7 days.
        NEW.used_by := NULL;
        NEW.created_at := NOW();
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

DROP TRIGGER IF EXISTS invite_tokens_guard_client_write ON invite_tokens;
CREATE TRIGGER invite_tokens_guard_client_write
    BEFORE INSERT OR UPDATE ON invite_tokens
    FOR EACH ROW EXECUTE FUNCTION guard_invite_tokens_client_write();

-- =============================================================================
-- 4. Keep expired, unused invites for 30 days (was: deleted nightly)
-- =============================================================================
-- Same body as 00005 except the invite_tokens line.
CREATE OR REPLACE FUNCTION enforce_data_retention()
RETURNS void AS $$
BEGIN
    -- Delete check-ins older than retention period per family
    DELETE FROM checkins c
    USING families f
    WHERE c.family_id = f.id
      AND c.checked_in_at < NOW() - (f.data_retention_days || ' days')::interval;

    -- Delete old notification logs (90 days regardless)
    DELETE FROM notification_log
    WHERE sent_at < NOW() - INTERVAL '90 days';

    -- Delete unused invite tokens 30 days after they expired, so the owner
    -- can still see "Invite expired — hasn't joined" in the meantime.
    DELETE FROM invite_tokens
    WHERE expires_at < NOW() - INTERVAL '30 days' AND used_by IS NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;

-- Verification:
--   SELECT proname FROM pg_proc WHERE proname IN
--     ('transfer_family_ownership_v2', 'stand_down_requests_for_departed_member',
--      'guard_invite_tokens_client_write');                               -- 3 rows
--   SELECT tgname FROM pg_trigger WHERE tgname IN
--     ('family_members_stand_down_on_leave', 'invite_tokens_guard_client_write'); -- 2 rows
