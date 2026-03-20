-- Wellvo Phase 3b: Low Battery Alerts and Background Safety
-- Migration: 00013_low_battery_and_background_safety

BEGIN;

-- =============================================================================
-- 1. LOW BATTERY ALERT DETECTION
-- Runs every 5 minutes. If a receiver's battery is at or below 10%,
-- alert the owner so they know a missed check-in may be due to a dead phone.
-- =============================================================================

CREATE OR REPLACE FUNCTION check_low_battery_alerts()
RETURNS void AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT
            u.id AS receiver_id,
            u.display_name,
            u.last_battery_level,
            u.last_seen_at,
            fm.family_id,
            f.owner_id
        FROM users u
        JOIN family_members fm ON fm.user_id = u.id
        JOIN families f ON f.id = fm.family_id
        WHERE fm.role = 'receiver'
          AND fm.status = 'active'
          AND u.last_battery_level IS NOT NULL
          AND u.last_battery_level <= 0.10
          AND u.last_seen_at > NOW() - INTERVAL '30 minutes'
          -- Don't duplicate alerts within 4 hours
          AND NOT EXISTS (
              SELECT 1 FROM alerts a
              WHERE a.receiver_id = u.id
                AND a.family_id = fm.family_id
                AND a.type = 'low_battery'
                AND a.created_at > NOW() - INTERVAL '4 hours'
          )
    LOOP
        INSERT INTO alerts (family_id, receiver_id, type, title, message, data)
        VALUES (
            rec.family_id,
            rec.receiver_id,
            'low_battery',
            'Low Battery Warning',
            rec.display_name || '''s phone battery is at ' ||
                ROUND((rec.last_battery_level * 100)::numeric) ||
                '%. If they miss their check-in, their phone may be off.',
            jsonb_build_object(
                'battery_level', rec.last_battery_level,
                'last_seen_at', rec.last_seen_at
            )
        );

        -- Send push notification to owner
        PERFORM net.http_post(
            url := current_setting('app.edge_functions_url') || '/escalation-tick',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || current_setting('app.service_role_key')
            ),
            body := jsonb_build_object(
                'type', 'low_battery_alert',
                'receiver_id', rec.receiver_id,
                'family_id', rec.family_id,
                'battery_level', rec.last_battery_level,
                'display_name', rec.display_name,
                'owner_id', rec.owner_id
            )
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

SELECT cron.schedule(
    'check-low-battery',
    '*/5 * * * *',
    $$SELECT check_low_battery_alerts()$$
);

-- =============================================================================
-- 2. STALE HEARTBEAT DETECTION
-- If a receiver hasn't been seen in 2+ hours during their waking hours,
-- alert the owner. This helps detect phones that are off or unresponsive.
-- =============================================================================

CREATE OR REPLACE FUNCTION check_stale_heartbeats()
RETURNS void AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT
            u.id AS receiver_id,
            u.display_name,
            u.last_seen_at,
            u.last_battery_level,
            fm.family_id,
            f.owner_id,
            rs.quiet_hours_start,
            rs.quiet_hours_end,
            rs.timezone
        FROM users u
        JOIN family_members fm ON fm.user_id = u.id
        JOIN families f ON f.id = fm.family_id
        LEFT JOIN receiver_settings rs ON rs.family_member_id = fm.id
        WHERE fm.role = 'receiver'
          AND fm.status = 'active'
          AND u.last_seen_at IS NOT NULL
          AND u.last_seen_at < NOW() - INTERVAL '2 hours'
          -- Must have been seen in the last 24 hours (otherwise they never set up)
          AND u.last_seen_at > NOW() - INTERVAL '24 hours'
          -- Not during quiet hours
          AND (
              rs.quiet_hours_start IS NULL
              OR NOT (
                  (NOW() AT TIME ZONE COALESCE(rs.timezone, 'America/New_York'))::time
                  BETWEEN rs.quiet_hours_start AND rs.quiet_hours_end
              )
          )
          -- Don't duplicate within 4 hours
          AND NOT EXISTS (
              SELECT 1 FROM alerts a
              WHERE a.receiver_id = u.id
                AND a.family_id = fm.family_id
                AND a.type = 'stale_heartbeat'
                AND a.created_at > NOW() - INTERVAL '4 hours'
          )
    LOOP
        INSERT INTO alerts (family_id, receiver_id, type, title, message, data)
        VALUES (
            rec.family_id,
            rec.receiver_id,
            'stale_heartbeat',
            'Device Inactive',
            rec.display_name || '''s phone hasn''t been active for over 2 hours. Last seen: ' ||
                TO_CHAR(rec.last_seen_at AT TIME ZONE COALESCE(rec.timezone, 'America/New_York'), 'HH12:MI AM'),
            jsonb_build_object(
                'last_seen_at', rec.last_seen_at,
                'last_battery_level', rec.last_battery_level
            )
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

SELECT cron.schedule(
    'check-stale-heartbeats',
    '*/15 * * * *',
    $$SELECT check_stale_heartbeats()$$
);

COMMIT;
