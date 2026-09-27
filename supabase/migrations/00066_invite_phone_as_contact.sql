-- Daily OK: keep a contact number for people who join without phone sign-in.
-- Migration: 00066_invite_phone_as_contact
--
-- ─── WHAT AND WHY ────────────────────────────────────────────────────────────
-- Phone-number sign-in is retired (server-sent SMS codes would need A2P 10DLC
-- registration). Until now users.phone — the number behind the caregiver's
-- "Call" and "Text <name>" buttons, and a co-caregiver's contact row — was only
-- ever set from the number Supabase Auth verified by SMS (00051 guards the
-- column against client writes). A receiver who now signs in with Apple,
-- Google or email would join with no number, and the buttons would vanish.
--
-- redeem_invite() now copies the invite's phone (the number the owner typed
-- and sent the invite to) onto the joining user's profile when the profile
-- has no number. It never overwrites one.
--
-- ─── BACKWARD COMPATIBILITY (CLAUDE.md §A) ───────────────────────────────────
-- Same signature, same return shape, same grants: CREATE OR REPLACE of the
-- 00054 function with one added UPDATE. Every join path (invite link, phone
-- auto-join, 6-digit code) goes through it, for old and new app builds alike.
-- Auto-join keeps trusting only auth.users.phone_confirmed_at, so an
-- owner-typed number can never be used to claim someone else's invite.
-- Accounts that signed up with a phone keep working exactly as before.
--
-- Also backfills: members who already joined with no profile number get the
-- number of the invite they redeemed.
--
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

    -- The number the owner invited becomes this person's contact number when
    -- their profile has none, so the family's Call / Text buttons work.
    -- Phone-number sign-in used to fill users.phone from the SMS-verified
    -- number; accounts made with Apple, Google or email never get one. This is
    -- a contact number only: auto-join trusts auth.users.phone_confirmed_at,
    -- never users.phone, so nothing about access changes. An existing number
    -- (a verified one from phone sign-in) is never overwritten.
    IF v_invite.phone IS NOT NULL AND btrim(v_invite.phone) <> '' THEN
        UPDATE users
        SET phone = btrim(v_invite.phone)
        WHERE id = p_user_id
          AND (phone IS NULL OR btrim(phone) = '');
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

-- Backfill: people who already joined through an invite and have no number.
-- The newest redeemed invite per user wins.
UPDATE users u
SET phone = btrim(i.phone)
FROM (
    SELECT DISTINCT ON (used_by) used_by, phone
    FROM invite_tokens
    WHERE used_by IS NOT NULL
      AND phone IS NOT NULL
      AND btrim(phone) <> ''
    ORDER BY used_by, created_at DESC
) i
WHERE u.id = i.used_by
  AND (u.phone IS NULL OR btrim(u.phone) = '');

COMMIT;
