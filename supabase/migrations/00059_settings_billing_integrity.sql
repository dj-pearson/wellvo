-- Daily OK: Settings tab — billing that follows the payer, schedules that come
-- back after a resubscribe, and nightly jobs one bad row can't break.
-- Migration: 00059_settings_billing_integrity
--
-- ─── WHAT AND WHY ────────────────────────────────────────────────────────────
-- 1. Billing columns on families (all NULLable, server-written only):
--      billing_user_id                  who pays for this family's plan
--      billing_original_transaction_id  which store subscription pays for it
--      billing_platform                 'ios' | 'android'
--      billing_verified_at              last time Apple's signature checked out
--    /subscription-webhook matched families by owner_id, so after an ownership
--    transfer the ex-owner's renewals 404'd, the family lapsed and its
--    receivers were switched off. The webhook now matches the payer first.
--    Paid families are backfilled with billing_user_id = owner_id.
--
-- 2. subscription_receipts (new table, service role only): binds one verified
--    App Store subscription (original transaction id) to one account, so one
--    purchase can't provision any number of accounts; audit trail for support.
--
-- 3. receiver_settings.billing_paused_at (NULLable): the expiry job used to set
--    is_active = FALSE with no record of why, and nothing ever set it back, so
--    resubscribing restored the plan but never the check-ins. The job now
--    stamps billing_paused_at, and resume_billing_paused_schedules() (called
--    by the webhook / App Store notifications) turns exactly those rows back on.
--
-- 4. enforce_subscription_grace_period(): also moves 'cancelled' families on.
--    Dispatch only runs for 'active'/'grace_period', and nothing ever moved a
--    'cancelled' family, so a cancellation stopped check-ins on the day it was
--    made, with paid time left, and forever. Existing cancelled families with
--    time left go back to 'active' (the job lapses them at expiry).
--
-- 5. data_retention_days is clamped to 30–3650 on client writes, and the
--    nightly job clamps it too. An owner could PATCH 3000000 (the job's single
--    DELETE then raised "timestamp out of range" every night, for every family)
--    or a negative number (deleted their whole family's history).
--
-- 6. dispatch_caregiver_digests(): one unknown users.timezone raised and
--    aborted the whole loop, so no owner after that row got a summary.
--    Now an invalid zone falls back to UTC and each row is isolated.
--
-- 7. export_user_data(): it has never worked. Since 00010 it read
--    invite_tokens.created_by, a column that doesn't exist; plpgsql only
--    resolves that when the function runs, so every "Export My Data" failed
--    (the app showed a raw "Network error: column it.created_by does not
--    exist"). Fixed, and adds 'families_owned' (the family rows the user
--    owns: name, plan, retention). Same keys otherwise; the apps only share
--    the JSON.
--
-- ─── BACKWARD COMPATIBILITY (CLAUDE.md §A) ───────────────────────────────────
-- New table, new NULLable columns, a new RPC (service role only), and
-- CREATE OR REPLACE of existing functions with unchanged signatures. No RLS
-- policy is tightened. Client writes that shipped builds perform still pass:
-- iOS/Android only ever write data_retention_days as 90/180/365/730 (inside
-- the clamp); nothing on a client writes the billing columns (a client write
-- to them is silently kept at the server's value, like the 00051 columns).
-- Idempotent: safe to replay.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- =============================================================================
-- 1. Billing columns
-- =============================================================================
ALTER TABLE families ADD COLUMN IF NOT EXISTS billing_user_id UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE families ADD COLUMN IF NOT EXISTS billing_original_transaction_id TEXT;
ALTER TABLE families ADD COLUMN IF NOT EXISTS billing_platform TEXT;
ALTER TABLE families ADD COLUMN IF NOT EXISTS billing_verified_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_families_billing_user_id ON families(billing_user_id) WHERE billing_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_families_billing_original_tx ON families(billing_original_transaction_id)
    WHERE billing_original_transaction_id IS NOT NULL;

UPDATE families
SET billing_user_id = owner_id
WHERE billing_user_id IS NULL
  AND subscription_tier <> 'free';

-- Same body as 00051 plus the billing columns and the retention clamp.
CREATE OR REPLACE FUNCTION guard_families_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- A new family always starts on the base allowance; the subscription
        -- webhook (service_role) upgrades it once a purchase is verified.
        NEW.subscription_tier := 'free';
        NEW.subscription_status := 'active';
        NEW.subscription_expires_at := NULL;
        NEW.free_tier_expires_at := NULL;
        NEW.max_receivers := 1;
        NEW.max_viewers := 0;
        NEW.billing_user_id := NULL;
        NEW.billing_original_transaction_id := NULL;
        NEW.billing_platform := NULL;
        NEW.billing_verified_at := NULL;
    ELSE
        NEW.id := OLD.id;
        -- Ownership moves only through transfer_family_ownership() (00045).
        -- Raise rather than silently keep: the RLS WITH CHECK already rejected
        -- this write, and a quiet no-op would tell the caller it had worked.
        IF NEW.owner_id IS DISTINCT FROM OLD.owner_id THEN
            RAISE EXCEPTION 'Use transfer_family_ownership to change the owner'
                USING ERRCODE = 'insufficient_privilege';
        END IF;
        NEW.subscription_tier := OLD.subscription_tier;
        NEW.subscription_status := OLD.subscription_status;
        NEW.subscription_expires_at := OLD.subscription_expires_at;
        NEW.free_tier_expires_at := OLD.free_tier_expires_at;
        NEW.max_receivers := OLD.max_receivers;
        NEW.max_viewers := OLD.max_viewers;
        NEW.billing_user_id := OLD.billing_user_id;
        NEW.billing_original_transaction_id := OLD.billing_original_transaction_id;
        NEW.billing_platform := OLD.billing_platform;
        NEW.billing_verified_at := OLD.billing_verified_at;
    END IF;

    -- Retention: silently keep it in a sane range (shipped apps only send
    -- 90–730, so nothing they do changes).
    IF NEW.data_retention_days IS NULL THEN
        NEW.data_retention_days := 365;
    ELSIF NEW.data_retention_days < 30 THEN
        NEW.data_retention_days := 30;
    ELSIF NEW.data_retention_days > 3650 THEN
        NEW.data_retention_days := 3650;
    END IF;
    RETURN NEW;
END;
$$;

-- =============================================================================
-- 2. subscription_receipts
-- =============================================================================
CREATE TABLE IF NOT EXISTS subscription_receipts (
    original_transaction_id TEXT PRIMARY KEY,
    platform TEXT NOT NULL DEFAULT 'ios',
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_id UUID REFERENCES families(id) ON DELETE SET NULL,
    product_id TEXT,
    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    environment TEXT,
    last_transaction_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_subscription_receipts_user ON subscription_receipts(user_id);

-- Service role only: RLS on, no policies, and no grants to app roles.
ALTER TABLE subscription_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON subscription_receipts FROM PUBLIC, anon, authenticated;
GRANT ALL ON subscription_receipts TO service_role;

-- =============================================================================
-- 3. Schedules paused by billing, and turning them back on
-- =============================================================================
ALTER TABLE receiver_settings ADD COLUMN IF NOT EXISTS billing_paused_at TIMESTAMPTZ;

-- Rows the old job already switched off in families that are expired now.
UPDATE receiver_settings rs
SET billing_paused_at = NOW()
FROM family_members fm
JOIN families f ON f.id = fm.family_id
WHERE rs.family_member_id = fm.id
  AND f.subscription_status = 'expired'
  AND rs.is_active = FALSE
  AND rs.billing_paused_at IS NULL;

CREATE OR REPLACE FUNCTION resume_billing_paused_schedules(p_family_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE receiver_settings rs
    SET is_active = TRUE,
        billing_paused_at = NULL
    FROM family_members fm
    JOIN families f ON f.id = fm.family_id
    WHERE rs.family_member_id = fm.id
      AND fm.family_id = p_family_id
      AND fm.role = 'receiver'
      AND fm.status = 'active'
      AND f.subscription_status IN ('active', 'grace_period')
      AND rs.billing_paused_at IS NOT NULL;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION resume_billing_paused_schedules(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION resume_billing_paused_schedules(UUID) TO service_role;

-- =============================================================================
-- 4. Grace-period job: cancelled families lapse like any other
-- =============================================================================
-- A cancelled family with paid time left is covered until then.
UPDATE families
SET subscription_status = 'active'
WHERE subscription_status = 'cancelled'
  AND subscription_expires_at IS NOT NULL
  AND subscription_expires_at > NOW();

CREATE OR REPLACE FUNCTION enforce_subscription_grace_period()
RETURNS void AS $$
BEGIN
    -- Move from grace_period to expired after 7 days
    UPDATE families
    SET subscription_status = 'expired'
    WHERE subscription_status = 'grace_period'
      AND subscription_expires_at IS NOT NULL
      AND subscription_expires_at + INTERVAL '7 days' < NOW();

    -- Pause receiver schedules for expired families, remembering why so a
    -- resubscribe can turn exactly these back on (resume_billing_paused_schedules).
    UPDATE receiver_settings rs
    SET is_active = FALSE,
        billing_paused_at = COALESCE(rs.billing_paused_at, NOW())
    FROM family_members fm
    JOIN families f ON f.id = fm.family_id
    WHERE rs.family_member_id = fm.id
      AND f.subscription_status = 'expired'
      AND rs.is_active = TRUE;

    -- Move active (and cancelled) subscriptions past their expiry date to
    -- grace_period. A cancelled family with no expiry recorded starts its
    -- week now.
    UPDATE families
    SET subscription_status = 'grace_period',
        subscription_expires_at = COALESCE(subscription_expires_at, NOW())
    WHERE (
            (subscription_status = 'active'
             AND subscription_tier != 'free'
             AND subscription_expires_at IS NOT NULL
             AND subscription_expires_at < NOW())
         OR (subscription_status = 'cancelled'
             AND (subscription_expires_at IS NULL OR subscription_expires_at < NOW()))
          );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- =============================================================================
-- 5. Retention: bounded values, and a job one row can't break
-- =============================================================================
UPDATE families
SET data_retention_days = 365
WHERE data_retention_days < 30 OR data_retention_days > 3650;

-- Same body as 00058 except the clamp.
CREATE OR REPLACE FUNCTION enforce_data_retention()
RETURNS void AS $$
BEGIN
    -- Delete check-ins older than retention period per family
    DELETE FROM checkins c
    USING families f
    WHERE c.family_id = f.id
      AND c.checked_in_at < NOW() - make_interval(days => LEAST(GREATEST(COALESCE(f.data_retention_days, 365), 30), 3650));

    -- Delete old notification logs (90 days regardless)
    DELETE FROM notification_log
    WHERE sent_at < NOW() - INTERVAL '90 days';

    -- Delete unused invite tokens 30 days after they expired, so the owner
    -- can still see "Invite expired — hasn't joined" in the meantime.
    DELETE FROM invite_tokens
    WHERE expires_at < NOW() - INTERVAL '30 days' AND used_by IS NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- 6. Caregiver digests: a bad timezone skips to UTC, a failing row is isolated
-- =============================================================================
CREATE OR REPLACE FUNCTION dispatch_caregiver_digests()
RETURNS void AS $$
DECLARE
    rec RECORD;
    v_tz TEXT;
    local_now TIMESTAMP;
BEGIN
    FOR rec IN
        SELECT
            u.id AS owner_id,
            u.timezone,
            u.digest_frequency,
            u.digest_hour,
            u.digest_last_sent_at
        FROM users u
        -- Only real owners (own at least one family).
        WHERE u.digest_frequency IN ('daily', 'weekly')
          AND EXISTS (SELECT 1 FROM families f WHERE f.owner_id = u.id)
    LOOP
        BEGIN
            v_tz := CASE WHEN is_valid_timezone(rec.timezone) THEN rec.timezone ELSE 'UTC' END;

            -- Current wall-clock time in the owner's timezone.
            local_now := (NOW() AT TIME ZONE v_tz);

            -- Wrong hour for this owner — skip.
            CONTINUE WHEN EXTRACT(HOUR FROM local_now)::int <> rec.digest_hour;

            -- Weekly digests only on Monday (ISO dow = 1).
            CONTINUE WHEN rec.digest_frequency = 'weekly'
                      AND EXTRACT(ISODOW FROM local_now)::int <> 1;

            -- Already sent today (local) — idempotent against multiple cron ticks.
            CONTINUE WHEN rec.digest_last_sent_at IS NOT NULL
                      AND (rec.digest_last_sent_at AT TIME ZONE v_tz)::date
                          = local_now::date;

            -- Fire-and-forget the digest push via the edge function.
            PERFORM net.http_post(
                url := current_setting('app.edge_functions_url') || '/send-digest',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'Authorization', 'Bearer ' || current_setting('app.service_role_key')
                ),
                body := jsonb_build_object('owner_id', rec.owner_id)
            );

            -- Mark as sent so we don't re-fire within the same local day.
            UPDATE users SET digest_last_sent_at = NOW() WHERE id = rec.owner_id;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'dispatch_caregiver_digests: owner % skipped: %', rec.owner_id, SQLERRM;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- 7. Export: the family rows the user owns
-- =============================================================================
-- Same body as 00049 plus 'families_owned'.
CREATE OR REPLACE FUNCTION export_user_data(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    IF auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT jsonb_build_object(
        'user', (SELECT row_to_json(u) FROM users u WHERE u.id = p_user_id),
        'families_owned', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', f.id,
                'name', f.name,
                'subscription_tier', f.subscription_tier,
                'subscription_status', f.subscription_status,
                'subscription_expires_at', f.subscription_expires_at,
                'max_receivers', f.max_receivers,
                'max_viewers', f.max_viewers,
                'data_retention_days', f.data_retention_days,
                'created_at', f.created_at
            )), '[]'::jsonb)
            FROM families f WHERE f.owner_id = p_user_id
        ),
        'family_memberships', (
            SELECT COALESCE(jsonb_agg(row_to_json(fm)), '[]'::jsonb)
            FROM family_members fm WHERE fm.user_id = p_user_id
        ),
        'checkins', (
            SELECT COALESCE(jsonb_agg(row_to_json(c)), '[]'::jsonb)
            FROM checkins c WHERE c.receiver_id = p_user_id
        ),
        'checkin_requests', (
            SELECT COALESCE(jsonb_agg(row_to_json(cr)), '[]'::jsonb)
            FROM checkin_requests cr
            WHERE cr.receiver_id = p_user_id OR cr.requested_by = p_user_id
        ),
        'notification_log', (
            SELECT COALESCE(jsonb_agg(row_to_json(nl)), '[]'::jsonb)
            FROM notification_log nl WHERE nl.user_id = p_user_id
        ),
        -- invite_tokens has no created_by column (never had one). Every
        -- earlier version of this function referenced it.created_by, which
        -- plpgsql only resolves when it runs — so Export My Data failed for
        -- every user with "column it.created_by does not exist". The invites
        -- that are the user's are the ones for families they own, and the one
        -- they joined with.
        'invite_tokens', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', it.id,
                'family_id', it.family_id,
                'token', '[REDACTED]',
                'role', it.role,
                'name', it.name,
                'used_by', it.used_by,
                'expires_at', it.expires_at,
                'created_at', it.created_at
            )), '[]'::jsonb)
            FROM invite_tokens it
            WHERE it.used_by = p_user_id
               OR it.family_id IN (SELECT f.id FROM families f WHERE f.owner_id = p_user_id)
        ),
        'alerts', (
            SELECT COALESCE(jsonb_agg(row_to_json(a)), '[]'::jsonb)
            FROM alerts a
            JOIN families f ON f.id = a.family_id
            WHERE f.owner_id = p_user_id
        ),
        'receiver_settings', (
            SELECT COALESCE(jsonb_agg(row_to_json(rs)), '[]'::jsonb)
            FROM receiver_settings rs
            WHERE rs.family_member_id IN (
                SELECT fm.id FROM family_members fm WHERE fm.user_id = p_user_id
            )
        ),
        'push_tokens', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', pt.id,
                'platform', pt.platform,
                'is_active', pt.is_active,
                'created_at', pt.created_at
            )), '[]'::jsonb)
            FROM push_tokens pt WHERE pt.user_id = p_user_id
        ),
        -- Location history (the subject's own coordinates; ~110 m coarsened).
        'location_updates', (
            SELECT COALESCE(jsonb_agg(row_to_json(lu)), '[]'::jsonb)
            FROM location_updates lu WHERE lu.receiver_id = p_user_id
        ),
        -- Care notes about the subject, and care notes the subject authored.
        'care_notes', (
            SELECT COALESCE(jsonb_agg(row_to_json(cn)), '[]'::jsonb)
            FROM care_notes cn
            WHERE cn.receiver_id = p_user_id OR cn.author_id = p_user_id
        ),
        -- Derived wellness signals (activity booleans, never raw health values).
        'wellness_signals', (
            SELECT COALESCE(jsonb_agg(row_to_json(ws)), '[]'::jsonb)
            FROM wellness_signals ws WHERE ws.receiver_id = p_user_id
        ),
        'exported_at', NOW()
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;

-- Verification:
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'families' AND column_name LIKE 'billing_%';          -- 4 rows
--   SELECT to_regclass('public.subscription_receipts');                        -- not null
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'receiver_settings' AND column_name = 'billing_paused_at'; -- 1 row
--   SELECT proname FROM pg_proc WHERE proname = 'resume_billing_paused_schedules'; -- 1 row
