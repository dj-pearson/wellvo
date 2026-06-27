-- =============================================================================
-- Migration: 00048_live_activity_push_tokens
-- Story: US-IOS127 — remotely end the escalation Live Activity when an
--        escalation resolves server-side, even if the owner's app is closed.
--
-- The owner's escalation Live Activity (EscalationLiveActivity) currently only
-- starts/updates/ends when the dashboard reloads (EscalationActivityManager.sync).
-- So when a receiver checks in — or the owner stands down — while the owner's app
-- is closed, the Lock Screen keeps showing an "Overdue" running timer until the
-- owner next opens the app. That is the most anxiety-inducing surface showing a
-- stale, already-resolved alarm.
--
-- This adds the storage needed to end that activity via an APNs `liveactivity`
-- push: each running activity vends an ActivityKit push token, which the owner's
-- app mirrors here keyed by (owner, receiver, family). The escalation-resolve
-- paths (process-checkin-response, cancel-escalation) then send an `end` push to
-- those tokens.
--
-- Two token kinds are stored, distinguished by `token_type`:
--   * 'update' — a per-activity push token (ActivityKit `activity.pushTokenUpdates`).
--                Tied to a specific receiver+family; targeted by the resolve path
--                to end/update that activity. iOS 16.2+.
--   * 'start'  — a push-to-start token (`Activity.pushToStartTokenUpdates`,
--                iOS 17.2+). Owner-scoped (receiver_id/family_id NULL); stored now
--                so a later release can server-initiate an activity without an app
--                change. Not consumed by this release.
--
-- BACKWARD-COMPATIBLE (CLAUDE.md §A — "Always safe"):
--   * New table only. No change to push_tokens or its `platform` contract
--     (CLAUDE.md §D): Live Activity tokens are a distinct, per-activity, expiring
--     token kind and deliberately do NOT reuse push_tokens.
--   * Additive, so it is safe to deploy ahead of the client build that writes to
--     it (older clients simply never register, and the resolve path no-ops when no
--     rows exist).
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS live_activity_push_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- The owner whose device renders the Live Activity (and authenticates the
    -- registration). Always set.
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- The receiver the activity tracks. NULL for owner-scoped 'start' tokens.
    receiver_id UUID REFERENCES users(id) ON DELETE CASCADE,
    -- The family context. NULL for owner-scoped 'start' tokens.
    family_id UUID REFERENCES families(id) ON DELETE CASCADE,
    -- The ActivityKit push token, hex-encoded (as APNs expects in the device path).
    push_token TEXT NOT NULL,
    -- 'update' = per-activity token; 'start' = push-to-start token.
    token_type TEXT NOT NULL DEFAULT 'update',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- A push token is globally unique to one activity (or one push-to-start
    -- registration), so re-registration upserts on the token.
    UNIQUE (push_token),
    -- 'update' tokens must be tied to a receiver+family; 'start' tokens must not.
    CONSTRAINT live_activity_token_scope CHECK (
        (token_type = 'update' AND receiver_id IS NOT NULL AND family_id IS NOT NULL)
        OR (token_type = 'start' AND receiver_id IS NULL AND family_id IS NULL)
    )
);

-- The resolve path looks up active 'update' tokens for a (family, receiver).
CREATE INDEX IF NOT EXISTS idx_live_activity_tokens_family_receiver
    ON live_activity_push_tokens (family_id, receiver_id)
    WHERE is_active = TRUE AND token_type = 'update';

CREATE INDEX IF NOT EXISTS idx_live_activity_tokens_owner
    ON live_activity_push_tokens (owner_id);

-- Keep updated_at fresh on upsert (reuses the shared trigger fn from 00001).
DROP TRIGGER IF EXISTS live_activity_push_tokens_updated_at ON live_activity_push_tokens;
CREATE TRIGGER live_activity_push_tokens_updated_at
    BEFORE UPDATE ON live_activity_push_tokens
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS: an owner manages only their own rows. The service role (used by the
-- edge functions to read tokens and deactivate stale ones) bypasses RLS.
ALTER TABLE live_activity_push_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Owners can manage own live activity tokens"
    ON live_activity_push_tokens FOR ALL
    USING (owner_id = auth.uid())
    WITH CHECK (owner_id = auth.uid());

COMMIT;
