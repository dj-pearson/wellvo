-- Daily OK: Redeem an invite in one transaction, and rate-limit pairing codes
--           durably.
-- Migration: 00054_atomic_invite_redemption
--
-- ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
-- The three join paths (invite-receiver accept, auto-join, redeem-code) each
-- did read-invite → insert member → upsert settings → set role → mark used as
-- separate un-guarded statements:
--   * Two concurrent redemptions of one invite could both succeed (no
--     `used_by IS NULL` guard on the final update).
--   * The plan's receiver limit was only checked when the invite was CREATED,
--     never when it was used, so extra invites (or resends) overfilled a family.
--   * users.role was overwritten with the invite role, so an owner who accepted
--     someone else's receiver invite lost their owner routing.
--   * Superseded invites to the same phone stayed live for 7 days, so a
--     receiver the owner had removed silently re-joined on next launch.
--   * receiver_settings "upsert" had no conflict target, so re-joining hit the
--     family_member_id unique key and the new check-in time was dropped.
--   * The pairing-code lockout lived in process memory, keyed per user: a
--     container restart or a second account reset it.
--
-- ─── WHAT CHANGES ────────────────────────────────────────────────────────────
--   * redeem_invite(): one SECURITY DEFINER function, service_role only, that
--     locks the invite row and does the whole join atomically.
--   * pairing_code_attempts + pairing_code_retry_after(): durable per-user
--     and per-IP failure limits for redeem-code.
--   * A nightly pg_cron job trims old attempts.
--
-- BACKWARD-COMPATIBLE (CLAUDE.md §A): a new table, two new functions and a new
-- cron job. Nothing existing is altered. The edge functions keep their
-- request/response shapes and switch to calling redeem_invite().
-- Idempotent: safe to replay.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

