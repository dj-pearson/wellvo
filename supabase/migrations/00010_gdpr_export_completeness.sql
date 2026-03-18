-- GDPR Export Completeness (US-026)
-- Migration: 00010_gdpr_export_completeness
--
-- Updates export_user_data to include all user-related tables:
--   checkin_requests, notification_log, invite_tokens, alerts, receiver_settings

BEGIN;

-- =============================================================================
-- UPDATED DATA EXPORT RPC
-- Returns all user data as JSON for GDPR/CCPA compliance.
--
-- JSON output structure:
-- {
--   "user":               { ...user profile row },
--   "family_memberships": [ ...family_members rows ],
--   "checkins":           [ ...checkins where user is receiver ],
--   "checkin_requests":   [ ...requests where user is receiver or requester ],
--   "notification_log":   [ ...notifications sent to user ],
--   "invite_tokens":      [ ...tokens created by user, token value redacted ],
--   "alerts":             [ ...alerts for families the user owns ],
--   "receiver_settings":  [ ...settings for user's family memberships ],
--   "push_tokens":        [ ...tokens with device details redacted ],
--   "exported_at":        "ISO 8601 timestamp"
-- }
-- =============================================================================

CREATE OR REPLACE FUNCTION export_user_data(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    -- Only allow users to export their own data
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
        'exported_at', NOW()
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
