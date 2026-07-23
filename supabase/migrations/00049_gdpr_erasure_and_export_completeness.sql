-- GDPR Erasure Completeness + Data Export Completeness
-- Migration: 00049_gdpr_erasure_and_export_completeness
--
-- Two forward-only, backward-compatible fixes (both CREATE OR REPLACE with
-- unchanged signatures; export gains keys clients already ignore-if-unknown):
--
--   1. delete_user_account: also delete the auth.users identity row. The FK
--      public.users.id -> auth.users(id) cascades auth->public, NOT
--      public->auth, so deleting only public.users left the Supabase Auth
--      identity (email, phone, password hash, OAuth identities, sign-in
--      metadata) behind — an incomplete Right to Erasure (GDPR Art. 17 /
--      CCPA §1798.105). Deleting auth.users cascades the public row away too.
--
--   2. export_user_data: include location_updates (00012), care_notes (00041),
--      and wellness_signals (00042), which were added after the export RPC and
--      never wired in — an incomplete Right to Access / Portability
--      (GDPR Art. 15/20).

BEGIN;

-- =============================================================================
-- 1. ERASURE — delete the authentication identity as well
-- =============================================================================

CREATE OR REPLACE FUNCTION delete_user_account(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    IF auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Explicit deletes for tables keyed off the public.users row.
    DELETE FROM push_tokens WHERE user_id = p_user_id;
    DELETE FROM checkins WHERE receiver_id = p_user_id;
    DELETE FROM notification_log WHERE user_id = p_user_id;
    DELETE FROM family_members WHERE user_id = p_user_id;
    DELETE FROM families WHERE owner_id = p_user_id;
    DELETE FROM users WHERE id = p_user_id;

    -- Remove the Supabase Auth identity. This is the row the previous version
    -- never touched; deleting it also cascades away any residual public.users
    -- row (defense in depth). Requires the function to run with a role that
    -- has DELETE on auth.users — guaranteed here because it is SECURITY
    -- DEFINER and owned by the migration/admin role.
    DELETE FROM auth.users WHERE id = p_user_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- 2. ACCESS / PORTABILITY — include location, care notes, and wellness signals
-- =============================================================================

CREATE OR REPLACE FUNCTION export_user_data(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    IF auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT jsonb_build_object(
        'user', (SELECT row_to_json(u) FROM users u WHERE u.id = p_user_id),
        'family_memberships', (
            SELECT COALESCE(jsonb_agg(row_to_json(fm)), '[]'::jsonb)
            FROM family_members fm WHERE fm.user_id = p_user_id
        ),
        'checkins', (
            SELECT COALESCE(jsonb_agg(row_to_json(c)), '[]'::jsonb)
            FROM checkins c WHERE c.receiver_id = p_user_id
        ),
        'checkin_requests', (
            SELECT COALESCE(jsonb_agg(row_to_json(cr)), '[]'::jsonb)
            FROM checkin_requests cr
            WHERE cr.receiver_id = p_user_id OR cr.requested_by = p_user_id
        ),
        'notification_log', (
            SELECT COALESCE(jsonb_agg(row_to_json(nl)), '[]'::jsonb)
            FROM notification_log nl WHERE nl.user_id = p_user_id
        ),
        'invite_tokens', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', it.id,
                'family_id', it.family_id,
                'token', '[REDACTED]',
                'role', it.role,
                'created_by', it.created_by,
                'used_by', it.used_by,
                'expires_at', it.expires_at,
                'created_at', it.created_at
            )), '[]'::jsonb)
            FROM invite_tokens it WHERE it.created_by = p_user_id
        ),
        'alerts', (
            SELECT COALESCE(jsonb_agg(row_to_json(a)), '[]'::jsonb)
            FROM alerts a
            JOIN families f ON f.id = a.family_id
            WHERE f.owner_id = p_user_id
        ),
        'receiver_settings', (
            SELECT COALESCE(jsonb_agg(row_to_json(rs)), '[]'::jsonb)
            FROM receiver_settings rs
            WHERE rs.family_member_id IN (
                SELECT fm.id FROM family_members fm WHERE fm.user_id = p_user_id
            )
        ),
        'push_tokens', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', pt.id,
                'platform', pt.platform,
                'is_active', pt.is_active,
                'created_at', pt.created_at
            )), '[]'::jsonb)
            FROM push_tokens pt WHERE pt.user_id = p_user_id
        ),
        -- Location history (the subject's own coordinates; ~110 m coarsened).
        'location_updates', (
            SELECT COALESCE(jsonb_agg(row_to_json(lu)), '[]'::jsonb)
            FROM location_updates lu WHERE lu.receiver_id = p_user_id
        ),
        -- Care notes about the subject, and care notes the subject authored.
        'care_notes', (
            SELECT COALESCE(jsonb_agg(row_to_json(cn)), '[]'::jsonb)
            FROM care_notes cn
            WHERE cn.receiver_id = p_user_id OR cn.author_id = p_user_id
        ),
        -- Derived wellness signals (activity booleans, never raw health values).
        'wellness_signals', (
            SELECT COALESCE(jsonb_agg(row_to_json(ws)), '[]'::jsonb)
            FROM wellness_signals ws WHERE ws.receiver_id = p_user_id
        ),
        'exported_at', NOW()
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
