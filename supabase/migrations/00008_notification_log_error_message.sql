-- Wellvo: Add error_message column to notification_log
-- Migration: 00008_notification_log_error_message
--
-- Stores SMS/push delivery error details for debugging failed notifications.

BEGIN;

ALTER TABLE notification_log
    ADD COLUMN IF NOT EXISTS error_message TEXT;

COMMIT;
