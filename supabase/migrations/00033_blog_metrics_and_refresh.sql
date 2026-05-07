-- Daily OK Blog — Metrics, decay detection, refresh queue
-- Migration: 00033_blog_metrics_and_refresh
--
-- Closes the autonomous loop:
--   1. blog_post_metrics       — per-post per-day per-source performance rows.
--                                Populated by the /ingest-metrics webhook
--                                (Make.com pulls GA4 + Search Console and POSTs
--                                here daily). (US-BLOG-061)
--   2. blog_refresh_queue      — posts flagged for editorial refresh, with the
--                                reason and any AI-proposed changes. (US-BLOG-063)
--   3. blog_detect_content_decay() + nightly pg_cron — compares trailing 28d
--                                clicks against the prior 28d and queues posts
--                                whose performance has dropped substantially. (US-BLOG-021)

BEGIN;

-- =============================================================================
-- 1. blog_post_metrics
-- =============================================================================

CREATE TYPE blog_metrics_source AS ENUM (
    'search_console',  -- impressions, clicks, position, ctr from GSC
    'ga4',             -- sessions, engaged_sessions, conversions, avg_time_on_page from GA4
    'internal'         -- view_count from blog_posts (already on the row)
);

CREATE TABLE blog_post_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES blog_posts(id) ON DELETE CASCADE,
    metric_date DATE NOT NULL,
    source blog_metrics_source NOT NULL,

    -- Search Console fields
    impressions INT NOT NULL DEFAULT 0,
    clicks INT NOT NULL DEFAULT 0,
    avg_position NUMERIC(6, 2),  -- e.g., 8.34
    ctr NUMERIC(6, 4),           -- e.g., 0.0421

    -- GA4 fields
    sessions INT NOT NULL DEFAULT 0,
    engaged_sessions INT NOT NULL DEFAULT 0,
    conversions INT NOT NULL DEFAULT 0,
    avg_time_on_page_seconds NUMERIC(8, 2),

    -- Free-form payload from the ingest webhook (raw API response, custom dims)
    raw JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT blog_post_metrics_unique_day UNIQUE (post_id, metric_date, source)
);

CREATE INDEX idx_blog_post_metrics_post_date ON blog_post_metrics(post_id, metric_date DESC);
CREATE INDEX idx_blog_post_metrics_date_source ON blog_post_metrics(metric_date, source);
CREATE INDEX idx_blog_post_metrics_clicks ON blog_post_metrics(clicks DESC, metric_date DESC) WHERE source = 'search_console';

CREATE TRIGGER blog_post_metrics_updated_at
    BEFORE UPDATE ON blog_post_metrics
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE blog_post_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can read blog post metrics"
    ON blog_post_metrics FOR SELECT
    USING (is_system_admin());

-- Inserts/updates happen via service-role from the ingest webhook + cron jobs.
-- No client-side write policy is needed; service role bypasses RLS.

-- =============================================================================
-- 2. blog_refresh_queue
-- =============================================================================

CREATE TYPE blog_refresh_status AS ENUM (
    'queued',         -- decay detector or manual flag added it
    'in_progress',    -- AI agent is generating a proposal, or editor is working
    'proposed',       -- AI agent emitted a draft revision; awaiting editor review
    'done',           -- editor accepted the proposal (restored the revision) or made manual edits
    'dismissed'       -- editor decided no refresh needed
);

CREATE TYPE blog_refresh_reason AS ENUM (
    'decay',          -- traffic dropped vs prior period
    'serp_change',    -- competitor or SERP feature shift detected
    'stale_facts',    -- statistics or sources are out of date
    'manual',         -- editor flagged
    'periodic'        -- post crossed a configurable age threshold
);

CREATE TABLE blog_refresh_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES blog_posts(id) ON DELETE CASCADE,
    reason blog_refresh_reason NOT NULL,
    status blog_refresh_status NOT NULL DEFAULT 'queued',

    -- Free-form metadata from the source that flagged this row.
    -- Decay: { current_28d_clicks, prior_28d_clicks, drop_pct }
    -- SERP change: { url, change_summary }
    detection_meta JSONB,

    -- The AI-generated revision id (in blog_post_revisions) when the agent has
    -- produced a proposal. Editor restores from there to apply.
    proposal_revision_id UUID REFERENCES blog_post_revisions(id) ON DELETE SET NULL,
    -- Free-form summary of what the agent proposed (so the queue list is
    -- skim-able without fetching the full revision).
    proposal_summary TEXT,

    actioned_by UUID REFERENCES users(id) ON DELETE SET NULL,
    actioned_at TIMESTAMPTZ,
    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Don't queue the same post for the same reason twice while the prior
    -- entry is still open. This is a partial unique to allow re-queueing
    -- after a 'done' or 'dismissed' close.
    CONSTRAINT blog_refresh_queue_open_unique
        EXCLUDE (post_id WITH =, reason WITH =) WHERE (status IN ('queued', 'in_progress', 'proposed'))
);

