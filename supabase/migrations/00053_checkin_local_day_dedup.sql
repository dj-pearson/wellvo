-- Daily OK: De-duplicate check-ins by the receiver's LOCAL day, not the UTC day.
-- Migration: 00053_checkin_local_day_dedup
--
-- ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
-- 00021 deliberately retired the one-per-UTC-day unique index because it
-- collides a west-of-UTC evening check-in with the next morning's (8pm ET Monday
-- and 8am ET Tuesday are the same UTC day). 00044/00049 then brought the same
-- UTC-day basis back inside `idx_checkins_unique_daily_slot`. So for every US
-- receiver on a single daily window, a check-in made in the evening makes the
-- next morning's check-in fail the insert: process-checkin-response returns 500,
-- the pending request is never closed, and the owner gets a false "missed"
-- escalation for someone who tapped "I'm OK".
--
-- ─── WHAT CHANGES ────────────────────────────────────────────────────────────
--   * New nullable column checkins.local_date: the receiver's local calendar day
--     for the check-in, written by process-checkin-response.
--   * `idx_checkins_unique_daily_slot` is rebuilt on
--     (receiver_id, family_id, local_date, COALESCE(slot_key,'')) for rows that
--     carry a local_date. The index NAME is kept on purpose: 00044 and 00049 use
--     `CREATE UNIQUE INDEX IF NOT EXISTS idx_checkins_unique_daily_slot`, so a
--     replay of those files stays a no-op instead of rebuilding the UTC index.
--   * Existing rows keep local_date NULL and are simply outside the index; the
--     edge function's local-day lookup still dedups them.
--
-- BACKWARD-COMPATIBLE (CLAUDE.md §A): an additive nullable column, and a unique
-- index that only ever LOOSENS what was accepted before (a new-shape row is
-- unique per local day, which is never stricter than per UTC day for rows the
-- old index covered, and legacy rows are no longer constrained at all). No
-- client reads or writes local_date. Idempotent: safe to replay.
--
-- Deploy with or after the matching edge-function change; until then new rows
-- carry no local_date and are deduplicated by the edge function alone.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

ALTER TABLE checkins ADD COLUMN IF NOT EXISTS local_date DATE;

COMMENT ON COLUMN checkins.local_date IS
    'Receiver''s local calendar day of checked_in_at (their IANA zone at write time). NULL on rows written before 00053.';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname = 'idx_checkins_unique_daily_slot'
          AND indexdef LIKE '%local_date%'
    ) THEN
        DROP INDEX IF EXISTS idx_checkins_unique_daily_slot;
        CREATE UNIQUE INDEX idx_checkins_unique_daily_slot
            ON checkins (receiver_id, family_id, local_date, COALESCE(slot_key, ''))
            WHERE local_date IS NOT NULL;
    END IF;
END $$;

COMMIT;
