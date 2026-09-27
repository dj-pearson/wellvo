-- Daily OK: Receiver detail — custom schedules that actually fire, quiet hours
--           that defer instead of dropping, pauses that end, honest care notes.
-- Migration: 00056_receiver_detail_schedule_integrity
--
-- ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
-- 1. iOS saved custom_schedule as a JSON *string* ("{\"mon\":\"08:00\"}"), not
--    an object. PostgREST copies a JSON value into a jsonb column verbatim, so
--    the column held a jsonb string scalar. dispatch_scheduled_checkins tests
--    `custom_schedule ? 'mon'`, which is false on a string, so it hit CONTINUE:
--    no custom-schedule check-in was ever created, and nothing escalated. Every
--    client also failed to decode the row. (Android sends an object.)
-- 2. A check-in time inside quiet hours was dropped for the day: dispatch skips
--    the receiver during quiet hours and only catches up 10 minutes, so a 06:30
--    check-in with quiet hours 22:00–07:00 was never asked and never escalated.
--    The receiver app already shows it deferred to the end of quiet hours.
-- 3. Windows were compared as local wall-clock times, so on the spring-forward
--    day a window between 02:00 and 02:50 never fell inside the catch-up range.
-- 4. Pause had no end. Owners pause for a hospital stay or a trip and forget;
--    every check-in and alert after that is silently off.
-- 5. care_notes: author_name / created_at / updated_at were whatever the client
--    sent, and an author could rewrite family_id / receiver_id / author_name on
--    an existing note. A caregiver could sign a note as the owner or a doctor,
--    or backdate it.
--
-- ─── WHAT CHANGES (all additive per CLAUDE.md §A) ───────────────────────────
--   * receiver_settings.paused_until TIMESTAMPTZ NULL (new nullable column).
--     Old clients never send it and keep seeing schedule_paused true/false.
--   * BEFORE INSERT/UPDATE trigger on receiver_settings: a string-typed
--     custom_schedule holding JSON is unwrapped to that JSON (so shipped iOS
--     builds start working); paused_until is cleared whenever not paused.
--   * One-time repair of existing string-typed custom_schedule rows.
--   * dispatch_scheduled_checkins (same signature, new body):
--       - ends expired pauses first (schedule_paused := FALSE);
--       - a window due inside quiet hours is asked when quiet hours end, if
--         that is later the same local day (matches the receiver app);
--       - due times are compared as absolute instants (DST-safe).
--   * BEFORE INSERT/UPDATE trigger on care_notes for client roles only:
--     author_name comes from users.display_name, created_at/updated_at from
--     the server clock, and an edit can change only the body. These pin values
--     silently (the 00051 pattern); no shipped client sends anything else
--     (iOS sends its own display name and edits only `body`; Android has no
--     care notes), so no request that works today is rejected.
--
-- Not changed: RLS policies (no tightening), RPC signatures, escalation_tick.

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. paused_until
-- -----------------------------------------------------------------------------
ALTER TABLE receiver_settings
    ADD COLUMN IF NOT EXISTS paused_until TIMESTAMPTZ;

COMMENT ON COLUMN receiver_settings.paused_until IS
    'When a pause ends by itself. NULL = until someone resumes (or not paused). Cleared by trigger when schedule_paused is FALSE; dispatch resumes expired pauses.';

