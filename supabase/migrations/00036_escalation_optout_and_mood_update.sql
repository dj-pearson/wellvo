-- Escalation Opt-Out + Mood Update Permission
-- Migration: 00036_escalation_optout_and_mood_update
--
-- 1. Honor receiver_settings.escalation_enabled in escalation_tick. The iOS
--    settings UI lets an owner turn off the escalation chain ("You won't
--    receive alerts for missed check-ins"), but the backend escalated anyway.
--    Now a receiver with escalation disabled is skipped entirely: their pending
--    requests are left alone and cleaned up by expire_old_requests after 24h,
--    so no reminder/owner/viewer alerts fire.
--
-- 2. Allow receivers to UPDATE their own checkins. Needed so the post-check-in
--    mood picker can attach a mood to the row the edge function just created.
--    Additive (more permissive) policy — does not change any existing access.
--
-- Both changes are backward-compatible: CREATE OR REPLACE of an existing
-- pg_cron function (schedule unchanged) and a new additive RLS policy.

BEGIN;

-- =============================================================================
-- 1. ESCALATION TICK — skip receivers who opted out of escalation
--    (supersedes the definition in 00035)
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
          -- Respect the per-receiver escalation toggle. Default to escalating
          -- when no settings row exists (safer for an at-risk receiver).
          AND COALESCE(rs.escalation_enabled, TRUE) = TRUE
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

-- =============================================================================
-- 2. RECEIVERS CAN UPDATE OWN CHECKINS (for the post-check-in mood picker)
-- =============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'checkins'
          AND policyname = 'Receivers can update own checkins'
    ) THEN
        CREATE POLICY "Receivers can update own checkins"
            ON checkins FOR UPDATE
            USING (receiver_id = auth.uid())
            WITH CHECK (receiver_id = auth.uid());
    END IF;
END $$;

COMMIT;
