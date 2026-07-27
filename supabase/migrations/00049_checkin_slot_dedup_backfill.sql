-- Daily OK: Corrective — resolve UTC-day check-in collisions for the slot-aware
--                        unique index (fixes the 00007 replay failure).
-- Migration: 00049_checkin_slot_dedup_backfill
--
-- ─── WHY THIS EXISTS ─────────────────────────────────────────────────────────
-- The migration runner replayed 00007_duplicate_checkin_prevention against the
-- live production DB and failed:
--
--   ERROR: could not create unique index "idx_checkins_unique_daily"
--   DETAIL: Key (receiver_id, family_id, UTC-day)=(25db547c…, d9d84091…, 2026-07-21)
--           is duplicated.
--
-- ROOT CAUSE — this is NOT a missing dependency and NOT plain junk data:
--   * 00007's index `idx_checkins_unique_daily` was DELETED on purpose in 00021
--     (its UTC-day basis wrongly collides a west-of-UTC evening check-in with the
--     next-morning check-in — different LOCAL days, same UTC day). Dedup was moved
--     into the `process-checkin-response` edge function, keyed on the receiver's
--     IANA local day.
--   * 00044 drops it AGAIN and replaces it with the slot-aware index
--     `idx_checkins_unique_daily_slot` (partitioned by COALESCE(slot_key,'')).
--   * The tracker is empty (appliedCount = 0) so the whole history is replaying
--     against a populated prod DB. 00007 reads as "absent" only because 00021/00044
--     removed its index — the replay mistakes a REVERTED migration for an
--     UNAPPLIED one and tries to rebuild an abandoned constraint.
--
-- Do NOT force 00007 to pass by deleting check-ins: that would destroy legitimate
-- rows (the exact west-of-UTC false-positive 00021 documented) to build an index
-- that 00021/00044 immediately drop. See the operator runbook in the PR summary:
-- 00007 should be marked applied / skipped, not replayed.
--
-- The one thing that genuinely still needs doing is creating 00044's slot-aware
-- index — and it hits the SAME collision, because the pre-existing rows all carry
-- slot_key = NULL (COALESCE → '' → still one-per-UTC-day). This migration resolves
-- that NON-DESTRUCTIVELY (no check-in is deleted) by giving the later same-UTC-day
-- rows a distinct, clearly-synthetic slot_key, then asserts the slot-aware index.
--
-- Idempotent: re-running is a no-op (only touches NULL-slot collision rows; index
-- is IF NOT EXISTS).
--
-- NOTE (ordering): a file numbered after 00007 cannot unblock the replay on its
-- own — 00044's index build hits the same collision first. Run the slot_key
-- backfill block below against the DB BEFORE re-running the sequence (or run this
-- whole file once), so that when the runner reaches 00044 the rows already carry
-- distinct slot_keys and `idx_checkins_unique_daily_slot` builds cleanly. This
-- file then lands as a confirming no-op.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- 1. Ensure the slot dimension exists (mirrors 00044; safe if already present or
--    if 00044 has not yet been (re)applied).
ALTER TABLE checkins ADD COLUMN IF NOT EXISTS slot_key TEXT;

-- 2. Non-destructively separate same-UTC-day, NULL-slot collisions. Keep the
--    EARLIEST row of each (receiver, family, UTC-day) group untouched (slot_key
--    stays NULL = legacy day-level). Every later row gets a guaranteed-unique,
--    obviously-synthetic slot_key so no check-in is lost and the slot-aware
--    unique index can build. 'legacy-dup-' || id is unique because id is the PK.
WITH ranked AS (
    SELECT
        id,
        row_number() OVER (
            PARTITION BY
                receiver_id,
                family_id,
                (date_trunc('day', checked_in_at AT TIME ZONE 'UTC')::date)
            ORDER BY checked_in_at, id
        ) AS rn
    FROM checkins
    WHERE slot_key IS NULL
)
UPDATE checkins c
SET slot_key = 'legacy-dup-' || c.id::text
FROM ranked r
WHERE c.id = r.id
  AND r.rn > 1;

-- 3. Assert the go-forward slot-aware unique index (matches 00044). We do NOT
--    recreate idx_checkins_unique_daily — it was intentionally retired in 00021
--    and 00044 and must stay gone.
CREATE UNIQUE INDEX IF NOT EXISTS idx_checkins_unique_daily_slot
    ON checkins (
        receiver_id,
        family_id,
        (date_trunc('day', checked_in_at AT TIME ZONE 'UTC')::date),
        COALESCE(slot_key, '')
    );

COMMIT;
