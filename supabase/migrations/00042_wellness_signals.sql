-- Daily OK: Optional Apple Health passive wellness signals
-- Migration: 00042_wellness_signals
--
-- US-IOS017. Strictly opt-in, privacy-minimal: a receiver may choose to share a
-- single DERIVED, AGGREGATE signal — "active today" (true/false) computed
-- on-device from a low-sensitivity HealthKit metric (step count). No raw health
-- data ever leaves the device. Owners/viewers see this only as a SUPPLEMENT to
-- an explicit check-in, never a replacement. This is reassurance, not medical
-- monitoring or fall detection.
--
-- Fully ADDITIVE per CLAUDE.md: a brand-new table with its own RLS. The receiver
-- writes their own derived signal; caregivers read it. Default is fully off
-- (no rows are written until the receiver opts in on-device), so older clients
-- and non-sharing receivers are entirely unaffected.

BEGIN;

CREATE TABLE IF NOT EXISTS wellness_signals (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_id   UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    -- The receiver's local calendar date this signal is for.
    signal_date DATE NOT NULL,
    -- Derived on-device: did the receiver move meaningfully today?
    active      BOOLEAN NOT NULL DEFAULT FALSE,
    -- Provenance, for future expansion (e.g., 'healthkit'). Never raw values.
    source      TEXT NOT NULL DEFAULT 'healthkit',
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- One signal per receiver/family/day — the device upserts it.
    UNIQUE (receiver_id, family_id, signal_date)
);

CREATE INDEX IF NOT EXISTS idx_wellness_signals_lookup
    ON wellness_signals(family_id, signal_date);

ALTER TABLE wellness_signals ENABLE ROW LEVEL SECURITY;

-- The receiver writes their OWN derived signal (insert + update for upsert).
CREATE POLICY "Receivers write own wellness signal"
    ON wellness_signals FOR INSERT
    WITH CHECK (receiver_id = auth.uid());

CREATE POLICY "Receivers update own wellness signal"
    ON wellness_signals FOR UPDATE
    USING (receiver_id = auth.uid())
    WITH CHECK (receiver_id = auth.uid());

-- The receiver can revoke (delete) their own signals.
CREATE POLICY "Receivers delete own wellness signal"
    ON wellness_signals FOR DELETE
    USING (receiver_id = auth.uid());

-- Caregivers (active owner/viewer of the family) may read the signal.
CREATE POLICY "Caregivers read family wellness signal"
    ON wellness_signals FOR SELECT
    USING (
        receiver_id = auth.uid()
        OR family_id IN (
            SELECT family_id FROM family_members
            WHERE user_id = auth.uid()
              AND role IN ('owner', 'viewer')
              AND status = 'active'
        )
    );

-- Realtime so the dashboard's supplementary indicator updates live.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
    ) THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename  = 'wellness_signals'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.wellness_signals;
    END IF;
END $$;

ALTER TABLE public.wellness_signals REPLICA IDENTITY FULL;

COMMIT;

-- Verification:
--   SELECT policyname FROM pg_policies WHERE tablename = 'wellness_signals';
--   SELECT tablename FROM pg_publication_tables WHERE tablename = 'wellness_signals';
