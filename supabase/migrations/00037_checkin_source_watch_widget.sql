-- Daily OK: attribute check-ins from new surfaces (Apple Watch, widgets)
-- Migration: 00037_checkin_source_watch_widget
--
-- Adds two values to the checkin_source enum so check-ins initiated from the
-- Apple Watch app and the Home/Lock Screen widget (and the iOS 18 Control
-- Center control) can be recorded with their true origin instead of being
-- lumped in with 'app'.
--
-- Backward compatibility: additive only. Per CLAUDE.md, adding a new value at
-- the end of an enum is always safe — existing clients keep sending the values
-- they already know, and nothing reads these as required. The new app build
-- that emits 'watch' ships in the same release as this migration, and there are
-- no currently-shipped watch/widget clients, so there is no ordering risk.

BEGIN;

ALTER TYPE checkin_source ADD VALUE IF NOT EXISTS 'watch';
ALTER TYPE checkin_source ADD VALUE IF NOT EXISTS 'widget';

COMMIT;