CREATE OR REPLACE FUNCTION redeem_invite(
    p_invite_id UUID,
    p_user_id UUID,
    p_timezone TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_invite invite_tokens;
    v_family families;
    v_member family_members;
    v_limit INT;
    v_active INT;
    v_tz TEXT;
    v_owns_family BOOLEAN;
    v_owner_name TEXT;
BEGIN
    SELECT * INTO v_invite
    FROM invite_tokens
    WHERE id = p_invite_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_invite.used_by IS NOT NULL
       OR v_invite.expires_at <= NOW()
       OR v_invite.role NOT IN ('receiver', 'viewer') THEN
        RETURN jsonb_build_object('status', 'invalid');
    END IF;

    SELECT * INTO v_family FROM families WHERE id = v_invite.family_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'invalid');
    END IF;

    SELECT display_name INTO v_owner_name FROM users WHERE id = v_family.owner_id;

    SELECT * INTO v_member
    FROM family_members
    WHERE family_id = v_invite.family_id AND user_id = p_user_id;

    IF FOUND AND v_member.status = 'active' THEN
        RETURN jsonb_build_object(
            'status', 'already_member',
            'family_id', v_invite.family_id,
            'role', v_member.role,
            'owner_name', v_owner_name
        );
    END IF;

    -- Plan limit, checked at the moment of joining (the family row is locked,
    -- so two concurrent joins cannot both take the last slot).
    v_limit := CASE v_invite.role WHEN 'receiver' THEN v_family.max_receivers
                                  ELSE v_family.max_viewers END;
    SELECT count(*) INTO v_active
    FROM family_members
    WHERE family_id = v_invite.family_id
      AND role = v_invite.role
      AND status = 'active'
      AND user_id <> p_user_id;
    IF v_active >= COALESCE(v_limit, 0) THEN
        RETURN jsonb_build_object('status', 'limit_reached', 'family_id', v_invite.family_id);
    END IF;

    INSERT INTO family_members (family_id, user_id, role, status, joined_at)
    VALUES (v_invite.family_id, p_user_id, v_invite.role, 'active', NOW())
    ON CONFLICT (family_id, user_id) DO UPDATE
        SET role = EXCLUDED.role,
            status = 'active',
            joined_at = EXCLUDED.joined_at
    RETURNING * INTO v_member;

    IF v_invite.role = 'receiver' THEN
        SELECT CASE
                   WHEN is_valid_timezone(p_timezone) THEN p_timezone
                   WHEN is_valid_timezone(u.timezone) THEN u.timezone
                   ELSE 'America/New_York'
               END
        INTO v_tz
        FROM users u WHERE u.id = p_user_id;

        INSERT INTO receiver_settings (family_member_id, checkin_time, timezone, receiver_mode)
        VALUES (
            v_member.id,
            COALESCE(v_invite.checkin_time, '08:00'),
            COALESCE(v_tz, 'America/New_York'),
            COALESCE(v_invite.receiver_mode, 'standard')
        )
        ON CONFLICT (family_member_id) DO UPDATE
            SET checkin_time = EXCLUDED.checkin_time,
                timezone = EXCLUDED.timezone,
                receiver_mode = EXCLUDED.receiver_mode,
                is_active = TRUE;
    END IF;

    -- users.role drives app routing. Someone who owns a family stays an owner
    -- and keeps the name they chose; otherwise the owner's name for the
    -- receiver ("Mom") is what the family sees, as before.
    SELECT EXISTS (SELECT 1 FROM families WHERE owner_id = p_user_id) INTO v_owns_family;
    IF NOT v_owns_family THEN
        UPDATE users
        SET role = v_invite.role,
            display_name = CASE
                WHEN v_invite.name IS NOT NULL AND btrim(v_invite.name) <> '' THEN v_invite.name
                ELSE display_name
            END
        WHERE id = p_user_id;
    END IF;

    UPDATE invite_tokens SET used_by = p_user_id WHERE id = v_invite.id;

    -- Any other open invite this family sent to the same person is now moot;
    -- leaving it live let a removed receiver silently re-join via auto-join.
    UPDATE invite_tokens
    SET expires_at = NOW()
    WHERE family_id = v_invite.family_id
      AND id <> v_invite.id
      AND used_by IS NULL
      AND expires_at > NOW()
      AND v_invite.phone IS NOT NULL
      AND phones_match(phone, v_invite.phone);

    RETURN jsonb_build_object(
        'status', 'joined',
        'family_id', v_invite.family_id,
        'member_id', v_member.id,
        'role', v_invite.role,
        'checkin_time', v_invite.checkin_time,
        'name', v_invite.name,
        'owner_name', v_owner_name
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION redeem_invite(UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION redeem_invite(UUID, UUID, TEXT) TO service_role;

-- -----------------------------------------------------------------------------
-- Pairing-code attempts (service_role only: RLS on, no policies).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pairing_code_attempts (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID,
    ip TEXT,
    succeeded BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pairing_code_attempts ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_pairing_code_attempts_user
    ON pairing_code_attempts (user_id, created_at) WHERE NOT succeeded;
CREATE INDEX IF NOT EXISTS idx_pairing_code_attempts_ip
    ON pairing_code_attempts (ip, created_at) WHERE NOT succeeded;
CREATE INDEX IF NOT EXISTS idx_pairing_code_attempts_created
    ON pairing_code_attempts (created_at);

-- Seconds until this caller may try another code; 0 = allowed now.
--   * 10 failures per user in 15 minutes
--   * 30 failures per IP in 60 minutes
-- No platform-wide block: anyone could trip it with throwaway accounts and
-- lock every real receiver out of pairing.
CREATE OR REPLACE FUNCTION pairing_code_retry_after(p_user_id UUID, p_ip TEXT)
RETURNS INT
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_wait INT := 0;
    v_oldest TIMESTAMPTZ;
BEGIN
    SELECT min(created_at) INTO v_oldest FROM (
        SELECT created_at FROM pairing_code_attempts
        WHERE user_id = p_user_id AND NOT succeeded
          AND created_at > NOW() - INTERVAL '15 minutes'
        ORDER BY created_at DESC LIMIT 10
    ) x HAVING count(*) >= 10;
    IF v_oldest IS NOT NULL THEN
        v_wait := GREATEST(v_wait, CEIL(EXTRACT(EPOCH FROM (v_oldest + INTERVAL '15 minutes' - NOW())))::INT);
    END IF;

    IF p_ip IS NOT NULL AND p_ip <> '' THEN
        SELECT min(created_at) INTO v_oldest FROM (
            SELECT created_at FROM pairing_code_attempts
            WHERE ip = p_ip AND NOT succeeded
              AND created_at > NOW() - INTERVAL '60 minutes'
            ORDER BY created_at DESC LIMIT 30
        ) x HAVING count(*) >= 30;
        IF v_oldest IS NOT NULL THEN
            v_wait := GREATEST(v_wait, CEIL(EXTRACT(EPOCH FROM (v_oldest + INTERVAL '60 minutes' - NOW())))::INT);
        END IF;
    END IF;

    RETURN GREATEST(v_wait, 0);
END;
$$;

REVOKE EXECUTE ON FUNCTION pairing_code_retry_after(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION pairing_code_retry_after(UUID, TEXT) TO service_role;

SELECT cron.schedule(
    'cleanup-pairing-code-attempts',
    '17 3 * * *',
    $$DELETE FROM pairing_code_attempts WHERE created_at < NOW() - INTERVAL '2 days'$$
);

COMMIT;
