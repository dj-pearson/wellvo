-- Wellvo: Add missing database indexes for performance
-- Migration: 00009_add_missing_indexes
--
-- Indexes for frequently queried columns: subscription status,
-- active receiver settings, and invite token phone lookups.

BEGIN;

-- Subscription status queries (used by escalation-tick and dashboard)
CREATE INDEX IF NOT EXISTS idx_families_subscription
    ON families(subscription_status, subscription_expires_at);

-- Active receiver settings (used by send-checkin-notification dispatch)
CREATE INDEX IF NOT EXISTS idx_receiver_settings_active
    ON receiver_settings(is_active) WHERE is_active = true;

-- Invite token phone lookups (used by invite-receiver)
CREATE INDEX IF NOT EXISTS idx_invite_tokens_phone
    ON invite_tokens(phone);

-- Push token lookups by user and active status (used by all notification senders)
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_active
    ON push_tokens(user_id, is_active) WHERE is_active = true;

-- Checkin requests by status for escalation queries
CREATE INDEX IF NOT EXISTS idx_checkin_requests_pending
    ON checkin_requests(status, next_escalation_at) WHERE status = 'pending';

COMMIT;
