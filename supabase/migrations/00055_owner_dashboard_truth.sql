-- Daily OK: Owner dashboard truthfulness — durable stand-down, viewer access to
--           request status, receiver notification status, race-free "I've got
--           this".
-- Migration: 00055_owner_dashboard_truth
--
-- ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
-- 1. "Stop alerts" (cancel-escalation) only nulled next_escalation_at on
--    PENDING rows and recorded nothing else. The dashboard re-read the same row
--    (escalation_step >= 1) on the next reload, so the escalating banner and
--    the Lock Screen Live Activity came straight back; on a MISSED row nothing
--    changed at all. Nobody could tell who stood down, or when.
-- 2. checkin_requests had SELECT policies for the receiver and the owner only.
--    Viewers (co-caregivers alerted at escalation step 3) read zero rows, so
--    their dashboard showed "Pending" for someone who had MISSED, and "Checked
--    In" for someone ignoring a later on-demand request.
-- 3. push_tokens is readable only by its own user, so the owner dashboard's
--    "has notifications" lookup always came back empty and every receiver card
--    warned "hasn't enabled notifications". Tokens are credentials and must not
--    be widened; owners need a yes/no per receiver only.
-- 4. acknowledge_alert() claims unconditionally (last writer wins) and lets
--    any caregiver release anyone's claim.
--
-- ─── WHAT CHANGES ────────────────────────────────────────────────────────────
--   * checkin_requests.stood_down_at / stood_down_by: new nullable columns,
--     written by cancel-escalation (service role) for pending AND missed rows.
--     The 00051 client-write guard is extended so apps cannot set them (a
--     receiver could otherwise silence the owner's banner on their own row).
--   * New SELECT policy: active viewers can read their family's requests.
--   * New RPC family_receiver_push_status(family) → (user_id, has_active_token)
--     for active owners/viewers of that family. Booleans only; no tokens.
--   * New RPC acknowledge_alert_v2(alert, release): claims only when unclaimed
--     (or already the caller's), releases only the caller's own claim (or any
--     claim, for the family owner). Returns the current row either way, so the
--     app can say "Already handled by X". acknowledge_alert() is unchanged.
--
-- BACKWARD-COMPATIBLE (CLAUDE.md §A): nullable columns, a more-permissive
-- SELECT policy, two new functions. No existing column, policy or function
-- signature is removed or tightened for any shipped client: no shipped client
-- writes the new columns. Idempotent: safe to replay.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- 1. Durable stand-down record ------------------------------------------------
ALTER TABLE checkin_requests ADD COLUMN IF NOT EXISTS stood_down_at TIMESTAMPTZ;
ALTER TABLE checkin_requests ADD COLUMN IF NOT EXISTS stood_down_by UUID
    REFERENCES users(id) ON DELETE SET NULL;

COMMENT ON COLUMN checkin_requests.stood_down_at IS
    'When a caregiver stopped escalation for this request after reaching the receiver another way (cancel-escalation). NULL = not stood down.';

-- Same guard as 00051, plus the two new server-owned columns.
CREATE OR REPLACE FUNCTION guard_checkin_requests_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() OR TG_OP <> 'UPDATE' THEN
        RETURN NEW;
    END IF;

    NEW.id := OLD.id;
    NEW.family_id := OLD.family_id;
    NEW.receiver_id := OLD.receiver_id;
    NEW.requested_by := OLD.requested_by;
    NEW.type := OLD.type;
    NEW.created_at := OLD.created_at;
    NEW.escalation_step := OLD.escalation_step;
    NEW.next_escalation_at := OLD.next_escalation_at;
    NEW.snoozed_until := OLD.snoozed_until;
    NEW.snooze_count := OLD.snooze_count;
    NEW.slot_key := OLD.slot_key;
    NEW.stood_down_at := OLD.stood_down_at;
    NEW.stood_down_by := OLD.stood_down_by;
    RETURN NEW;
END;
$$;

-- 2. Viewers can read their family's requests ----------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename  = 'checkin_requests'
          AND policyname = 'Viewers can read family requests'
    ) THEN
        CREATE POLICY "Viewers can read family requests"
            ON checkin_requests FOR SELECT
            USING (
                family_id IN (
                    SELECT family_id FROM family_members
                    WHERE user_id = auth.uid()
                      AND role = 'viewer'
                      AND status = 'active'
                )
            );
    END IF;
END $$;

-- 3. Receiver notification status, without exposing tokens --------------------
CREATE OR REPLACE FUNCTION family_receiver_push_status(p_family_id UUID)
RETURNS TABLE (user_id UUID, has_active_token BOOLEAN)
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

    RETURN QUERY
        SELECT fm.user_id,
               EXISTS (
                   SELECT 1 FROM push_tokens pt
                   WHERE pt.user_id = fm.user_id AND pt.is_active = TRUE
               )
        FROM family_members fm
        WHERE fm.family_id = p_family_id
          AND fm.role = 'receiver'
          AND fm.status = 'active';
END;
$$;

REVOKE ALL ON FUNCTION family_receiver_push_status(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION family_receiver_push_status(UUID) TO authenticated;

-- 4. Race-free acknowledgement -------------------------------------------------
CREATE OR REPLACE FUNCTION acknowledge_alert_v2(
    p_alert_id UUID,
    p_release  BOOLEAN DEFAULT FALSE
)
RETURNS alerts
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_alert     alerts;
    v_family_id UUID;
    v_is_owner  BOOLEAN;
    v_name      TEXT;
BEGIN
    SELECT family_id INTO v_family_id FROM alerts WHERE id = p_alert_id;
    IF v_family_id IS NULL THEN
        RAISE EXCEPTION 'Alert not found' USING ERRCODE = 'no_data_found';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM family_members
        WHERE family_id = v_family_id
          AND user_id = auth.uid()
          AND role IN ('owner', 'viewer')
          AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'Not authorized to acknowledge alerts for this family'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    v_is_owner := EXISTS (SELECT 1 FROM families WHERE id = v_family_id AND owner_id = auth.uid());

    IF p_release THEN
        UPDATE alerts
           SET acknowledged_by = NULL,
               acknowledged_at = NULL,
               acknowledged_by_name = NULL
         WHERE id = p_alert_id
           AND (acknowledged_by = auth.uid() OR v_is_owner);
    ELSE
        SELECT display_name INTO v_name FROM users WHERE id = auth.uid();
        UPDATE alerts
           SET acknowledged_by = auth.uid(),
               acknowledged_at = NOW(),
               acknowledged_by_name = COALESCE(v_name, 'A caregiver')
         WHERE id = p_alert_id
           AND (acknowledged_at IS NULL OR acknowledged_by = auth.uid());
    END IF;

    -- Whether or not this call changed anything, hand back the row as it now
    -- stands so the caller sees who actually holds the claim.
    SELECT * INTO v_alert FROM alerts WHERE id = p_alert_id;
    RETURN v_alert;
END;
$$;

REVOKE ALL ON FUNCTION acknowledge_alert_v2(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION acknowledge_alert_v2(UUID, BOOLEAN) TO authenticated;

COMMIT;

-- Verification:
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'checkin_requests' AND column_name LIKE 'stood_down%';   -- 2 rows
--   SELECT policyname FROM pg_policies
--    WHERE tablename = 'checkin_requests' AND policyname = 'Viewers can read family requests';
--   SELECT proname FROM pg_proc
--    WHERE proname IN ('family_receiver_push_status', 'acknowledge_alert_v2');   -- 2 rows
