-- Wellvo Phase 3: Delivery Confirmation, Location Safety, Enhanced Responses
-- Migration: 00012_delivery_confirmation_location_safety
-- Features:
--   1. Push notification delivery confirmation with retry tracking
--   2. Optional location/distance tracking for receiver safety (dementia care)
--   3. Last-seen heartbeat for app activity monitoring
--   4. Enhanced check-in responses (need help, call me)
--   5. Battery level reporting

BEGIN;

-- =============================================================================
-- 1. DELIVERY CONFIRMATION & RETRY TRACKING
-- =============================================================================

-- Add delivery tracking columns to notification_log
ALTER TABLE notification_log
    ADD COLUMN IF NOT EXISTS delivery_confirmed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS apns_id TEXT,
    ADD COLUMN IF NOT EXISTS retry_count INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS max_retries INT NOT NULL DEFAULT 3,
    ADD COLUMN IF NOT EXISTS next_retry_at TIMESTAMPTZ;

-- Index for finding notifications that need retry
CREATE INDEX IF NOT EXISTS idx_notification_log_retry
    ON notification_log(next_retry_at)
    WHERE status = 'sent' AND delivery_confirmed_at IS NULL AND retry_count < max_retries;

-- =============================================================================
-- 2. LOCATION / DISTANCE TRACKING
-- =============================================================================

-- Add location fields to receiver_settings (owner configures these)
ALTER TABLE receiver_settings
    ADD COLUMN IF NOT EXISTS location_tracking_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS home_latitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS home_longitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS geofence_radius_meters INT NOT NULL DEFAULT 500,
    ADD COLUMN IF NOT EXISTS location_alert_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Add location data to check-ins (submitted by receiver at check-in time)
ALTER TABLE checkins
    ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS location_accuracy_meters DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS distance_from_home_meters DOUBLE PRECISION;

-- Location updates table for periodic background location reporting
CREATE TABLE IF NOT EXISTS location_updates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy_meters DOUBLE PRECISION,
    distance_from_home_meters DOUBLE PRECISION,
    battery_level DOUBLE PRECISION,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_location_updates_receiver ON location_updates(receiver_id, recorded_at DESC);
CREATE INDEX idx_location_updates_family ON location_updates(family_id, recorded_at DESC);

-- Auto-expire old location data (privacy: keep only 7 days)
CREATE OR REPLACE FUNCTION cleanup_old_location_data()
RETURNS void AS $$
BEGIN
    DELETE FROM location_updates
    WHERE recorded_at < NOW() - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

SELECT cron.schedule(
    'cleanup-location-data',
    '0 3 * * *',
    $$SELECT cleanup_old_location_data()$$
);

-- =============================================================================
-- 3. LAST-SEEN HEARTBEAT
-- =============================================================================

-- Add heartbeat tracking to users table
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_battery_level DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS last_app_version TEXT;

-- =============================================================================
-- 4. ENHANCED CHECK-IN RESPONSES
-- =============================================================================

-- Extend checkin_source to support new response types
ALTER TYPE checkin_source ADD VALUE IF NOT EXISTS 'need_help';
ALTER TYPE checkin_source ADD VALUE IF NOT EXISTS 'call_me';

-- Add urgency field to check-ins for enhanced responses
ALTER TABLE checkins
    ADD COLUMN IF NOT EXISTS response_type TEXT NOT NULL DEFAULT 'ok';
-- response_type: 'ok', 'need_help', 'call_me'

-- Add alert types for enhanced responses
-- (alerts table already exists from migration 00006)

-- =============================================================================
-- 5. DELIVERY RETRY FUNCTION
-- Runs every 2 minutes to retry unconfirmed notifications
-- =============================================================================

CREATE OR REPLACE FUNCTION retry_undelivered_notifications()
RETURNS void AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT
            nl.id AS log_id,
            nl.user_id,
            nl.checkin_request_id,
            nl.type,
            nl.retry_count,
            cr.family_id,
            cr.receiver_id
        FROM notification_log nl
        LEFT JOIN checkin_requests cr ON cr.id = nl.checkin_request_id
        WHERE nl.status = 'sent'
          AND nl.delivery_confirmed_at IS NULL
          AND nl.next_retry_at IS NOT NULL
          AND nl.next_retry_at <= NOW()
          AND nl.retry_count < nl.max_retries
          -- Only retry notifications from the last 2 hours
          AND nl.sent_at > NOW() - INTERVAL '2 hours'
    LOOP
        -- Update retry count and next retry time (exponential backoff: 2, 4, 8 min)
        UPDATE notification_log
        SET retry_count = rec.retry_count + 1,
            next_retry_at = NOW() + ((2 * POWER(2, rec.retry_count)) || ' minutes')::interval
        WHERE id = rec.log_id;

        -- Re-trigger the push notification via edge function
        IF rec.checkin_request_id IS NOT NULL AND rec.family_id IS NOT NULL THEN
            PERFORM net.http_post(
                url := current_setting('app.edge_functions_url') || '/send-checkin-notification',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'Authorization', 'Bearer ' || current_setting('app.service_role_key')
                ),
                body := jsonb_build_object(
                    'receiver_id', rec.user_id,
                    'family_id', rec.family_id,
                    'type', 'scheduled',
                    'is_retry', true,
                    'notification_log_id', rec.log_id
                )
            );
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