CREATE INDEX idx_blog_refresh_queue_status ON blog_refresh_queue(status, created_at DESC);
CREATE INDEX idx_blog_refresh_queue_post ON blog_refresh_queue(post_id, created_at DESC);

CREATE TRIGGER blog_refresh_queue_updated_at
    BEFORE UPDATE ON blog_refresh_queue
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE blog_refresh_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage blog refresh queue"
    ON blog_refresh_queue FOR ALL
    USING (is_system_admin())
    WITH CHECK (is_system_admin());

-- =============================================================================
-- 3. blog_detect_content_decay() — nightly decay scan
-- =============================================================================
--
-- Definition of decay (kept simple by design — easier to reason about + tune):
--   * Post is published and ≥60 days old (so it's had time to mature).
--   * Prior 28-day click total is ≥ 20 (so dips on tiny posts don't trigger).
--   * Current 28-day clicks are ≤ 50% of prior 28-day clicks.
--
-- Inserts a row into blog_refresh_queue with reason='decay' and
-- detection_meta carrying the click numbers. The EXCLUDE constraint above
-- silently swallows duplicates if the same post is already queued for decay.

CREATE OR REPLACE FUNCTION blog_detect_content_decay()
RETURNS INT AS $$
DECLARE
    v_inserted INT := 0;
    rec RECORD;
BEGIN
    FOR rec IN
        WITH windows AS (
            SELECT
                bp.id AS post_id,
                COALESCE(SUM(CASE WHEN m.metric_date >= CURRENT_DATE - INTERVAL '28 days'
                                  THEN m.clicks ELSE 0 END), 0) AS clicks_28d,
                COALESCE(SUM(CASE WHEN m.metric_date <  CURRENT_DATE - INTERVAL '28 days'
                                  AND  m.metric_date >= CURRENT_DATE - INTERVAL '56 days'
                                  THEN m.clicks ELSE 0 END), 0) AS clicks_prior_28d
            FROM blog_posts bp
            LEFT JOIN blog_post_metrics m
                   ON m.post_id = bp.id
                  AND m.source = 'search_console'
            WHERE bp.status = 'published'
              AND bp.published_at <= NOW() - INTERVAL '60 days'
            GROUP BY bp.id
        )
        SELECT post_id, clicks_28d, clicks_prior_28d
        FROM windows
        WHERE clicks_prior_28d >= 20
          AND clicks_28d <= clicks_prior_28d * 0.5
    LOOP
        BEGIN
            INSERT INTO blog_refresh_queue (post_id, reason, status, detection_meta)
            VALUES (
                rec.post_id, 'decay', 'queued',
                jsonb_build_object(
                    'current_28d_clicks', rec.clicks_28d,
                    'prior_28d_clicks', rec.clicks_prior_28d,
                    'drop_pct', ROUND((1.0 - (rec.clicks_28d::NUMERIC / NULLIF(rec.clicks_prior_28d, 0))) * 100, 1),
                    'detected_at', NOW()
                )
            );
            v_inserted := v_inserted + 1;
        EXCEPTION
            -- EXCLUDE constraint will reject when an open queue entry exists
            -- for this (post_id, reason). That's expected — silently skip.
            WHEN exclusion_violation THEN NULL;
        END;
    END LOOP;
    RETURN v_inserted;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION blog_detect_content_decay() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION blog_detect_content_decay() TO service_role;

SELECT cron.schedule(
    'blog-detect-content-decay',
    '30 4 * * *',  -- 04:30 UTC, after the revision-cleanup job at 04:00
    $$SELECT blog_detect_content_decay()$$
);

COMMIT;

-- =============================================================================
-- Verification
-- =============================================================================

SELECT
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'blog_post_metrics')   AS metrics_table,
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'blog_refresh_queue')  AS queue_table,
    (SELECT COUNT(*) FROM pg_policies WHERE tablename = 'blog_post_metrics')                  AS metrics_rls,
    (SELECT COUNT(*) FROM pg_policies WHERE tablename = 'blog_refresh_queue')                 AS queue_rls,
    (SELECT COUNT(*) FROM pg_proc WHERE proname = 'blog_detect_content_decay')                AS detector_fn,
    (SELECT COUNT(*) FROM cron.job WHERE jobname = 'blog-detect-content-decay')               AS cron_job;
