-- =============================================================================
-- Migration: 00047_multi_window_dispatch
-- Story: US-IOS089 — dispatch every custom-schedule window, not just one/day
--
-- US-IOS048 let a receiver configure multiple check-in windows per day
-- (custom_schedule.multiTimes), and the iOS app already scores consistency and
-- dedups per window (slot_key). But `dispatch_scheduled_checkins` only ever read
-- ONE time per day (`custom_schedule->>current_dow`) and a day-level idempotency
-- guard hard-capped it at a single scheduled request/day — so extra windows were
-- never actually prompted, and a multi-window receiver was scored against windows
-- the backend never sent.
--
-- This migration:
--   1. Adds a nullable `slot_key` to `checkin_requests` (additive; mirrors the
--      `checkins.slot_key` added in 00044). NULL = legacy day-level request.
--   2. Rewrites `dispatch_scheduled_checkins` to iterate EVERY window for the day
--      and create one request per window, keyed by slot_key, with per-slot
--      idempotency. Escalation then honors each window automatically because each
--      window is its own `checkin_requests` row that `escalation_tick` advances.
--
-- BACKWARD-COMPATIBLE (CLAUDE.md §A):
--   * `slot_key` is nullable/additive.
--   * Single-window receivers (daily, weekday_weekend, and custom days with one
--     time) produce a request with slot_key = NULL and the per-slot guards reduce
--     to the exact prior day-level behavior (COALESCE(slot_key,'') = ''). Their
--     dispatch is byte-for-byte unchanged.
--   * Only a custom day with >1 window behaves differently — and that is the bug
--     being fixed.
--
-- DEPLOY SEQUENCING: this must reach production before/with the app build that
-- relies on multi-window prompting. It only ADDS prompts for already-configured
-- multi-window receivers, so it is safe to deploy ahead of the client.
-- =============================================================================

BEGIN;

-- 1. Per-window request key (NULL = legacy day-level request).
ALTER TABLE checkin_requests ADD COLUMN IF NOT EXISTS slot_key TEXT;

-- 2. Multi-window-aware dispatch.
CREATE OR REPLACE FUNCTION dispatch_scheduled_checkins()
RETURNS void AS $$
DECLARE
    rec RECORD;
    current_dow TEXT;
    now_local_minute TEXT;
    target_times TIME[];
    is_multi BOOLEAN;
    t TIME;
    v_slot_key TEXT;
    v_owner UUID;
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
          -- Quiet hours (unchanged).
          AND (
              rs.quiet_hours_start IS NULL
              OR NOT (
                  (NOW() AT TIME ZONE rs.timezone)::time
                  BETWEEN rs.quiet_hours_start AND rs.quiet_hours_end
              )
          )
        -- NOTE: the day-level "already checked in / already has a request" guards
        -- that used to live here are now applied PER SLOT inside the loop, so a
        -- morning window being satisfied doesn't suppress the evening window.
    LOOP
        current_dow := LOWER(TO_CHAR(NOW() AT TIME ZONE rec.timezone, 'Dy'));
        now_local_minute := to_char((NOW() AT TIME ZONE rec.timezone)::time, 'HH24:MI');

        -- Build the list of scheduled times for today.
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
                -- Prefer the multiTimes array for this day; fall back to the
                -- legacy single field; skip days with no scheduled time.
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
        v_owner := (SELECT owner_id FROM families WHERE id = rec.family_id);

        FOREACH t IN ARRAY target_times LOOP
            -- Only fire the window whose time matches the current minute (HH:MI
            -- match tolerates pg_cron tick jitter).
            CONTINUE WHEN to_char(t, 'HH24:MI') <> now_local_minute;

            -- slot_key distinguishes windows on a multi-window day; NULL on a
            -- single-window day preserves the legacy one-per-day dedup exactly.
            v_slot_key := CASE WHEN is_multi THEN to_char(t, 'HH24:MI') ELSE NULL END;

            -- Per-slot: skip if this slot already has a check-in today.
            CONTINUE WHEN EXISTS (
                SELECT 1 FROM checkins c
                WHERE c.receiver_id = rec.receiver_id
                  AND c.family_id = rec.family_id
                  AND c.checked_in_at >= (NOW() AT TIME ZONE rec.timezone)::date::timestamptz
                  AND COALESCE(c.slot_key, '') = COALESCE(v_slot_key, '')
            );

            -- Per-slot idempotency: skip if this slot already has a scheduled
            -- request today (retried/delayed cron tick).
            CONTINUE WHEN EXISTS (
                SELECT 1 FROM checkin_requests cr
                WHERE cr.receiver_id = rec.receiver_id
                  AND cr.family_id = rec.family_id
                  AND cr.type = 'scheduled'
                  AND cr.created_at >= (NOW() AT TIME ZONE rec.timezone)::date::timestamptz
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
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
