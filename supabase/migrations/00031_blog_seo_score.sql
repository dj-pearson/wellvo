-- Daily OK Blog — SEO Score columns
-- Migration: 00031_blog_seo_score
--
-- Adds an integer 0-100 SEO score and a JSONB breakdown to every blog post.
-- The score is computed by edge-functions/shared/seo-scorer.ts on every
-- create/update and on the AI publish path. Existing rows stay NULL until
-- they're edited again or until an admin runs the rescore_all action.
--
-- Rationale (US-BLOG-033): manual editorial review can't keep up with the
-- volume of AI-generated posts. A deterministic, transparent score on every
-- save lets editors triage and gives the auto-refresh agent (Phase 3) a
-- quality target it can optimize against.

BEGIN;

ALTER TABLE blog_posts
    ADD COLUMN IF NOT EXISTS seo_score INTEGER,
    ADD COLUMN IF NOT EXISTS seo_score_meta JSONB;

-- 0-100 only. NULL means "not yet scored" (existing rows).
ALTER TABLE blog_posts
    ADD CONSTRAINT blog_posts_seo_score_range CHECK (seo_score IS NULL OR (seo_score BETWEEN 0 AND 100));

-- Hot path for "what needs editorial attention" queries.
CREATE INDEX IF NOT EXISTS idx_blog_posts_seo_score ON blog_posts(seo_score) WHERE seo_score IS NOT NULL;

COMMIT;

-- Verification
SELECT
    'blog_posts.seo_score' AS column_name,
    (SELECT COUNT(*) FROM information_schema.columns
       WHERE table_name = 'blog_posts' AND column_name = 'seo_score') AS exists_seo_score,
    (SELECT COUNT(*) FROM information_schema.columns
       WHERE table_name = 'blog_posts' AND column_name = 'seo_score_meta') AS exists_seo_score_meta,
    (SELECT COUNT(*) FROM pg_indexes
       WHERE indexname = 'idx_blog_posts_seo_score') AS index_present;
