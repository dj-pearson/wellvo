-- Daily OK: senior "Simple Mode" + audible confirmation (US-IOS011 / US-IOS012)
-- Migration: 00038_receiver_simple_mode
--
-- Adds two per-receiver, owner-controlled preferences:
--   * simple_mode — an extra-large, low-clutter, emoji-free check-in screen for
--     senior receivers.
--   * audio_confirmation_enabled — speak/chime a confirmation on a successful
--     check-in for low-vision receivers.
--
-- Backward compatibility: additive only. Both columns are nullable-safe with a
-- default of FALSE, so existing clients that don't know these fields keep
-- working unchanged (the iOS model decodes missing keys as false).

BEGIN;

ALTER TABLE receiver_settings
    ADD COLUMN IF NOT EXISTS simple_mode BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE receiver_settings
    ADD COLUMN IF NOT EXISTS audio_confirmation_enabled BOOLEAN NOT NULL DEFAULT FALSE;

COMMIT;
