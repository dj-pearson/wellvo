-- Wellvo Phase 2: SMS Escalation Toggle and Pattern Alert Detection
-- Migration: 00006_sms_escalation_and_pattern_alerts

-- =============================================================================
-- SMS ESCALATION TOGGLE
-- Per-receiver setting to enable SMS fallback during escalation.
-- =============================================================================

ALTER TABLE receiver_settings
    ADD COLUMN IF NOT EXISTS sms_escalation_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- =============================================================================
-- PATTERN ALERTS
-- Detects when a receiver's check-in time drifts significantly from their
-- historical average. Runs daily and creates alerts for owners.
-- =============================================================================

-- Alerts table for pattern detection and other system alerts
CREATE TABLE IF NOT EXISTS alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL, -- 'time_drift', 'streak_broken', etc.
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    data JSONB DEFAULT '{}',
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_alerts_family ON alerts(family_id);
CREATE INDEX idx_alerts_unread ON alerts(family_id, is_read) WHERE is_read = FALSE;

-- Pattern detection function: flags when average check-in time shifts
-- by more than 2 hours compared to the 30-day baseline
CREATE OR REPLACE FUNCTION detect_checkin_time_drift()
RETURNS void AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT
            fm.user_id AS receiver_id,
            fm.family_id,
            u.display_name,
            -- Average check-in time over the last 7 days (recent)
            (
                SELECT AVG(EXTRACT(EPOCH FROM (c.checked_in_at AT TIME ZONE COALESCE(rs.timezone, 'America/New_York'))::time))
                FROM checkins c
                WHERE c.receiver_id = fm.user_id
                  AND c.family_id = fm.family_id
                  AND c.checked_in_at >= NOW() - INTERVAL '7 days'
            ) AS recent_avg_seconds,
            -- Average check-in time over the last 30 days (baseline)
            (
                SELECT AVG(EXTRACT(EPOCH FROM (c.checked_in_at AT TIME ZONE COALESCE(rs.timezone, 'America/New_York'))::time))
                FROM checkins c
                WHERE c.receiver_id = fm.user_id
                  AND c.family_id = fm.family_id
                  AND c.checked_in_at >= NOW() - INTERVAL '30 days'
                  AND c.checked_in_at < NOW() - INTERVAL '7 days'
            ) AS baseline_avg_seconds,
            -- Count recent check-ins (need at least 3 to detect drift)
            (
                SELECT COUNT(*)
                FROM checkins c
                WHERE c.receiver_id = fm.user_id
                  AND c.family_id = fm.family_id
                  AND c.checked_in_at >= NOW() - INTERVAL '7 days'
            ) AS recent_count
        FROM family_members fm
        JOIN users u ON u.id = fm.user_id
        LEFT JOIN receiver_settings rs ON rs.family_member_id = fm.id
        WHERE fm.role = 'receiver'
          AND fm.status = 'active'
    LOOP
        -- Skip if not enough data
        IF rec.recent_count < 3 OR rec.recent_avg_seconds IS NULL OR rec.baseline_avg_seconds IS NULL THEN
            CONTINUE;
        END IF;

        -- Check if drift exceeds 2 hours (7200 seconds)
        IF ABS(rec.recent_avg_seconds - rec.baseline_avg_seconds) > 7200 THEN
            -- Don't duplicate alerts — check if one was created in the last 7 days
            IF NOT EXISTS (
                SELECT 1 FROM alerts
                WHERE receiver_id = rec.receiver_id
                  AND family_id = rec.family_id
                  AND type = 'time_drift'
                  AND created_at >= NOW() - INTERVAL '7 days'
            ) THEN
                INSERT INTO alerts (family_id, receiver_id, type, title, message, data)
                VALUES (
                    rec.family_id,
                    rec.receiver_id,
                    'time_drift',
                    'Check-In Time Shift Detected',
                    rec.display_name || '''s check-in time has shifted significantly over the past week.',
                    jsonb_build_object(
                        'recent_avg_seconds', rec.recent_avg_seconds,
                        'baseline_avg_seconds', rec.baseline_avg_seconds,
                        'drift_hours', ROUND(ABS(rec.recent_avg_seconds - rec.baseline_avg_seconds) / 3600.0, 1)
                    )
                );
            END IF;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Run pattern detection daily at 11 PM
SELECT cron.schedule(
    'detect-checkin-time-drift',
    '0 23 * * *',
    $$SELECT detect_checkin_time_drift()$$
);

-- =============================================================================
-- RLS for alerts table
-- =============================================================================

ALTER TABLE alerts ENABLE ROW LEVEL SECURITY;

-- Owners can read alerts for their family
CREATE POLICY "Owners can read family alerts"
    ON alerts FOR SELECT
    USING (
        family_id IN (
            SELECT id FROM families WHERE owner_id = auth.uid()
        )
    );

-- Owners can mark alerts as read
CREATE POLICY "Owners can update family alerts"
    ON alerts FOR UPDATE
    USING (
        family_id IN (
            SELECT id FROM families WHERE owner_id = auth.uid()
        )
    );

-- Viewers can read alerts
CREATE POLICY "Viewers can read family alerts"
    ON alerts FOR SELECT
    USING (
        family_id IN (
            SELECT family_id FROM family_members
            WHERE user_id = auth.uid() AND role = 'viewer' AND status = 'active'
        )
    );
