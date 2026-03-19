-- Wellvo: Duplicate Check-In Prevention
-- Migration: 00007_duplicate_checkin_prevention
--
-- Adds a unique constraint to prevent multiple check-ins per receiver
-- per family per calendar day. Uses a unique index on the date portion
-- of checked_in_at to allow the constraint while keeping the full timestamp.

BEGIN;

-- Create unique index on (receiver_id, family_id, date)
-- This prevents duplicate check-ins on the same calendar day.
-- Uses date_trunc with explicit UTC cast — must be IMMUTABLE for index expressions.
-- checked_in_at is stored as timestamptz; we normalise to UTC date for uniqueness.
CREATE UNIQUE INDEX IF NOT EXISTS idx_checkins_unique_daily
    ON checkins (receiver_id, family_id, (date_trunc('day', checked_in_at AT TIME ZONE 'UTC')::date));

COMMIT;
