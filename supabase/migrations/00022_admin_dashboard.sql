-- Daily OK Admin Dashboard
-- Migration: 00022_admin_dashboard
--
-- Adds:
--   * is_system_admin flag on users (system-wide admin, distinct from family role)
--   * is_system_admin() helper + admin-wide RLS read policies
--   * blog_posts table (WYSIWYG + AI-generated, public reads on published)
--   * social_posts table (webhook-to-Make workflow)
--   * admin_activity_log (audit trail)

BEGIN;

-- =============================================================================
-- SYSTEM ADMIN FLAG
-- =============================================================================

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS is_system_admin BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_users_system_admin
    ON users(id) WHERE is_system_admin = TRUE;

-- Helper: is the current auth.uid() a system admin?
-- SECURITY DEFINER so RLS on users table doesn't block the check.
CREATE OR REPLACE FUNCTION is_system_admin()
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM users
        WHERE id = auth.uid() AND is_system_admin = TRUE
    );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- =============================================================================
-- ADMIN READ POLICIES ON EXISTING TABLES
-- Admins get global read access for monitoring. Writes still go through
-- edge functions using the service role.
-- =============================================================================

CREATE POLICY "Admins can read all users"
    ON users FOR SELECT
    USING (is_system_admin());

CREATE POLICY "Admins can read all families"
    ON families FOR SELECT
    USING (is_system_admin());

CREATE POLICY "Admins can read all family members"
    ON family_members FOR SELECT
    USING (is_system_admin());

CREATE POLICY "Admins can read all checkins"
    ON checkins FOR SELECT
    USING (is_system_admin());

CREATE POLICY "Admins can read all checkin requests"
    ON checkin_requests FOR SELECT
    USING (is_system_admin());

CREATE POLICY "Admins can read all notifications"
    ON notification_log FOR SELECT
    USING (is_system_admin());

-- =============================================================================
-- BLOG POSTS
-- =============================================================================

CREATE TYPE blog_post_status AS ENUM ('draft', 'published', 'archived');

CREATE TABLE blog_posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    excerpt TEXT,
    content_html TEXT NOT NULL DEFAULT '',
    content_json JSONB,                    -- TipTap JSON doc (source of truth)
    featured_image_url TEXT,
    status blog_post_status NOT NULL DEFAULT 'draft',
    published_at TIMESTAMPTZ,
    author_id UUID REFERENCES users(id) ON DELETE SET NULL,

    -- SEO
    seo_title TEXT,
    seo_description TEXT,
    canonical_url TEXT,
    og_image_url TEXT,

    -- Taxonomy
    tags TEXT[] NOT NULL DEFAULT '{}',
    category TEXT,

    -- AI / pSEO
    ai_generated BOOLEAN NOT NULL DEFAULT FALSE,
    ai_meta JSONB,                         -- { provider, model, prompt, template_id, variables, tokens }

    -- Metrics (updated async)
    view_count INT NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_blog_posts_slug ON blog_posts(slug);
CREATE INDEX idx_blog_posts_status_published ON blog_posts(status, published_at DESC);
CREATE INDEX idx_blog_posts_author ON blog_posts(author_id);
CREATE INDEX idx_blog_posts_tags ON blog_posts USING GIN(tags);

CREATE TRIGGER blog_posts_updated_at
    BEFORE UPDATE ON blog_posts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE blog_posts ENABLE ROW LEVEL SECURITY;

-- Public can read published posts only
CREATE POLICY "Anyone can read published blog posts"
    ON blog_posts FOR SELECT
    USING (status = 'published' AND published_at <= NOW());

-- Admins can do anything
CREATE POLICY "Admins can manage blog posts"
    ON blog_posts FOR ALL
    USING (is_system_admin())
    WITH CHECK (is_system_admin());

