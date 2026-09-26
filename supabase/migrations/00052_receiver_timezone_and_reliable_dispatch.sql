-- Daily OK: Prompt receivers at their own local time, every time.
-- Migration: 00052_receiver_timezone_and_reliable_dispatch
--
-- ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
-- 1. Wrong timezone. Every join path (auto-join, accept, redeem-code) wrote
--    receiver_settings.timezone = 'America/New_York' — auto-join hardcoded it and
--    the apps never send one to accept/redeem — and receivers cannot write their
--    own settings row (owner-only RLS). The apps DO keep users.timezone in step
--    with the device, but dispatch reads receiver_settings.timezone. So a
--    receiver in Los Angeles with an 8:00 check-in was prompted at 5:00.
--
-- 2. Evening check-in suppressed the next morning's prompt. The "already checked
--    in today" guard computed local midnight as
--    `(NOW() AT TIME ZONE tz)::date::timestamptz`, which casts the local DATE
--    back using the SESSION timezone (UTC), i.e. UTC midnight. For anyone west of
--    UTC, an evening check-in (8pm ET = 00:00 UTC next day) counted as "today"
--    the next morning: no request was created, so no prompt and no escalation.
--
-- 3. A skipped cron minute lost the window for the day. Dispatch fired only on
--    an exact HH:MI match, so one late or skipped pg_cron tick meant no prompt.
--
-- 4. Quiet hours spanning midnight (e.g. 22:00–07:00) never applied, because
--    `x BETWEEN 22:00 AND 07:00` is always false.
--
-- 5. One bad row stopped everyone. An invalid timezone string made
--    `AT TIME ZONE` raise, aborting the whole per-minute dispatch run.
--
-- 6. escalation_tick could overwrite a check-in that landed mid-tick: its
--    UPDATEs had no status guard, so a request the receiver had just answered
--    could be advanced or marked 'missed' anyway.
--
-- ─── WHAT CHANGES ────────────────────────────────────────────────────────────
--   * receiver_settings.timezone now follows the receiver's device timezone
--     (users.timezone): synced on change, defaulted on insert, and backfilled
--     for rows still on the hardcoded 'America/New_York' default.
--   * dispatch_scheduled_checkins: correct local midnight; fires any window
--     that came due in the last 10 minutes and has no request yet (per-slot
--     idempotency already existed); wrap-around quiet hours; per-receiver error
--     isolation.
--   * escalation_tick: only advances or misses a request that is still
--     pending at the moment of the UPDATE.
--
-- BACKWARD-COMPATIBLE (CLAUDE.md §A): function bodies replaced with identical
-- signatures; two new triggers; one data backfill limited to rows still on the
-- default zone. No shipped client reads or writes anything differently.
-- Idempotent: safe to replay.
--
-- BEHAVIOUR NOTE FOR SUPPORT: receivers outside Eastern time will start being
-- prompted at their scheduled time in THEIR zone. An owner who had shifted the
-- time to compensate (e.g. set 11:00 to reach an 8:00 Pacific receiver) will
-- need to set it back.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

CREATE OR REPLACE FUNCTION is_valid_timezone(p_tz TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT p_tz IS NOT NULL AND EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_tz);
$$;

-- -----------------------------------------------------------------------------
-- 1. receiver_settings.timezone follows the receiver's device.
-- -----------------------------------------------------------------------------

-- SECURITY DEFINER: the receiver's own app updates users.timezone, and the
-- receiver has no RLS write on receiver_settings. This only ever copies the
-- user's own zone onto their own receiver rows.
CREATE OR REPLACE FUNCTION sync_receiver_timezone_from_user()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
    IF NEW.timezone IS DISTINCT FROM OLD.timezone AND is_valid_timezone(NEW.timezone) THEN
        UPDATE receiver_settings rs
        SET timezone = NEW.timezone
        FROM family_members fm
        WHERE rs.family_member_id = fm.id
          AND fm.user_id = NEW.id
          AND fm.role = 'receiver'
          AND rs.timezone IS DISTINCT FROM NEW.timezone;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_sync_receiver_timezone ON users;
CREATE TRIGGER users_sync_receiver_timezone
    AFTER UPDATE OF timezone ON users
    FOR EACH ROW EXECUTE FUNCTION sync_receiver_timezone_from_user();

