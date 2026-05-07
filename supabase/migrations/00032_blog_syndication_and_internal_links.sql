-- Daily OK Blog — Syndication provenance + internal-link suggestions
-- Migration: 00032_blog_syndication_and_internal_links
--
-- Two related additions for Phase 2:
--
-- 1. social_posts.source_post_id + variant_meta — every syndicated draft (X
--    thread, LinkedIn long-form, Facebook, Pinterest pin) traces back to the
--    blog post it came from, with platform-specific metadata (hook, hashtags,
--    first_comment, variant index) captured for Make.com to consume. (US-BLOG-044/045/046/048)
--
-- 2. blog_internal_link_suggestions — every contextual link the auto-injector
--    proposes or inserts is logged so editors can audit and revert. Append-only
--    history; the current state on blog_posts is authoritative. (US-BLOG-055)

BEGIN;

-- =============================================================================
-- 1. social_posts: link syndicated drafts back to their source blog post
-- =============================================================================

ALTER TABLE social_posts
    ADD COLUMN IF NOT EXISTS source_post_id UUID REFERENCES blog_posts(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS variant_meta JSONB;

CREATE INDEX IF NOT EXISTS idx_social_posts_source_post ON social_posts(source_post_id, created_at DESC)
    WHERE source_post_id IS NOT NULL;

-- =============================================================================
-- 2. blog_internal_link_suggestions
-- =============================================================================

CREATE TYPE blog_link_suggestion_status AS ENUM (
    'proposed',     -- generated, not yet acted on
    'auto_inserted',-- linker injected this one into the body
    'accepted',     -- editor approved a 'proposed' suggestion (manually inserted)
    'rejected',     -- editor rejected
    'skipped'       -- linker skipped (already linked, anchor missing, etc.)
);

CREATE TABLE blog_internal_link_suggestions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- The post that gets the new link inserted into it.
    post_id UUID NOT NULL REFERENCES blog_posts(id) ON DELETE CASCADE,

    -- The post being linked TO.
    target_post_id UUID NOT NULL REFERENCES blog_posts(id) ON DELETE CASCADE,

    -- Anchor text the linker chose (or proposed). Stored for audit / revert.
    anchor_text TEXT NOT NULL,
    -- Heuristic that produced this suggestion: 'tag_overlap', 'cluster_match',
    -- 'keyword_match', 'manual'. Free text so we can add new sources later.
    source TEXT NOT NULL,
    -- 0–100. Higher = stronger signal that the anchor is a natural fit.
    relevance_score INT NOT NULL DEFAULT 50,

    status blog_link_suggestion_status NOT NULL DEFAULT 'proposed',
    actioned_by UUID REFERENCES users(id) ON DELETE SET NULL,
    actioned_at TIMESTAMPTZ,
    -- Free-form notes (e.g., reason rejected, scope of insertion).
    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Don't let the same auto-injection run twice on the same post→target pair.
    CONSTRAINT blog_internal_link_suggestions_unique_pair
        UNIQUE (post_id, target_post_id, anchor_text)
);

CREATE INDEX idx_blog_link_suggestions_post ON blog_internal_link_suggestions(post_id, created_at DESC);
CREATE INDEX idx_blog_link_suggestions_target ON blog_internal_link_suggestions(target_post_id);
CREATE INDEX idx_blog_link_suggestions_status ON blog_internal_link_suggestions(status, created_at DESC);

ALTER TABLE blog_internal_link_suggestions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage internal link suggestions"
    ON blog_internal_link_suggestions FOR ALL
    USING (is_system_admin())
    WITH CHECK (is_system_admin());

COMMIT;

-- =============================================================================
-- Verification
-- =============================================================================

SELECT
    'social_posts.source_post_id' AS column_name,
    (SELECT COUNT(*) FROM information_schema.columns
       WHERE table_name = 'social_posts' AND column_name = 'source_post_id') AS exists_source,
    (SELECT COUNT(*) FROM information_schema.columns
       WHERE table_name = 'social_posts' AND column_name = 'variant_meta') AS exists_variant_meta,
    (SELECT COUNT(*) FROM pg_indexes
       WHERE indexname = 'idx_social_posts_source_post') AS index_present,
    (SELECT COUNT(*) FROM information_schema.tables
       WHERE table_name = 'blog_internal_link_suggestions') AS suggestions_table_exists,
    (SELECT COUNT(*) FROM pg_policies
       WHERE tablename = 'blog_internal_link_suggestions') AS suggestions_rls_policies;