-- -----------------------------------------------------------------------------
-- 2. Normalise receiver_settings writes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION normalize_receiver_settings()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_unwrapped JSONB;
BEGIN
    -- Dual-read at write time: a JSON string holding an object is the object.
    IF NEW.custom_schedule IS NOT NULL AND jsonb_typeof(NEW.custom_schedule) = 'string' THEN
        BEGIN
            v_unwrapped := (NEW.custom_schedule #>> '{}')::jsonb;
            IF jsonb_typeof(v_unwrapped) = 'object' THEN
                NEW.custom_schedule := v_unwrapped;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- Not JSON inside: leave as sent (dispatch skips it, as before).
            NULL;
        END;
    END IF;

    -- A pause end only means something while paused. Clearing it here also
    -- stops a stale end date from ending a later pause set by an old client
    -- that doesn't know the column.
    IF NEW.schedule_paused IS DISTINCT FROM TRUE THEN
        NEW.paused_until := NULL;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS receiver_settings_normalize ON receiver_settings;
CREATE TRIGGER receiver_settings_normalize
    BEFORE INSERT OR UPDATE ON receiver_settings
    FOR EACH ROW EXECUTE FUNCTION normalize_receiver_settings();

-- -----------------------------------------------------------------------------
-- 3. Repair rows already stored as strings (the trigger does the unwrapping).
-- -----------------------------------------------------------------------------
UPDATE receiver_settings
SET custom_schedule = custom_schedule
WHERE jsonb_typeof(custom_schedule) = 'string';

-- -----------------------------------------------------------------------------
-- 4. Dispatch
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
    v_t TIME;
    v_quiet_start TIME;
    v_quiet_end TIME;
    v_due_at TIMESTAMPTZ;
    v_slot_key TEXT;
    v_owner UUID;
BEGIN
    -- Pauses that have run their course end now, before anyone is skipped.
    UPDATE receiver_settings
    SET schedule_paused = FALSE,
        paused_until = NULL
    WHERE schedule_paused = TRUE
      AND paused_until IS NOT NULL
      AND paused_until <= NOW();

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

            v_quiet_start := date_trunc('minute', rec.quiet_hours_start::interval)::time;
            v_quiet_end := date_trunc('minute', rec.quiet_hours_end::interval)::time;
            IF v_quiet_start = v_quiet_end THEN
                v_quiet_start := NULL;
                v_quiet_end := NULL;
            END IF;

            -- Nothing is sent while quiet hours are on (ranges may wrap midnight).
            IF v_quiet_start IS NOT NULL AND v_quiet_end IS NOT NULL THEN
                IF (v_quiet_start < v_quiet_end
                        AND v_local_time >= v_quiet_start AND v_local_time < v_quiet_end)
                   OR (v_quiet_start > v_quiet_end
                        AND (v_local_time >= v_quiet_start OR v_local_time < v_quiet_end))
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
                       AND jsonb_typeof(rec.custom_schedule) = 'object'
                       AND rec.custom_schedule->'multiTimes' ? current_dow
                       AND jsonb_typeof(rec.custom_schedule->'multiTimes'->current_dow) = 'array'
                       AND jsonb_array_length(rec.custom_schedule->'multiTimes'->current_dow) > 0
                    THEN
                        SELECT array_agg(elem::time)
                        INTO target_times
                        FROM jsonb_array_elements_text(rec.custom_schedule->'multiTimes'->current_dow) AS elem;
                    ELSIF rec.custom_schedule IS NOT NULL
                          AND jsonb_typeof(rec.custom_schedule) = 'object'
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
                v_t := date_trunc('minute', t::interval)::time;

                -- A window due inside quiet hours is asked when they end, if
                -- that is later the same local day (the receiver app shows it
                -- that way). One whose quiet hours run past midnight is still
                -- skipped; the apps block saving that combination.
                IF v_quiet_start IS NOT NULL AND v_quiet_end IS NOT NULL
                   AND v_t < v_quiet_end
                   AND ((v_quiet_start < v_quiet_end AND v_t >= v_quiet_start)
                        OR (v_quiet_start > v_quiet_end))
                THEN
                    v_t := v_quiet_end;
                END IF;

                -- Absolute instant, so a window in the spring-forward gap maps
                -- to just after it instead of never falling inside the window.
                v_due_at := (v_local_today + v_t) AT TIME ZONE v_tz;
                CONTINUE WHEN v_due_at > NOW() OR v_due_at <= NOW() - c_catch_up;

                -- slot_key distinguishes windows on a multi-window day; NULL on
                -- a single-window day keeps the legacy one-per-day dedup. It is
                -- the scheduled time, not the deferred one.
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
-- 5. care_notes: server-owned author name and timestamps; edits change body only
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION guard_care_note_write()
RETURNS TRIGGER
-- SECURITY INVOKER on purpose: is_client_role() reads current_user, which a
-- SECURITY DEFINER function would replace with its owner.
LANGUAGE plpgsql AS $$
DECLARE
    v_name TEXT;
BEGIN
    -- Server-side code (service role, SECURITY DEFINER functions) is trusted.
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        SELECT NULLIF(btrim(display_name), '') INTO v_name
        FROM users WHERE id = NEW.author_id;
        NEW.author_name := COALESCE(v_name, 'A caregiver');
        NEW.created_at := NOW();
        NEW.updated_at := NOW();
    ELSE
        NEW.id := OLD.id;
        NEW.family_id := OLD.family_id;
        NEW.receiver_id := OLD.receiver_id;
        NEW.author_id := OLD.author_id;
        NEW.author_name := OLD.author_name;
        NEW.created_at := OLD.created_at;
        -- updated_at is set by trg_care_notes_touch.
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_care_notes_guard ON care_notes;
CREATE TRIGGER trg_care_notes_guard
    BEFORE INSERT OR UPDATE ON care_notes
    FOR EACH ROW EXECUTE FUNCTION guard_care_note_write();

COMMIT;

-- Verification:
--   SELECT count(*) FROM receiver_settings WHERE jsonb_typeof(custom_schedule) = 'string';  -- 0
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'receiver_settings' AND column_name = 'paused_until';
--   SELECT tgname FROM pg_trigger WHERE tgname IN ('receiver_settings_normalize', 'trg_care_notes_guard');
