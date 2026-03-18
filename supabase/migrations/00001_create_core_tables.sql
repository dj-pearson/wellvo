-- Wellvo Core Schema
-- Migration: 00001_create_core_tables

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_cron";
CREATE EXTENSION IF NOT EXISTS "pg_net";

-- =============================================================================
-- ENUMS
-- =============================================================================

CREATE TYPE user_role AS ENUM ('owner', 'receiver', 'viewer');
CREATE TYPE member_status AS ENUM ('active', 'invited', 'deactivated');
CREATE TYPE subscription_tier AS ENUM ('free', 'family', 'family_plus');
CREATE TYPE subscription_status AS ENUM ('active', 'expired', 'grace_period', 'cancelled');
CREATE TYPE mood_type AS ENUM ('happy', 'neutral', 'tired');
CREATE TYPE checkin_source AS ENUM ('app', 'notification', 'on_demand');
CREATE TYPE checkin_request_status AS ENUM ('pending', 'checked_in', 'missed', 'expired');
CREATE TYPE checkin_request_type AS ENUM ('scheduled', 'on_demand');
CREATE TYPE notification_type AS ENUM ('checkin_reminder', 'escalation', 'owner_alert', 'viewer_alert');
CREATE TYPE notification_status AS ENUM ('sent', 'delivered', 'opened', 'failed');

-- =============================================================================
-- TABLES
-- =============================================================================

-- Users
CREATE TABLE users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    phone TEXT,
    display_name TEXT NOT NULL DEFAULT 'User',
    role user_role NOT NULL DEFAULT 'owner',
    avatar_url TEXT,
    timezone TEXT NOT NULL DEFAULT 'America/New_York',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_phone ON users(phone);

-- Families
CREATE TABLE families (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subscription_tier subscription_tier NOT NULL DEFAULT 'free',
    subscription_status subscription_status NOT NULL DEFAULT 'active',
    subscription_expires_at TIMESTAMPTZ,
    max_receivers INT NOT NULL DEFAULT 1,
    max_viewers INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_families_owner ON families(owner_id);

-- Family Members
CREATE TABLE family_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role user_role NOT NULL DEFAULT 'receiver',
    status member_status NOT NULL DEFAULT 'invited',
    invited_at TIMESTAMPTZ DEFAULT NOW(),
    joined_at TIMESTAMPTZ,
    UNIQUE(family_id, user_id)
);

CREATE INDEX idx_family_members_family ON family_members(family_id);
CREATE INDEX idx_family_members_user ON family_members(user_id);

-- Receiver Settings
CREATE TABLE receiver_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    family_member_id UUID NOT NULL REFERENCES family_members(id) ON DELETE CASCADE UNIQUE,
    checkin_time TIME NOT NULL DEFAULT '08:00',
    timezone TEXT NOT NULL DEFAULT 'America/New_York',
    grace_period_minutes INT NOT NULL DEFAULT 30,
    reminder_interval_minutes INT NOT NULL DEFAULT 30,
    escalation_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    quiet_hours_start TIME,
    quiet_hours_end TIME,
    mood_tracking_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX idx_receiver_settings_member ON receiver_settings(family_member_id);

-- Check-ins
CREATE TABLE checkins (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    checked_in_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    mood mood_type,
    source checkin_source NOT NULL DEFAULT 'app',
    scheduled_for TIMESTAMPTZ
);

CREATE INDEX idx_checkins_receiver ON checkins(receiver_id);
CREATE INDEX idx_checkins_family ON checkins(family_id);
CREATE INDEX idx_checkins_date ON checkins(checked_in_at DESC);
CREATE INDEX idx_checkins_receiver_family_date ON checkins(receiver_id, family_id, checked_in_at DESC);

-- Check-in Requests
CREATE TABLE checkin_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    requested_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type checkin_request_type NOT NULL DEFAULT 'scheduled',
    status checkin_request_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at TIMESTAMPTZ,
    escalation_step INT NOT NULL DEFAULT 0,
    next_escalation_at TIMESTAMPTZ
);

CREATE INDEX idx_checkin_requests_receiver ON checkin_requests(receiver_id);
CREATE INDEX idx_checkin_requests_status ON checkin_requests(status);
CREATE INDEX idx_checkin_requests_escalation ON checkin_requests(next_escalation_at) WHERE status = 'pending';

-- Push Tokens
CREATE TABLE push_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'ios',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, token)
);

CREATE INDEX idx_push_tokens_user ON push_tokens(user_id);

-- Notification Log
CREATE TABLE notification_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    checkin_request_id UUID REFERENCES checkin_requests(id) ON DELETE SET NULL,
    type notification_type NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at TIMESTAMPTZ,
    opened_at TIMESTAMPTZ,
    status notification_status NOT NULL DEFAULT 'sent'
);

CREATE INDEX idx_notification_log_user ON notification_log(user_id);
CREATE INDEX idx_notification_log_request ON notification_log(checkin_request_id);

-- Invite Tokens
CREATE TABLE invite_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    role user_role NOT NULL DEFAULT 'receiver',
    phone TEXT,
    name TEXT,
    checkin_time TIME,
    token TEXT NOT NULL UNIQUE,
    used_by UUID REFERENCES users(id),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_invite_tokens_token ON invite_tokens(token);

-- =============================================================================
-- AUTO-UPDATE TIMESTAMPS
-- =============================================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER push_tokens_updated_at
    BEFORE UPDATE ON push_tokens
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
