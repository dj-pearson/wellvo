-- Daily OK: Caregiver daily / weekly digest
-- Migration: 00040_caregiver_digest
--
-- US-IOS014. Shifts owners from anxious checking to passive reassurance: an
-- opt-in daily or weekly summary push (consistency, check-ins X of Y, misses,
-- mood trend). Fully ADDITIVE per CLAUDE.md:
--   * New nullable/defaulted owner-preference columns on `users` (older clients
--     ignore them; default 'off' means nothing changes until a user opts in).
--   * A NEW pg_cron job + NEW edge function (/send-digest). No existing job or
--     function is modified.
--
-- Delivery time is the owner's local hour (users.timezone). Weekly digests go
-- out on Mondays. The cron runs hourly and posts to the edge function via
-- pg_net exactly like dispatch_scheduled_checkins / escalation_tick.

BEGIN;

-- 1. Owner digest preferences (per-owner).
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS digest_frequency TEXT NOT NULL DEFAULT 'off'
        CHECK (digest_frequency IN ('off', 'daily', 'weekly'));
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS digest_hour SMALLINT NOT NULL DEFAULT 8
        CHECK (digest_hour BETWEEN 0 AND 23);
-- Dedupe guard so a given local day only ever fires one digest.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS digest_last_sent_at TIMESTAMPTZ;

-- 2. Hourly dispatcher: find owners whose chosen local hour has arrived and
--    who are due (daily every day; weekly on Monday), then trigger /send-digest.
CREATE OR REPLACE FUNCTION dispatch_caregiver_digests()
RETURNS void AS $$
DECLARE
    rec RECORD;
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
        -- Current wall-clock time in the owner's timezone.
        local_now := (NOW() AT TIME ZONE rec.timezone);

        -- Wrong hour for this owner — skip.
        CONTINUE WHEN EXTRACT(HOUR FROM local_now)::int <> rec.digest_hour;

        -- Weekly digests only on Monday (ISO dow = 1).
        CONTINUE WHEN rec.digest_frequency = 'weekly'
                  AND EXTRACT(ISODOW FROM local_now)::int <> 1;

        -- Already sent today (local) — idempotent against multiple cron ticks.
        CONTINUE WHEN rec.digest_last_sent_at IS NOT NULL
                  AND (rec.digest_last_sent_at AT TIME ZONE rec.timezone)::date
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
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Schedule: run at the top of every hour.
SELECT cron.schedule(
    'dispatch-caregiver-digests',
    '0 * * * *',
    $$SELECT dispatch_caregiver_digests()$$
);

COMMIT;

-- Verification:
--   SELECT digest_frequency, digest_hour FROM users LIMIT 1;
--   SELECT jobname FROM cron.job WHERE jobname = 'dispatch-caregiver-digests';