-- New settings rows: replace the hardcoded default (or an invalid value) with
-- the receiver's real zone when we know it.
CREATE OR REPLACE FUNCTION default_receiver_settings_timezone()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_user_tz TEXT;
BEGIN
    IF NEW.timezone IS NULL
       OR NEW.timezone = 'America/New_York'
       OR NOT is_valid_timezone(NEW.timezone) THEN
        SELECT u.timezone INTO v_user_tz
        FROM family_members fm
        JOIN users u ON u.id = fm.user_id
        WHERE fm.id = NEW.family_member_id;

        IF is_valid_timezone(v_user_tz) THEN
            NEW.timezone := v_user_tz;
        ELSIF NOT is_valid_timezone(NEW.timezone) THEN
            NEW.timezone := 'America/New_York';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS receiver_settings_default_timezone ON receiver_settings;
CREATE TRIGGER receiver_settings_default_timezone
    BEFORE INSERT ON receiver_settings
    FOR EACH ROW EXECUTE FUNCTION default_receiver_settings_timezone();

-- Backfill: only rows still on the hardcoded default. A row that already holds
-- some other zone was set deliberately (redeem-code with a device zone) and is
-- left alone.
UPDATE receiver_settings rs
SET timezone = u.timezone
FROM family_members fm
JOIN users u ON u.id = fm.user_id
WHERE rs.family_member_id = fm.id
  AND fm.role = 'receiver'
  AND rs.timezone = 'America/New_York'
  AND u.timezone IS DISTINCT FROM 'America/New_York'
  AND is_valid_timezone(u.timezone);

-- -----------------------------------------------------------------------------
-- 2. Dispatch.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION dispatch_scheduled_checkins()
RETURNS void AS $$
DECLARE
    -- A window is dispatched if it came due within this lookback and has no
    -- request yet today. Covers late or skipped pg_cron ticks.
    c_catch_up CONSTANT INTERVAL := INTERVAL '10 minutes';
    rec RECORD;
    v_tz TEXT;
    v_local_now TIMESTAMP;
    v_local_today DATE;
    v_local_midnight TIMESTAMPTZ;
    v_local_time TIME;
    current_dow TEXT;
    target_times TIME[];
    is_multi BOOLEAN;
    t TIME;
    v_due TIMESTAMP;
    v_slot_key TEXT;
    v_owner UUID;
