-- Security Hardening Migration
-- Migration: 00018_security_hardening
--
-- US-SEC005: Add authorization check to increment_max_receivers/viewers RPC
-- US-SEC006: Add CHECK constraints to receiver_settings numeric fields
-- US-SEC012: Add null auth checks to GDPR RPC functions
-- US-SEC014: Add DELETE RLS policy for alerts table (owners only)
-- US-SEC023: Add DELETE RLS policy for checkin_requests (owners only)

BEGIN;

-- =============================================================================
-- US-SEC005: Authorization check for increment_max_receivers/viewers
-- SECURITY DEFINER functions must verify auth.uid() = p_owner_id
-- =============================================================================

CREATE OR REPLACE FUNCTION increment_max_receivers(p_owner_id UUID)
RETURNS void AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    IF auth.uid() != p_owner_id THEN
        RAISE EXCEPTION 'Unauthorized: caller is not the family owner';
    END IF;

    UPDATE families
    SET max_receivers = max_receivers + 1
    WHERE owner_id = p_owner_id
      AND subscription_tier IN ('family', 'family_plus');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION increment_max_viewers(p_owner_id UUID)
RETURNS void AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    IF auth.uid() != p_owner_id THEN
        RAISE EXCEPTION 'Unauthorized: caller is not the family owner';
    END IF;

    UPDATE families
    SET max_viewers = max_viewers + 1
    WHERE owner_id = p_owner_id
      AND subscription_tier IN ('family', 'family_plus');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- US-SEC006: CHECK constraints on receiver_settings numeric fields
-- =============================================================================

ALTER TABLE receiver_settings
    ADD CONSTRAINT chk_grace_period_positive
        CHECK (grace_period_minutes > 0),
    ADD CONSTRAINT chk_reminder_interval_positive
        CHECK (reminder_interval_minutes > 0);

-- =============================================================================
-- US-SEC012: Null auth checks in GDPR RPC functions
-- Explicit NULL check prevents silent bypass when auth.uid() is NULL
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
        'exported_at', NOW()
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION delete_user_account(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    IF auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    DELETE FROM push_tokens WHERE user_id = p_user_id;
    DELETE FROM checkins WHERE receiver_id = p_user_id;
    DELETE FROM notification_log WHERE user_id = p_user_id;
    DELETE FROM family_members WHERE user_id = p_user_id;
    DELETE FROM families WHERE owner_id = p_user_id;
    DELETE FROM users WHERE id = p_user_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- US-SEC014: DELETE RLS policy for alerts table (owners only)
-- =============================================================================

CREATE POLICY "Owners can delete family alerts"
    ON alerts FOR DELETE
    USING (
        family_id IN (
            SELECT id FROM families WHERE owner_id = auth.uid()
        )
    );

-- =============================================================================
-- US-SEC023: DELETE RLS policy for checkin_requests (owners only)
-- Receivers cannot delete requests (audit trail preservation)
-- =============================================================================

CREATE POLICY "Owners can delete family requests"
    ON checkin_requests FOR DELETE
    USING (is_family_owner(family_id));

COMMIT;