-- pSEO templates: reusable prompt scaffolds for bulk generation
CREATE TABLE blog_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    system_prompt TEXT NOT NULL,           -- cached across generations
    user_prompt_template TEXT NOT NULL,    -- uses {{variables}}
    default_tags TEXT[] NOT NULL DEFAULT '{}',
    default_category TEXT,
    slug_template TEXT,                    -- e.g. "{{keyword}}-guide"
    title_template TEXT,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER blog_templates_updated_at
    BEFORE UPDATE ON blog_templates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE blog_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage blog templates"
    ON blog_templates FOR ALL
    USING (is_system_admin())
    WITH CHECK (is_system_admin());

-- =============================================================================
-- SOCIAL POSTS (webhook-to-Make workflow)
-- =============================================================================

CREATE TYPE social_post_status AS ENUM ('draft', 'scheduled', 'publishing', 'posted', 'failed');

CREATE TABLE social_posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content TEXT NOT NULL,
    platforms TEXT[] NOT NULL DEFAULT '{}',   -- e.g. {'twitter','linkedin','facebook','instagram'}
    status social_post_status NOT NULL DEFAULT 'draft',
    scheduled_at TIMESTAMPTZ,
    posted_at TIMESTAMPTZ,
    media_urls TEXT[] NOT NULL DEFAULT '{}',
    link_url TEXT,                            -- associated URL (e.g. blog post)

    -- Webhook exchange
    webhook_url TEXT,                         -- resolved at publish time from env
    webhook_response JSONB,                   -- Make scenario response
    webhook_error TEXT,

    -- Per-platform resulting URLs returned by Make (optional)
    post_urls JSONB,                          -- { "twitter": "https://x.com/...", ... }

    author_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_social_posts_status ON social_posts(status, scheduled_at);
CREATE INDEX idx_social_posts_author ON social_posts(author_id);

CREATE TRIGGER social_posts_updated_at
    BEFORE UPDATE ON social_posts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE social_posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage social posts"
    ON social_posts FOR ALL
    USING (is_system_admin())
    WITH CHECK (is_system_admin());

-- =============================================================================
-- ADMIN ACTIVITY LOG (audit trail)
-- =============================================================================

CREATE TABLE admin_activity_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    admin_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    action TEXT NOT NULL,                  -- e.g. 'blog.publish', 'user.view', 'social.publish'
    resource_type TEXT,                    -- e.g. 'blog_post', 'user', 'social_post'
    resource_id UUID,
    metadata JSONB,                        -- free-form context
    ip_address TEXT,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_admin_activity_admin ON admin_activity_log(admin_id, created_at DESC);
CREATE INDEX idx_admin_activity_resource ON admin_activity_log(resource_type, resource_id);
CREATE INDEX idx_admin_activity_action ON admin_activity_log(action, created_at DESC);

ALTER TABLE admin_activity_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can read admin activity log"
    ON admin_activity_log FOR SELECT
    USING (is_system_admin());

-- =============================================================================
-- DASHBOARD METRICS RPC
-- Aggregated read-only metrics for the admin overview page. SECURITY DEFINER
-- so it can read across tables; gated on is_system_admin().
-- =============================================================================

CREATE OR REPLACE FUNCTION admin_dashboard_metrics()
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    IF NOT is_system_admin() THEN
        RAISE EXCEPTION 'admin access required';
    END IF;

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

-- Daily time series for charts (last 30 days)
CREATE OR REPLACE FUNCTION admin_daily_timeseries(p_days INT DEFAULT 30)
RETURNS TABLE (
    day DATE,
    new_users BIGINT,
    new_families BIGINT,
    checkins BIGINT,
    missed BIGINT
) AS $$
BEGIN
    IF NOT is_system_admin() THEN
        RAISE EXCEPTION 'admin access required';
    END IF;

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

-- Allow authenticated users to invoke (function itself enforces is_system_admin)
GRANT EXECUTE ON FUNCTION admin_dashboard_metrics() TO authenticated;
GRANT EXECUTE ON FUNCTION admin_daily_timeseries(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION is_system_admin() TO authenticated;

COMMIT;
