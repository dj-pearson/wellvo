-- Daily OK Blog — Post Revisions
-- Migration: 00030_blog_post_revisions
--
-- Adds version history for blog posts so every edit (manual or AI-driven)
-- snapshots the prior state. Foundation for safe auto-refresh agents and
-- editor-side undo / restore. (US-BLOG-009)
--
-- Design:
--   * blog_post_revisions stores a full snapshot of the row's editorial fields.
--   * snapshot_blog_post_revision() is the single entrypoint — admin edge
--     functions call it BEFORE applying an update; AI-driven flows
--     (auto-refresh in Phase 3) will call it from worker code.
--   * Initial revision is captured on INSERT via trigger so every post has at
--     least one row, including AI-generated articles published by the
--     /generate-next-article webhook.
--   * Append-only: no UPDATE or DELETE policies. Even admins cannot mutate
--     existing revisions. Cleanup happens via SECURITY DEFINER cron job.
--   * 90-day retention; cleanup keeps at minimum the 5 most recent revisions
--     per post regardless of age, so we never lose the "what did this used
--     to look like" trail for active posts.

BEGIN;

-- =============================================================================
-- TABLE
-- =============================================================================

CREATE TABLE blog_post_revisions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES blog_posts(id) ON DELETE CASCADE,
    editor_id UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Snapshot of the editorial fields at revision time. Mirrors blog_posts
    -- so a single SELECT is enough to render any historical version.
    title TEXT NOT NULL,
    slug TEXT NOT NULL,
    excerpt TEXT,
    content_html TEXT NOT NULL,
    content_json JSONB,
    featured_image_url TEXT,
    seo_title TEXT,
    seo_description TEXT,
    canonical_url TEXT,
    og_image_url TEXT,
    tags TEXT[] NOT NULL DEFAULT '{}',
    category TEXT,
    status blog_post_status NOT NULL,
    ai_meta JSONB,

    -- Revision metadata
    -- reason ∈ {'initial', 'manual_edit', 'ai_regenerate', 'auto_refresh', 'restore'}
    -- Free text so future flows can introduce new reasons without a migration.
    reason TEXT NOT NULL DEFAULT 'manual_edit',
    -- For 'restore' rows, points at the revision being restored back to.
    parent_revision_id UUID REFERENCES blog_post_revisions(id) ON DELETE SET NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_blog_post_revisions_post ON blog_post_revisions(post_id, created_at DESC);
CREATE INDEX idx_blog_post_revisions_editor ON blog_post_revisions(editor_id, created_at DESC);
CREATE INDEX idx_blog_post_revisions_reason ON blog_post_revisions(reason, created_at DESC);

ALTER TABLE blog_post_revisions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can read blog post revisions"
    ON blog_post_revisions FOR SELECT
    USING (is_system_admin());

CREATE POLICY "Admins can insert blog post revisions"
    ON blog_post_revisions FOR INSERT
    WITH CHECK (is_system_admin());

-- Append-only: deliberately no UPDATE or DELETE policy.
-- Cleanup runs via SECURITY DEFINER pg_cron job below, which bypasses RLS.

-- =============================================================================
-- snapshot_blog_post_revision() — single entrypoint for capturing a revision
-- =============================================================================

CREATE OR REPLACE FUNCTION snapshot_blog_post_revision(
    p_post_id UUID,
    p_editor_id UUID DEFAULT NULL,
    p_reason TEXT DEFAULT 'manual_edit',
    p_parent_revision_id UUID DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_revision_id UUID;
BEGIN
    INSERT INTO blog_post_revisions (
        post_id, editor_id,
        title, slug, excerpt,
        content_html, content_json, featured_image_url,
        seo_title, seo_description, canonical_url, og_image_url,
        tags, category, status, ai_meta,
        reason, parent_revision_id
    )
    SELECT
        p.id, p_editor_id,
        p.title, p.slug, p.excerpt,
        p.content_html, p.content_json, p.featured_image_url,
        p.seo_title, p.seo_description, p.canonical_url, p.og_image_url,
        p.tags, p.category, p.status, p.ai_meta,
        p_reason, p_parent_revision_id
    FROM blog_posts p
    WHERE p.id = p_post_id
    RETURNING id INTO v_revision_id;

    RETURN v_revision_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION snapshot_blog_post_revision(UUID, UUID, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION snapshot_blog_post_revision(UUID, UUID, TEXT, UUID) TO service_role;

-- =============================================================================
-- Capture an 'initial' revision on every new post (including AI-generated ones)
-- =============================================================================

CREATE OR REPLACE FUNCTION blog_posts_capture_initial_revision()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM snapshot_blog_post_revision(NEW.id, NEW.author_id, 'initial', NULL);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER blog_posts_initial_revision
    AFTER INSERT ON blog_posts
    FOR EACH ROW EXECUTE FUNCTION blog_posts_capture_initial_revision();

-- Backfill: snapshot every existing blog_posts row so the history view has
-- something to show for posts created before this migration.
INSERT INTO blog_post_revisions (
    post_id, editor_id,
    title, slug, excerpt,
    content_html, content_json, featured_image_url,
    seo_title, seo_description, canonical_url, og_image_url,
    tags, category, status, ai_meta,
    reason, created_at
)
SELECT
    p.id, p.author_id,
    p.title, p.slug, p.excerpt,
    p.content_html, p.content_json, p.featured_image_url,
    p.seo_title, p.seo_description, p.canonical_url, p.og_image_url,
    p.tags, p.category, p.status, p.ai_meta,
    'initial', p.created_at
FROM blog_posts p;

-- =============================================================================
-- 90-day retention with floor of 5 most-recent revisions per post
-- =============================================================================

CREATE OR REPLACE FUNCTION cleanup_blog_post_revisions()
RETURNS INT AS $$
DECLARE
    v_deleted INT;
BEGIN
    WITH ranked AS (
        SELECT id, post_id, created_at,
               ROW_NUMBER() OVER (PARTITION BY post_id ORDER BY created_at DESC) AS rn
        FROM blog_post_revisions
    )
    DELETE FROM blog_post_revisions r
    USING ranked
    WHERE r.id = ranked.id
      AND ranked.rn > 5
      AND ranked.created_at < NOW() - INTERVAL '90 days';
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION cleanup_blog_post_revisions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION cleanup_blog_post_revisions() TO service_role;

SELECT cron.schedule(
    'cleanup-blog-post-revisions',
    '0 4 * * *',
    $$SELECT cleanup_blog_post_revisions()$$
);

COMMIT;

-- =============================================================================
-- Verification
-- =============================================================================

SELECT
    'blog_post_revisions' AS table_name,
    (SELECT COUNT(*) FROM blog_post_revisions) AS rows,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = 'blog_post_revisions') AS columns,
    (SELECT COUNT(*) FROM pg_policies WHERE tablename = 'blog_post_revisions') AS rls_policies,
    (SELECT COUNT(*) FROM pg_trigger WHERE tgrelid = 'blog_posts'::regclass AND tgname = 'blog_posts_initial_revision') AS triggers,
    (SELECT COUNT(*) FROM cron.job WHERE jobname = 'cleanup-blog-post-revisions') AS cron_jobs;
