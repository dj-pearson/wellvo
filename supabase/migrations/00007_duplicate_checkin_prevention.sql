-- Wellvo: Duplicate Check-In Prevention
-- Migration: 00007_duplicate_checkin_prevention
--
-- Adds a unique constraint to prevent multiple check-ins per receiver
-- per family per calendar day. Uses a unique index on the date portion
-- of checked_in_at to allow the constraint while keeping the full timestamp.

BEGIN;

-- Create unique index on (receiver_id, family_id, date)
-- This prevents duplicate check-ins on the same calendar day
CREATE UNIQUE INDEX IF NOT EXISTS idx_checkins_unique_daily
    ON checkins (receiver_id, family_id, (DATE(checked_in_at)));

COMMIT;