BEGIN
    FOR rec IN
        SELECT
            rs.id AS setting_id,
            fm.user_id AS receiver_id,
            fm.family_id,
            f.owner_id,
            rs.checkin_time,
            rs.timezone,
            rs.grace_period_minutes,
            rs.schedule_type,
            rs.weekend_checkin_time,
            rs.custom_schedule,
            rs.quiet_hours_start,
            rs.quiet_hours_end
        FROM receiver_settings rs
        JOIN family_members fm ON fm.id = rs.family_member_id
        JOIN families f ON f.id = fm.family_id
        WHERE rs.is_active = TRUE
          AND rs.schedule_paused = FALSE
          AND fm.status = 'active'
          AND f.subscription_status IN ('active', 'grace_period')
    LOOP
        BEGIN
            v_tz := CASE WHEN is_valid_timezone(rec.timezone) THEN rec.timezone
                         ELSE 'America/New_York' END;
            v_local_now := NOW() AT TIME ZONE v_tz;
            v_local_today := v_local_now::date;
            -- Local midnight as an absolute instant, independent of the
            -- session timezone.
            v_local_midnight := v_local_today::timestamp AT TIME ZONE v_tz;
            v_local_time := v_local_now::time;
            current_dow := LOWER(TO_CHAR(v_local_now, 'Dy'));

            -- Quiet hours, including ranges that wrap midnight.
            IF rec.quiet_hours_start IS NOT NULL AND rec.quiet_hours_end IS NOT NULL THEN
                IF (rec.quiet_hours_start <= rec.quiet_hours_end
                        AND v_local_time BETWEEN rec.quiet_hours_start AND rec.quiet_hours_end)
                   OR (rec.quiet_hours_start > rec.quiet_hours_end
                        AND (v_local_time >= rec.quiet_hours_start OR v_local_time <= rec.quiet_hours_end))
                THEN
                    CONTINUE;
                END IF;
            END IF;

            CASE rec.schedule_type
                WHEN 'daily' THEN
                    target_times := ARRAY[rec.checkin_time];
                WHEN 'weekday_weekend' THEN
                    IF current_dow IN ('sat', 'sun') THEN
                        target_times := ARRAY[COALESCE(rec.weekend_checkin_time, rec.checkin_time)];
                    ELSE
                        target_times := ARRAY[rec.checkin_time];
                    END IF;
                WHEN 'custom' THEN
                    IF rec.custom_schedule IS NOT NULL
                       AND rec.custom_schedule->'multiTimes' ? current_dow
                       AND jsonb_typeof(rec.custom_schedule->'multiTimes'->current_dow) = 'array'
                       AND jsonb_array_length(rec.custom_schedule->'multiTimes'->current_dow) > 0
                    THEN
                        SELECT array_agg(elem::time)
                        INTO target_times
                        FROM jsonb_array_elements_text(rec.custom_schedule->'multiTimes'->current_dow) AS elem;
                    ELSIF rec.custom_schedule IS NOT NULL
                          AND rec.custom_schedule ? current_dow
                          AND rec.custom_schedule->>current_dow IS NOT NULL
                    THEN
                        target_times := ARRAY[(rec.custom_schedule->>current_dow)::time];
                    ELSE
                        CONTINUE;
                    END IF;
                ELSE
                    target_times := ARRAY[rec.checkin_time];
            END CASE;

            is_multi := COALESCE(array_length(target_times, 1), 0) > 1;
            v_owner := rec.owner_id;

            FOREACH t IN ARRAY target_times LOOP
                -- Seconds are ignored so "08:00:30" behaves like "08:00".
                v_due := v_local_today + date_trunc('minute', t::interval)::time;
                CONTINUE WHEN v_due > v_local_now OR v_due <= v_local_now - c_catch_up;

                -- slot_key distinguishes windows on a multi-window day; NULL on
                -- a single-window day keeps the legacy one-per-day dedup.
                v_slot_key := CASE WHEN is_multi THEN to_char(t, 'HH24:MI') ELSE NULL END;

                -- Per-slot: skip if this slot already has a check-in today.
                CONTINUE WHEN EXISTS (
                    SELECT 1 FROM checkins c
                    WHERE c.receiver_id = rec.receiver_id
                      AND c.family_id = rec.family_id
                      AND c.checked_in_at >= v_local_midnight
                      AND COALESCE(c.slot_key, '') = COALESCE(v_slot_key, '')
                );

                -- Per-slot idempotency: at most one scheduled request per slot
                -- per local day, however many ticks see the window as due.
                CONTINUE WHEN EXISTS (
                    SELECT 1 FROM checkin_requests cr
                    WHERE cr.receiver_id = rec.receiver_id
                      AND cr.family_id = rec.family_id
                      AND cr.type = 'scheduled'
                      AND cr.created_at >= v_local_midnight
                      AND COALESCE(cr.slot_key, '') = COALESCE(v_slot_key, '')
                );

                INSERT INTO checkin_requests (
                    family_id, receiver_id, requested_by, type, status,
                    escalation_step, next_escalation_at, slot_key
                ) VALUES (
                    rec.family_id,
                    rec.receiver_id,
                    v_owner,
                    'scheduled',
                    'pending',
                    0,
                    NOW() + (rec.grace_period_minutes || ' minutes')::interval,
                    v_slot_key
                );

                PERFORM net.http_post(
                    url := current_setting('app.edge_functions_url') || '/send-checkin-notification',
                    headers := jsonb_build_object(
                        'Content-Type', 'application/json',
                        'Authorization', 'Bearer ' || current_setting('app.service_role_key')
                    ),
                    body := jsonb_build_object(
                        'receiver_id', rec.receiver_id,
                        'family_id', rec.family_id,
                        'type', 'scheduled',
                        'slot_key', v_slot_key
                    )
                );
            END LOOP;
        EXCEPTION WHEN OTHERS THEN
            -- One malformed row (bad custom_schedule time, etc.) must not stop
            -- every other receiver's check-in for this minute.
            RAISE WARNING 'dispatch_scheduled_checkins: skipped settings % (%): %',
                rec.setting_id, SQLSTATE, SQLERRM;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- -----------------------------------------------------------------------------
-- 3. Escalation: never overwrite a request answered mid-tick.
-- -----------------------------------------------------------------------------
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
          AND COALESCE(rs.escalation_enabled, TRUE) = TRUE
          AND (cr.snoozed_until IS NULL OR cr.snoozed_until <= NOW())
    LOOP
        IF rec.escalation_step >= 3 THEN
            UPDATE checkin_requests
            SET status = 'missed'
            WHERE id = rec.request_id
              AND status = 'pending';
        ELSE
            UPDATE checkin_requests
            SET escalation_step = rec.escalation_step + 1,
                next_escalation_at = NOW() + (rec.reminder_interval_minutes || ' minutes')::interval
            WHERE id = rec.request_id
              AND status = 'pending';

            -- Answered between the SELECT and this UPDATE: nothing to send.
            CONTINUE WHEN NOT FOUND;

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
