-- =============================================================================
-- Migration: 00046_checkin_source_surfaces
-- Story: US-IOS107 — attribute out-of-process check-ins to their real surface
--
-- The interactive Home/Lock widget, the iOS 18 Control Center control, and Siri
-- / Shortcuts all run the same CheckInIntent, which recorded source = 'app' for
-- every one of them — so analytics couldn't tell a widget tap from a Siri
-- phrase. The client now sends 'widget' / 'control' / 'siri', but `checkins.source`
-- is the `checkin_source` ENUM, so those values must exist first or the INSERT
-- fails.
--
-- Backward-compatible per CLAUDE.md §A: adding ENUM values *at the end* is an
-- always-safe single-release change. Existing clients keep sending the old
-- values; the iOS `CheckInSource` decoder is forgiving (unknown -> .app), so an
-- older build reading a 'widget' row decodes cleanly.
-- =============================================================================

BEGIN;

ALTER TYPE checkin_source ADD VALUE IF NOT EXISTS 'widget';
ALTER TYPE checkin_source ADD VALUE IF NOT EXISTS 'control';
ALTER TYPE checkin_source ADD VALUE IF NOT EXISTS 'siri';

COMMIT;
