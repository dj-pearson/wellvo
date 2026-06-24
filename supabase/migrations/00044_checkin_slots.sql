-- Daily OK: Slot-aware check-in dedup (multiple check-ins per day)
-- Migration: 00044_checkin_slots
--
-- US-IOS048. Lets a receiver have more than one scheduled check-in window per
-- day (e.g. morning + evening) without the windows collapsing into a single
-- "checked in today" row.
--
-- Backward compatibility (CLAUDE.md §A): this only LOOSENS the existing
-- one-per-day uniqueness — it never rejects a row that was previously allowed.
--   * slot_key is a nullable, additive column (safe).
--   * The replacement unique index keys on COALESCE(slot_key, ''), so rows with
--     NULL slot_key (every currently-shipped client, plus single-window
--     receivers and offline-synced check-ins) keep exactly the old
--     one-per-UTC-day behavior. Only rows that carry a distinct slot_key can
--     coexist on the same day.
-- The index keeps the same UTC-day basis as 00007 (the edge function still
-- enforces the receiver's local-day window on top of it); only the slot
-- dimension is added.

BEGIN;

-- Additive nullable column. NULL = legacy/day-level check-in (one per day).
-- A value (e.g. '08:00') identifies the scheduled window the check-in satisfies.
ALTER TABLE checkins ADD COLUMN IF NOT EXISTS slot_key TEXT;

-- Replace the one-per-UTC-day unique index with a slot-aware one. Dropping the
-- old index and creating a strictly more permissive one is backward-compatible.
DROP INDEX IF EXISTS idx_checkins_unique_daily;

CREATE UNIQUE INDEX IF NOT EXISTS idx_checkins_unique_daily_slot
    ON checkins (
        receiver_id,
        family_id,
        (date_trunc('day', checked_in_at AT TIME ZONE 'UTC')::date),
        COALESCE(slot_key, '')
    );

COMMIT;
