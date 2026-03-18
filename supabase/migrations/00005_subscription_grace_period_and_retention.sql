-- Wellvo Grace Period Enforcement, Data Retention, and Subscription Downgrade
-- Migration: 00005_subscription_grace_period_and_retention

-- =============================================================================
-- GRACE PERIOD ENFORCEMENT
-- Runs daily: if subscription_expires_at + 7 days has passed, mark as expired
-- and deactivate receiver settings to stop check-in dispatching.
-- =============================================================================

CREATE OR REPLACE FUNCTION enforce_subscription_grace_period()
RETURNS void AS $$
BEGIN
    -- Move from grace_period to expired after 7 days
    UPDATE families
    SET subscription_status = 'expired'
    WHERE subscription_status = 'grace_period'
      AND subscription_expires_at IS NOT NULL
      AND subscription_expires_at + INTERVAL '7 days' < NOW();

    -- Deactivate receiver settings for expired families
    UPDATE receiver_settings rs
    SET is_active = FALSE
    FROM family_members fm
    JOIN families f ON f.id = fm.family_id
    WHERE rs.family_member_id = fm.id
      AND f.subscription_status = 'expired';

    -- Move active subscriptions past their expiry date to grace_period
    UPDATE families
    SET subscription_status = 'grace_period'
    WHERE subscription_status = 'active'
      AND subscription_tier != 'free'
      AND subscription_expires_at IS NOT NULL
      AND subscription_expires_at < NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

SELECT cron.schedule(
    'enforce-subscription-grace-period',
    '0 1 * * *',
    $$SELECT enforce_subscription_grace_period()$$
);

-- =============================================================================
-- DATA RETENTION
-- Add configurable retention period to families table.
-- Daily job deletes check-in records older than the retention period.
-- =============================================================================

ALTER TABLE families ADD COLUMN IF NOT EXISTS data_retention_days INT NOT NULL DEFAULT 365;

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

    -- Delete expired invite tokens
    DELETE FROM invite_tokens
    WHERE expires_at < NOW() AND used_by IS NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

SELECT cron.schedule(
    'enforce-data-retention',
    '0 3 * * *',
    $$SELECT enforce_data_retention()$$
);

-- =============================================================================
-- SUBSCRIPTION DOWNGRADE: soft-deactivate excess receivers
-- When max_receivers decreases, mark the newest excess members as deactivated.
-- Owner must re-activate after choosing which to keep via app UI.
-- =============================================================================

CREATE OR REPLACE FUNCTION handle_subscription_downgrade()
RETURNS TRIGGER AS $$
BEGIN
    -- Only act when max_receivers decreased
    IF NEW.max_receivers < OLD.max_receivers THEN
        -- Deactivate excess active receivers (keep the oldest by joined_at)
        UPDATE family_members
        SET status = 'deactivated'
        WHERE id IN (
            SELECT fm.id
            FROM family_members fm
            WHERE fm.family_id = NEW.id
              AND fm.role = 'receiver'
              AND fm.status = 'active'
            ORDER BY fm.joined_at ASC
            OFFSET NEW.max_receivers
        );
    END IF;

    -- Same for viewers
    IF NEW.max_viewers < OLD.max_viewers THEN
        UPDATE family_members
        SET status = 'deactivated'
        WHERE id IN (
            SELECT fm.id
            FROM family_members fm
            WHERE fm.family_id = NEW.id
              AND fm.role = 'viewer'
              AND fm.status = 'active'
            ORDER BY fm.joined_at ASC
            OFFSET NEW.max_viewers
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER families_subscription_downgrade
    AFTER UPDATE OF max_receivers, max_viewers ON families
    FOR EACH ROW
    EXECUTE FUNCTION handle_subscription_downgrade();

-- =============================================================================
-- DATA EXPORT RPC
-- Returns all user data as JSON for GDPR/CCPA compliance.
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

-- =============================================================================
-- ACCOUNT DELETION RPC
-- Deletes all user data for GDPR/CCPA right-to-be-forgotten.
-- If user is family owner, the family is also deleted (CASCADE handles members).
-- =============================================================================

CREATE OR REPLACE FUNCTION delete_user_account(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    -- Only allow users to delete their own account
    IF auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Delete push tokens
    DELETE FROM push_tokens WHERE user_id = p_user_id;

    -- Delete check-ins
    DELETE FROM checkins WHERE receiver_id = p_user_id;

    -- Delete notification logs
    DELETE FROM notification_log WHERE user_id = p_user_id;

    -- Remove from families (CASCADE will handle receiver_settings)
    DELETE FROM family_members WHERE user_id = p_user_id;

    -- Delete owned families (CASCADE handles members, checkins, requests)
    DELETE FROM families WHERE owner_id = p_user_id;

    -- Delete user record
    DELETE FROM users WHERE id = p_user_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