SELECT cron.schedule(
    'retry-undelivered-notifications',
    '*/2 * * * *',
    $$SELECT retry_undelivered_notifications()$$
);

-- =============================================================================
-- 6. GEOFENCE ALERT DETECTION
-- Runs every 5 minutes to check if any receiver has left their safe zone
-- =============================================================================

CREATE OR REPLACE FUNCTION check_geofence_alerts()
RETURNS void AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT
            lu.receiver_id,
            lu.family_id,
            lu.latitude,
            lu.longitude,
            lu.distance_from_home_meters,
            rs.geofence_radius_meters,
            u.display_name
        FROM location_updates lu
        JOIN family_members fm ON fm.user_id = lu.receiver_id AND fm.family_id = lu.family_id
        JOIN receiver_settings rs ON rs.family_member_id = fm.id
        JOIN users u ON u.id = lu.receiver_id
        WHERE rs.location_tracking_enabled = TRUE
          AND rs.location_alert_enabled = TRUE
          AND rs.home_latitude IS NOT NULL
          AND rs.home_longitude IS NOT NULL
          AND lu.distance_from_home_meters IS NOT NULL
          AND lu.distance_from_home_meters > rs.geofence_radius_meters
          -- Only look at recent updates (last 10 minutes)
          AND lu.recorded_at > NOW() - INTERVAL '10 minutes'
          -- Don't duplicate alerts within 1 hour
          AND NOT EXISTS (
              SELECT 1 FROM alerts a
              WHERE a.receiver_id = lu.receiver_id
                AND a.family_id = lu.family_id
                AND a.type = 'geofence_breach'
                AND a.created_at > NOW() - INTERVAL '1 hour'
          )
        ORDER BY lu.recorded_at DESC
    LOOP
        INSERT INTO alerts (family_id, receiver_id, type, title, message, data)
        VALUES (
            rec.family_id,
            rec.receiver_id,
            'geofence_breach',
            'Location Alert',
            rec.display_name || ' may have left their safe zone (' ||
                ROUND(rec.distance_from_home_meters::numeric) || 'm from home).',
            jsonb_build_object(
                'latitude', rec.latitude,
                'longitude', rec.longitude,
                'distance_meters', rec.distance_from_home_meters,
                'geofence_radius', rec.geofence_radius_meters
            )
        );

        -- Also trigger push to owner
        PERFORM net.http_post(
            url := current_setting('app.edge_functions_url') || '/escalation-tick',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || current_setting('app.service_role_key')
            ),
            body := jsonb_build_object(
                'type', 'geofence_alert',
                'receiver_id', rec.receiver_id,
                'family_id', rec.family_id,
                'distance_meters', rec.distance_from_home_meters,
                'display_name', rec.display_name
            )
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

SELECT cron.schedule(
    'check-geofence-alerts',
    '*/5 * * * *',
    $$SELECT check_geofence_alerts()$$
);

-- =============================================================================
-- RLS POLICIES FOR NEW TABLE
-- =============================================================================

ALTER TABLE location_updates ENABLE ROW LEVEL SECURITY;

-- Receivers can insert their own location
CREATE POLICY "Receivers can insert own location"
    ON location_updates FOR INSERT
    WITH CHECK (receiver_id = auth.uid());

-- Owners can read location updates for their family
CREATE POLICY "Owners can read family location updates"
    ON location_updates FOR SELECT
    USING (
        family_id IN (
            SELECT id FROM families WHERE owner_id = auth.uid()
        )
    );

-- Viewers can read location updates for their family
CREATE POLICY "Viewers can read family location updates"
    ON location_updates FOR SELECT
    USING (
        family_id IN (
            SELECT family_id FROM family_members
            WHERE user_id = auth.uid() AND role = 'viewer' AND status = 'active'
        )
    );

-- Receivers can read their own location updates
CREATE POLICY "Receivers can read own location updates"
    ON location_updates FOR SELECT
    USING (receiver_id = auth.uid());

COMMIT;
