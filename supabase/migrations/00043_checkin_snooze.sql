-- =============================================================================
-- Migration: 00043_checkin_snooze
-- Story: US-IOS046 — Snooze / "remind me in N minutes" for a check-in request
--
-- A receiver who sees the request but can't act right now (driving, in a
-- meeting) can snooze it, deferring the escalation chain by the snoozed amount
-- so the family isn't falsely alerted. Snoozes are bounded so they can't
-- indefinitely suppress escalation for an at-risk receiver.
--
-- Backward-compatibility (per CLAUDE.md): all changes are additive.
--   * Two NULL/defaulted columns on checkin_requests (older clients ignore them).
--   * escalation_tick() recreated (supersedes 00036) with one extra guard line;
--     non-snoozed requests behave exactly as before.
--   * One new SECURITY DEFINER RPC; no existing signature changed.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. SNOOZE COLUMNS
-- -----------------------------------------------------------------------------
ALTER TABLE checkin_requests
    ADD COLUMN IF NOT EXISTS snoozed_until TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS snooze_count INT NOT NULL DEFAULT 0;

-- -----------------------------------------------------------------------------
-- 2. ESCALATION TICK — defer snoozed requests (supersedes 00036)
--    Identical to 00036 except for the snoozed_until guard in the WHERE clause.
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
          -- Respect the per-receiver escalation toggle. Default to escalating
          -- when no settings row exists (safer for an at-risk receiver).
          AND COALESCE(rs.escalation_enabled, TRUE) = TRUE
          -- Defer while the receiver has an active snooze. The snooze RPC also
          -- pushes next_escalation_at forward, so this is belt-and-suspenders.
          AND (cr.snoozed_until IS NULL OR cr.snoozed_until <= NOW())
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

-- -----------------------------------------------------------------------------
-- 3. SNOOZE RPC
--    The receiver defers their own pending request. Bounded to MAX_SNOOZES so a
--    snooze can't indefinitely suppress escalation. p_minutes is clamped to a
--    sane range. Returns the updated row so the client can reflect the new
--    snooze count / deadline.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION snooze_checkin_request(
    p_request_id UUID,
    p_minutes INT DEFAULT 15
)
RETURNS checkin_requests AS $$
DECLARE
    v_max_snoozes CONSTANT INT := 3;
    v_minutes INT;
    v_row checkin_requests;
BEGIN
    -- Clamp the snooze window to 1..60 minutes.
    v_minutes := LEAST(GREATEST(COALESCE(p_minutes, 15), 1), 60);

    SELECT * INTO v_row
    FROM checkin_requests
    WHERE id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Check-in request not found' USING ERRCODE = 'no_data_found';
    END IF;

    -- Only the receiver may snooze their own request.
    IF v_row.receiver_id <> auth.uid() THEN
        RAISE EXCEPTION 'You can only snooze your own check-in' USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Only a still-pending request can be snoozed.
    IF v_row.status <> 'pending' THEN
        RAISE EXCEPTION 'Only a pending check-in can be snoozed' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- Bound the number of snoozes so escalation can't be suppressed forever.
    IF v_row.snooze_count >= v_max_snoozes THEN
        RAISE EXCEPTION 'Snooze limit reached' USING ERRCODE = 'check_violation';
    END IF;

    UPDATE checkin_requests
    SET snoozed_until = NOW() + (v_minutes || ' minutes')::interval,
        next_escalation_at = GREATEST(
            COALESCE(next_escalation_at, NOW()),
            NOW() + (v_minutes || ' minutes')::interval
        ),
        snooze_count = snooze_count + 1
    WHERE id = p_request_id
    RETURNING * INTO v_row;

    RETURN v_row;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION snooze_checkin_request(UUID, INT) TO authenticated;

COMMIT;
