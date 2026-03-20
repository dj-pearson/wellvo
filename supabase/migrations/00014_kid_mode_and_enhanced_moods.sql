-- Wellvo: Kid Mode and Enhanced Moods
-- Migration: 00014_kid_mode_and_enhanced_moods
-- Features:
--   1. New mood_type enum values for richer emotional check-ins
--   2. Kid mode for receiver_settings (simplified UI for children)
--   3. Location label on check-ins (e.g. "School", "Home")
--   4. Kid response type on check-ins (e.g. emoji-based responses)
--   5. Receiver mode on invite tokens so new invites carry the mode

-- =============================================================================
-- 1. NEW MOOD_TYPE ENUM VALUES
-- ALTER TYPE ... ADD VALUE cannot run inside a transaction block.
-- Using IF NOT EXISTS so this is safe to re-run.
-- =============================================================================

ALTER TYPE mood_type ADD VALUE IF NOT EXISTS 'excited';
ALTER TYPE mood_type ADD VALUE IF NOT EXISTS 'bored';
ALTER TYPE mood_type ADD VALUE IF NOT EXISTS 'hungry';
ALTER TYPE mood_type ADD VALUE IF NOT EXISTS 'scared';
ALTER TYPE mood_type ADD VALUE IF NOT EXISTS 'having_fun';

-- =============================================================================
-- 2. SCHEMA CHANGES (inside transaction for atomicity)
-- =============================================================================

BEGIN;

-- Add receiver_mode to receiver_settings
-- Values: 'standard' (default adult UI), 'kid' (simplified child-friendly UI)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'receiver_settings' AND column_name = 'receiver_mode'
    ) THEN
        ALTER TABLE receiver_settings
            ADD COLUMN receiver_mode TEXT NOT NULL DEFAULT 'standard';
    END IF;
END $$;

-- Add location_label to checkins
-- Free-text label like "Home", "School", "Grandma's house"
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'checkins' AND column_name = 'location_label'
    ) THEN
        ALTER TABLE checkins
            ADD COLUMN location_label TEXT;
    END IF;
END $$;

-- Add kid_response_type to checkins
-- Captures the kid-mode response variant (e.g. 'thumbs_up', 'emoji_happy', 'sticker')
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'checkins' AND column_name = 'kid_response_type'
    ) THEN
        ALTER TABLE checkins
            ADD COLUMN kid_response_type TEXT;
    END IF;
END $$;

-- Add receiver_mode to invite_tokens
-- So the invite carries the intended mode for the new receiver
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'invite_tokens' AND column_name = 'receiver_mode'
    ) THEN
        ALTER TABLE invite_tokens
            ADD COLUMN receiver_mode TEXT NOT NULL DEFAULT 'standard';
    END IF;
END $$;

-- Add CHECK constraints to validate receiver_mode values
ALTER TABLE receiver_settings
    DROP CONSTRAINT IF EXISTS chk_receiver_settings_mode;
ALTER TABLE receiver_settings
    ADD CONSTRAINT chk_receiver_settings_mode
    CHECK (receiver_mode IN ('standard', 'kid'));

ALTER TABLE invite_tokens
    DROP CONSTRAINT IF EXISTS chk_invite_tokens_mode;
ALTER TABLE invite_tokens
    ADD CONSTRAINT chk_invite_tokens_mode
    CHECK (receiver_mode IN ('standard', 'kid'));

COMMIT;
