-- Flexible Notification Schedules
-- Migration: 00015_flexible_notification_schedules
--
-- Adds support for:
-- 1. Schedule types: daily (existing), weekday_weekend, custom (per-day)
-- 2. Weekend-specific check-in time
-- 3. Per-day JSONB schedule for full granular control
-- 4. Pause toggle for recurring notifications
-- 5. Updated dispatch function to handle all schedule types

BEGIN;

-- =============================================================================
-- ADD SCHEDULE COLUMNS TO receiver_settings
-- =============================================================================

-- Schedule type: 'daily' (default, existing behavior), 'weekday_weekend', 'custom'
ALTER TABLE receiver_settings
    ADD COLUMN IF NOT EXISTS schedule_type TEXT NOT NULL DEFAULT 'daily'
    CHECK (schedule_type IN ('daily', 'weekday_weekend', 'custom'));

-- Weekend check-in time (used when schedule_type = 'weekday_weekend')
-- checkin_time becomes the weekday time in this mode
ALTER TABLE receiver_settings
    ADD COLUMN IF NOT EXISTS weekend_checkin_time TIME;

-- Per-day schedule as JSONB (used when schedule_type = 'custom')
-- Format: {"mon": "08:00", "tue": "08:00", "wed": null, "thu": "09:30", "fri": "08:00", "sat": "10:00", "sun": "10:00"}
-- null value = no check-in that day
ALTER TABLE receiver_settings
    ADD COLUMN IF NOT EXISTS custom_schedule JSONB;

-- Pause toggle — when true, no scheduled notifications are sent
ALTER TABLE receiver_settings
    ADD COLUMN IF NOT EXISTS schedule_paused BOOLEAN NOT NULL DEFAULT FALSE;

-- =============================================================================
-- UPDATED DISPATCH FUNCTION
-- Handles daily, weekday_weekend, and custom schedule types.
-- =============================================================================

CREATE OR REPLACE FUNCTION dispatch_scheduled_checkins()
RETURNS void AS $$
DECLARE
    rec RECORD;
    current_dow TEXT;
    target_time TIME;
BEGIN
    FOR rec IN
        SELECT
            rs.id AS setting_id,
            fm.user_id AS receiver_id,
            fm.family_id,
            rs.checkin_time,
            rs.timezone,
            rs.grace_period_minutes,
            rs.schedule_type,
            rs.weekend_checkin_time,
            rs.custom_schedule
        FROM receiver_settings rs
        JOIN family_members fm ON fm.id = rs.family_member_id
        JOIN families f ON f.id = fm.family_id
        WHERE rs.is_active = TRUE
          AND rs.schedule_paused = FALSE
          AND fm.status = 'active'
          AND f.subscription_status IN ('active', 'grace_period')
          -- Check quiet hours
          AND (
              rs.quiet_hours_start IS NULL
              OR NOT (
                  (NOW() AT TIME ZONE rs.timezone)::time
                  BETWEEN rs.quiet_hours_start AND rs.quiet_hours_end
              )
          )
          -- Don't send if already checked in today
          AND NOT EXISTS (
              SELECT 1 FROM checkins c
              WHERE c.receiver_id = fm.user_id
                AND c.family_id = fm.family_id
                AND c.checked_in_at >= (NOW() AT TIME ZONE rs.timezone)::date::timestamptz
          )
    LOOP
        -- Determine target time based on schedule type
        current_dow := LOWER(TO_CHAR(NOW() AT TIME ZONE rec.timezone, 'Dy'));

        CASE rec.schedule_type
            WHEN 'daily' THEN
                target_time := rec.checkin_time;

            WHEN 'weekday_weekend' THEN
                IF current_dow IN ('sat', 'sun') THEN
                    target_time := COALESCE(rec.weekend_checkin_time, rec.checkin_time);
                ELSE
                    target_time := rec.checkin_time;
                END IF;

            WHEN 'custom' THEN
                IF rec.custom_schedule IS NOT NULL
                   AND rec.custom_schedule ? current_dow
                   AND rec.custom_schedule->>current_dow IS NOT NULL
                THEN
                    target_time := (rec.custom_schedule->>current_dow)::time;
                ELSE
                    -- No check-in scheduled for this day
                    CONTINUE;
                END IF;

            ELSE
                target_time := rec.checkin_time;
        END CASE;

        -- Match current time to target time (within the minute)
        IF target_time = (NOW() AT TIME ZONE rec.timezone)::time(0) THEN
            -- Create a check-in request
            INSERT INTO checkin_requests (
                family_id, receiver_id, requested_by, type, status,
                escalation_step, next_escalation_at
            ) VALUES (
                rec.family_id,
                rec.receiver_id,
                (SELECT owner_id FROM families WHERE id = rec.family_id),
                'scheduled',
                'pending',
                0,
                NOW() + (rec.grace_period_minutes || ' minutes')::interval
            );

            -- Trigger push notification via pg_net to edge function
            PERFORM net.http_post(
                url := current_setting('app.edge_functions_url') || '/send-checkin-notification',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'Authorization', 'Bearer ' || current_setting('app.service_role_key')
                ),
                body := jsonb_build_object(
                    'receiver_id', rec.receiver_id,
                    'family_id', rec.family_id,
                    'type', 'scheduled'
                )
            );
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
