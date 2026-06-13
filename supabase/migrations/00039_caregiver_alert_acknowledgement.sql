-- Daily OK: Multi-caregiver alert acknowledgement ("I've got this")
-- Migration: 00039_caregiver_alert_acknowledgement
--
-- US-IOS013. When several caregivers (owner + viewers) share a family, a missed
-- check-in / pattern alert currently makes everyone panic and call at once. This
-- lets one caregiver tap "I've got this" so the others see "Handled by <name>"
-- and stand down. Fully ADDITIVE and forward-only per CLAUDE.md:
--   * Three nullable columns on `alerts` (no change to existing shape; older
--     clients simply ignore them and never render the ack UI).
--   * A new SECURITY DEFINER RPC so acknowledgement is authorized centrally
--     without granting viewers broad UPDATE on `alerts`.
--   * A new additive SELECT policy so viewers (not just owners) can read their
--     family's alerts and receive the realtime UPDATE when one is acknowledged.
-- `alerts` is already in the supabase_realtime publication with REPLICA IDENTITY
-- FULL (migration 00020), so the acknowledgement UPDATE streams to co-caregivers
-- with no further wiring.

BEGIN;

-- 1. Additive nullable columns. `acknowledged_by_name` is denormalized so other
--    caregivers can render "Handled by <name>" without a join / extra fetch.
ALTER TABLE alerts ADD COLUMN IF NOT EXISTS acknowledged_by UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE alerts ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ;
ALTER TABLE alerts ADD COLUMN IF NOT EXISTS acknowledged_by_name TEXT;

-- 2. Viewers can read their family's alerts (owners already can, via 00006).
--    Additive / more-permissive only.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename  = 'alerts'
          AND policyname = 'Viewers can read family alerts'
    ) THEN
        CREATE POLICY "Viewers can read family alerts"
            ON alerts FOR SELECT
            USING (
                family_id IN (
                    SELECT family_id FROM family_members
                    WHERE user_id = auth.uid()
                      AND role IN ('owner', 'viewer')
                      AND status = 'active'
                )
            );
    END IF;
END $$;

-- 3. Acknowledge / release RPC. Any ACTIVE caregiver (owner or viewer) in the
--    alert's family may acknowledge or release it. Reversible: pass
--    p_release => TRUE to clear the acknowledgement before the situation
--    resolves. Returns the updated alert row.
CREATE OR REPLACE FUNCTION acknowledge_alert(
    p_alert_id UUID,
    p_release  BOOLEAN DEFAULT FALSE
)
RETURNS alerts AS $$
DECLARE
    v_alert      alerts;
    v_family_id  UUID;
    v_name       TEXT;
BEGIN
    SELECT family_id INTO v_family_id FROM alerts WHERE id = p_alert_id;
    IF v_family_id IS NULL THEN
        RAISE EXCEPTION 'Alert not found' USING ERRCODE = 'no_data_found';
    END IF;

    -- Authorization: caller must be an active owner/viewer of the family.
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

    IF p_release THEN
        UPDATE alerts
           SET acknowledged_by = NULL,
               acknowledged_at = NULL,
               acknowledged_by_name = NULL
         WHERE id = p_alert_id
        RETURNING * INTO v_alert;
    ELSE
        SELECT display_name INTO v_name FROM users WHERE id = auth.uid();
        UPDATE alerts
           SET acknowledged_by = auth.uid(),
               acknowledged_at = NOW(),
               acknowledged_by_name = COALESCE(v_name, 'A caregiver')
         WHERE id = p_alert_id
        RETURNING * INTO v_alert;
    END IF;

    RETURN v_alert;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION acknowledge_alert(UUID, BOOLEAN) TO authenticated;

COMMIT;

-- Verification:
--   SELECT acknowledged_by, acknowledged_at, acknowledged_by_name FROM alerts LIMIT 1;
--   SELECT proname FROM pg_proc WHERE proname = 'acknowledge_alert';
