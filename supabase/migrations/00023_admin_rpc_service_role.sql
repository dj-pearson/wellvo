-- Daily OK Admin Dashboard — RPC gate fix
-- Migration: 00023_admin_rpc_service_role
--
-- Bug: admin_dashboard_metrics() and admin_daily_timeseries() checked
-- is_system_admin() internally via auth.uid(). When the edge-functions service
-- calls them with the service role key, auth.uid() is NULL and the check
-- always fails. Edge functions already validate admin via requireSystemAdmin()
-- before calling these RPCs, so the internal gate is redundant and wrong.
--
-- Fix: drop the internal gate, revoke EXECUTE from authenticated (so direct
-- PostgREST calls from a browser JWT can't reach them). Only service_role
-- (edge functions) and postgres (DB superuser) can invoke.

BEGIN;

CREATE OR REPLACE FUNCTION admin_dashboard_metrics()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_users',            (SELECT COUNT(*) FROM users),
        'total_families',         (SELECT COUNT(*) FROM families),
        'total_members',          (SELECT COUNT(*) FROM family_members WHERE status = 'active'),
        'checkins_today',         (SELECT COUNT(*) FROM checkins WHERE checked_in_at >= date_trunc('day', NOW())),
        'checkins_7d',            (SELECT COUNT(*) FROM checkins WHERE checked_in_at >= NOW() - INTERVAL '7 days'),
        'new_users_7d',           (SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '7 days'),
        'new_users_30d',          (SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '30 days'),
        'active_subscriptions',   (SELECT COUNT(*) FROM families WHERE subscription_status = 'active' AND subscription_tier <> 'free'),
        'free_families',          (SELECT COUNT(*) FROM families WHERE subscription_tier = 'free'),
        'paid_families',          (SELECT COUNT(*) FROM families WHERE subscription_tier <> 'free'),
        'pending_requests',       (SELECT COUNT(*) FROM checkin_requests WHERE status = 'pending'),
        'missed_requests_7d',     (SELECT COUNT(*) FROM checkin_requests WHERE status = 'missed' AND created_at >= NOW() - INTERVAL '7 days'),
        'published_posts',        (SELECT COUNT(*) FROM blog_posts WHERE status = 'published'),
        'draft_posts',            (SELECT COUNT(*) FROM blog_posts WHERE status = 'draft'),
        'social_posts_scheduled', (SELECT COUNT(*) FROM social_posts WHERE status = 'scheduled'),
        'social_posts_posted_7d', (SELECT COUNT(*) FROM social_posts WHERE status = 'posted' AND posted_at >= NOW() - INTERVAL '7 days'),
        'generated_at',           NOW()
    ) INTO result;
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION admin_daily_timeseries(p_days INT DEFAULT 30)
RETURNS TABLE (
    day DATE,
    new_users BIGINT,
    new_families BIGINT,
    checkins BIGINT,
    missed BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH days AS (
        SELECT generate_series(
            date_trunc('day', NOW() - (p_days || ' days')::INTERVAL)::DATE,
            date_trunc('day', NOW())::DATE,
            '1 day'::INTERVAL
        )::DATE AS day
    )
    SELECT
        d.day,
        (SELECT COUNT(*) FROM users u WHERE u.created_at::DATE = d.day),
        (SELECT COUNT(*) FROM families f WHERE f.created_at::DATE = d.day),
        (SELECT COUNT(*) FROM checkins c WHERE c.checked_in_at::DATE = d.day),
        (SELECT COUNT(*) FROM checkin_requests r WHERE r.status = 'missed' AND r.created_at::DATE = d.day)
    FROM days d
    ORDER BY d.day;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Lock down to service_role + postgres (edge functions call with service role).
REVOKE EXECUTE ON FUNCTION admin_dashboard_metrics() FROM authenticated, anon, public;
REVOKE EXECUTE ON FUNCTION admin_daily_timeseries(INT) FROM authenticated, anon, public;
GRANT EXECUTE ON FUNCTION admin_dashboard_metrics() TO service_role;
GRANT EXECUTE ON FUNCTION admin_daily_timeseries(INT) TO service_role;

COMMIT;
