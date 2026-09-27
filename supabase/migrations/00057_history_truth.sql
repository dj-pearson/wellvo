-- Daily OK: History tab — the same schedule for every caregiver, and a record
-- that can't be quietly rewritten.
-- Migration: 00057_history_truth
--
-- ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
-- 1. Viewers (co-caregivers) open the same History tab as the owner, but RLS
--    only lets owners and the receiver read receiver_settings. The viewer's
--    heatmap therefore ran with no schedule, so a weekdays-only parent showed
--    every weekend as Missed. The owner, looking at the same data, saw green.
--    receiver_settings also holds the receiver's home coordinates, so the
--    table's RLS is NOT widened. Instead, a SECURITY DEFINER RPC returns the
--    schedule fields only (no home_latitude / home_longitude), to the owner
--    and to active owner/viewer members of that family.
--
-- 2. A receiver could POST /rest/v1/checkins directly with any checked_in_at,
--    past or future. History, the heatmap, the streak and the exported PDF all
--    showed these rows as real. process-checkin-response already clamps
--    occurred_at to 7 days back / 5 minutes ahead (shared/checkin-time.ts);
--    the direct path now gets the same bounds. The value is CLAMPED, never
--    rejected, so an older build's offline replay (which inserted directly)
--    keeps working.
--
-- 3. The 00051 UPDATE guard pinned response_type but not the location columns
--    or kid_response_type. A kid receiver could PATCH their own row to erase
--    an SOS after the alert fired, or move a past check-in's coordinates. Now
--    the coordinates are pinned, and an 'sos' stays 'sos'. Every other
--    kid_response_type change is still allowed (Android sets it after a
--    check-in), as are mood and location_label.
--
-- ─── BACKWARD COMPATIBILITY (CLAUDE.md §A) ───────────────────────────────────
--   * New RPC only; no RLS policy is added, removed or tightened.
--   * Trigger changes are silent (the 00051 pattern): nothing that a shipped
--     iOS or Android build sends starts failing. Audited writes:
--       iOS:     UPDATE checkins SET mood.
--       Android: UPDATE checkins SET mood / location_label / kid_response_type.
--       No shipped build INSERTs into checkins directly (both go through
--       process-checkin-response, which runs as service_role and is untouched).
--   * local_date is deliberately NOT computed for direct inserts: that would
--     put those rows under the 00053 unique index and could turn an old
--     build's replay into a 23505 error.
-- Idempotent: safe to replay.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- 1. Schedules for everyone who can see History --------------------------------
CREATE OR REPLACE FUNCTION family_receiver_schedules(p_family_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
BEGIN
    IF NOT (
        EXISTS (SELECT 1 FROM families f WHERE f.id = p_family_id AND f.owner_id = auth.uid())
        OR EXISTS (
            SELECT 1 FROM family_members m
            WHERE m.family_id = p_family_id
              AND m.user_id = auth.uid()
              AND m.role IN ('owner', 'viewer')
              AND m.status = 'active'
        )
    ) THEN
        RAISE EXCEPTION 'Not authorized for this family'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Explicit column list on purpose: a column added to receiver_settings
    -- later must not leak to viewers by default. The keys match the table's
    -- column names, so the apps decode this with their existing settings model.
    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'id',                        rs.id,
            'family_member_id',          rs.family_member_id,
            'checkin_time',              rs.checkin_time,
            'timezone',                  rs.timezone,
            'grace_period_minutes',      rs.grace_period_minutes,
            'reminder_interval_minutes', rs.reminder_interval_minutes,
            'escalation_enabled',        rs.escalation_enabled,
            'quiet_hours_start',         rs.quiet_hours_start,
            'quiet_hours_end',           rs.quiet_hours_end,
            'mood_tracking_enabled',     rs.mood_tracking_enabled,
            'sms_escalation_enabled',    rs.sms_escalation_enabled,
            'is_active',                 rs.is_active,
            'location_tracking_enabled', rs.location_tracking_enabled,
            'geofence_radius_meters',    rs.geofence_radius_meters,
            'location_alert_enabled',    rs.location_alert_enabled,
            'receiver_mode',             rs.receiver_mode,
            'schedule_type',             rs.schedule_type,
            'weekend_checkin_time',      rs.weekend_checkin_time,
            'custom_schedule',           rs.custom_schedule,
            'schedule_paused',           rs.schedule_paused,
            'paused_until',              rs.paused_until
        ))
        FROM receiver_settings rs
        JOIN family_members fm ON fm.id = rs.family_member_id
        WHERE fm.family_id = p_family_id
          AND fm.role = 'receiver'
    ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION family_receiver_schedules(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION family_receiver_schedules(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION family_receiver_schedules(UUID) TO authenticated;

COMMENT ON FUNCTION family_receiver_schedules(UUID) IS
    'Schedule fields of every receiver in the family (no home coordinates), for the owner and active owner/viewer members. Used by History so co-caregivers judge missed days against the real schedule.';

-- 2 + 3. Check-in rows: bounded time on insert, pinned facts on update -------
CREATE OR REPLACE FUNCTION guard_checkins_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NOT is_family_member(NEW.family_id) THEN
            RAISE EXCEPTION 'Not a member of this family'
                USING ERRCODE = 'insufficient_privilege';
        END IF;
        -- Same window process-checkin-response accepts for occurred_at: no
        -- check-ins in the future, none backdated more than 7 days.
        NEW.checked_in_at := LEAST(
            GREATEST(COALESCE(NEW.checked_in_at, NOW()), NOW() - INTERVAL '7 days'),
            NOW()
        );
    ELSE
        NEW.id := OLD.id;
        NEW.receiver_id := OLD.receiver_id;
        NEW.family_id := OLD.family_id;
        NEW.checked_in_at := OLD.checked_in_at;
        NEW.response_type := OLD.response_type;
        NEW.source := OLD.source;
        NEW.slot_key := OLD.slot_key;
        -- Where a check-in happened is a fact of that check-in.
        NEW.latitude := OLD.latitude;
        NEW.longitude := OLD.longitude;
        NEW.location_accuracy_meters := OLD.location_accuracy_meters;
        NEW.distance_from_home_meters := OLD.distance_from_home_meters;
        -- An SOS can't be taken back after the alert went out.
        IF OLD.kid_response_type = 'sos' THEN
            NEW.kid_response_type := OLD.kid_response_type;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- The trigger itself is unchanged (00051); re-create it so a replay on a
-- database without it still ends up guarded.
DROP TRIGGER IF EXISTS checkins_guard_client_write ON checkins;
CREATE TRIGGER checkins_guard_client_write
    BEFORE INSERT OR UPDATE ON checkins
    FOR EACH ROW EXECUTE FUNCTION guard_checkins_client_write();

COMMIT;
