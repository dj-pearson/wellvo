-- Wellvo pg_cron Scheduled Jobs
-- Migration: 00003_pg_cron_jobs

-- =============================================================================
-- SCHEDULED CHECK-IN DISPATCHER
-- Runs every minute to find receivers whose check-in time has arrived.
-- Calls the edge function to send push notifications.
-- =============================================================================

-- Function to dispatch scheduled check-in notifications
CREATE OR REPLACE FUNCTION dispatch_scheduled_checkins()
RETURNS void AS $$
DECLARE
    rec RECORD;
BEGIN
    -- Find all active receivers whose check-in time matches the current time
    -- (within the current minute) in their local timezone
    FOR rec IN
        SELECT
            rs.id AS setting_id,
            fm.user_id AS receiver_id,
            fm.family_id,
            rs.checkin_time,
            rs.timezone,
            rs.grace_period_minutes
        FROM receiver_settings rs
        JOIN family_members fm ON fm.id = rs.family_member_id
        JOIN families f ON f.id = fm.family_id
        WHERE rs.is_active = TRUE
          AND fm.status = 'active'
          AND f.subscription_status IN ('active', 'grace_period')
          -- Match current time in receiver's timezone to their checkin_time
          AND rs.checkin_time = (NOW() AT TIME ZONE rs.timezone)::time(0)
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
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Schedule: check every minute for due check-ins
SELECT cron.schedule(
    'dispatch-scheduled-checkins',
    '* * * * *',
    $$SELECT dispatch_scheduled_checkins()$$
);

-- =============================================================================
-- ESCALATION TICK
-- Runs every minute to advance escalation steps for pending requests.
-- =============================================================================

CREATE OR REPLACE FUNCTION escalation_tick()
RETURNS void AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT
            cr.id AS request_id,
            cr.family_id,
            cr.receiver_id,
            cr.escalation_step,
            cr.requested_by,
            f.owner_id
        FROM checkin_requests cr
        JOIN families f ON f.id = cr.family_id
        WHERE cr.status = 'pending'
          AND cr.next_escalation_at <= NOW()
    LOOP
        -- Advance escalation step
        IF rec.escalation_step >= 3 THEN
            -- Max escalation reached — mark as missed
            UPDATE checkin_requests
            SET status = 'missed'
            WHERE id = rec.request_id;
        ELSE
            -- Advance to next step
            UPDATE checkin_requests
            SET escalation_step = rec.escalation_step + 1,
                next_escalation_at = NOW() + INTERVAL '30 minutes'
            WHERE id = rec.request_id;

            -- Trigger escalation notification
            PERFORM net.http_post(
                url := current_setting('app.edge_functions_url') || '/escalation-tick',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'Authorization', 'Bearer ' || current_setting('app.service_role_key')
                ),
                body := jsonb_build_object(
                    'request_id', rec.request_id,
                    'receiver_id', rec.receiver_id,
                    'family_id', rec.family_id,
                    'escalation_step', rec.escalation_step + 1,
                    'owner_id', rec.owner_id
                )
            );
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Schedule: check every minute for escalation
SELECT cron.schedule(
    'escalation-tick',
    '* * * * *',
    $$SELECT escalation_tick()$$
);

-- =============================================================================
-- EXPIRE OLD REQUESTS
-- Runs daily to clean up old pending requests older than 24 hours.
-- =============================================================================

CREATE OR REPLACE FUNCTION expire_old_requests()
RETURNS void AS $$
BEGIN
    UPDATE checkin_requests
    SET status = 'expired'
    WHERE status = 'pending'
      AND created_at < NOW() - INTERVAL '24 hours';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

SELECT cron.schedule(
    'expire-old-requests',
    '0 0 * * *',
    $$SELECT expire_old_requests()$$
);

-- =============================================================================
-- APP SETTINGS (for pg_net URLs)
-- These are set via ALTER DATABASE in the Coolify deployment.
-- =============================================================================
-- ALTER DATABASE wellvo SET app.edge_functions_url = 'http://edge-functions:9000';
-- ALTER DATABASE wellvo SET app.service_role_key = 'your-service-role-key';
