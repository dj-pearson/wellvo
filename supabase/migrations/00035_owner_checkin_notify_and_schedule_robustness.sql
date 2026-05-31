-- Owner Check-In Confirmations + Schedule/Escalation Robustness
-- Migration: 00035_owner_checkin_notify_and_schedule_robustness
--
-- Closes gaps in the owner <-> receiver collaboration loop:
--
-- 1. notify_owner_on_checkin (opt-in, default TRUE): when a receiver taps
--    "I'm OK", the owner now gets a confirmation push. Previously the owner was
--    only notified for urgent/kid responses, so routine check-ins were invisible
--    unless the owner had the app open watching the realtime dashboard.
--    The edge function `process-checkin-response` reads this flag.
--
-- 2. dispatch_scheduled_checkins: match the scheduled time to the *minute*
--    instead of requiring exact-second equality. pg_cron ticks can arrive a
--    second or more late under load; the old `= ...::time(0)` comparison would
--    then silently skip the entire day's reminder. A NOT EXISTS guard against a
--    scheduled request already created today keeps the wider window idempotent.
--
-- 3. escalation_tick: honor each receiver's `reminder_interval_minutes` between
--    escalation steps instead of a hard-coded 30 minutes. The iOS settings UI
--    already exposes this control; the backend was ignoring it.
--
-- All changes are additive / backward-compatible: a new NULL-safe column with a
-- default, and CREATE OR REPLACE of two existing pg_cron functions (the cron
-- schedules from 00003 are unchanged and keep calling them).

BEGIN;

-- =============================================================================
-- 1. OWNER CHECK-IN CONFIRMATION OPT-IN (default on)
-- =============================================================================

ALTER TABLE receiver_settings
    ADD COLUMN IF NOT EXISTS notify_owner_on_checkin BOOLEAN NOT NULL DEFAULT TRUE;

-- =============================================================================
-- 2. DISPATCH SCHEDULED CHECK-INS — minute-granularity match + idempotency
--    (supersedes the definition in 00015)
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
          -- Idempotency: don't create a second scheduled request today. Combined
          -- with the minute-granularity match below this guarantees exactly one
          -- request per receiver per day even if a cron tick is retried/delayed.
          AND NOT EXISTS (
              SELECT 1 FROM checkin_requests cr
              WHERE cr.receiver_id = fm.user_id
                AND cr.family_id = fm.family_id
                AND cr.type = 'scheduled'
                AND cr.created_at >= (NOW() AT TIME ZONE rs.timezone)::date::timestamptz
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

        -- Match the target time to the current minute in the receiver's
        -- timezone. Comparing HH24:MI (rather than exact-second equality)
        -- tolerates pg_cron tick jitter so a slightly-late tick still fires.
        IF to_char(target_time, 'HH24:MI')
           = to_char((NOW() AT TIME ZONE rec.timezone)::time, 'HH24:MI') THEN
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

-- =============================================================================
-- 3. ESCALATION TICK — honor per-receiver reminder_interval_minutes
--    (supersedes the definition in 00003)
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
            f.owner_id,
            -- Gap between escalation steps, configurable per receiver. Falls
            -- back to 30 minutes if no settings row is found.
            COALESCE(rs.reminder_interval_minutes, 30) AS reminder_interval_minutes
        FROM checkin_requests cr
        JOIN families f ON f.id = cr.family_id
        LEFT JOIN family_members fm
               ON fm.family_id = cr.family_id
              AND fm.user_id = cr.receiver_id
              AND fm.role = 'receiver'
        LEFT JOIN receiver_settings rs ON rs.family_member_id = fm.id
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
            -- Advance to next step, waiting the receiver's reminder interval
            UPDATE checkin_requests
            SET escalation_step = rec.escalation_step + 1,
                next_escalation_at = NOW() + (rec.reminder_interval_minutes || ' minutes')::interval
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

COMMIT;
