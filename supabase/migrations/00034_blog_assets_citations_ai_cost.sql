-- Daily OK Blog — Assets library, citations, AI cost view
-- Migration: 00034_blog_assets_citations_ai_cost
--
-- Three additions for Phase 4 polish:
--
-- 1. blog_assets — reusable images, quotes, links, files, data tables.
--    License + source are mandatory on every row (E-E-A-T + legal safety).
--    (US-BLOG-010)
-- 2. blog_citations — per-post sources captured during research / fact-check.
--    (US-BLOG-025)
-- 3. v_blog_ai_cost — read-only view aggregating tokens-per-day from the
--    JSONB ai_meta fields on blog_posts, blog_post_revisions, and
--    social_posts.variant_meta. Powers the cost dashboard tile. (US-BLOG-078)

BEGIN;

-- =============================================================================
-- 1. blog_assets
-- =============================================================================

CREATE TYPE blog_asset_type AS ENUM ('image', 'quote', 'link', 'file', 'data_table', 'expert_contact');

CREATE TABLE blog_assets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type blog_asset_type NOT NULL,

    -- Common fields
    title TEXT NOT NULL,
    description TEXT,
    tags TEXT[] NOT NULL DEFAULT '{}',
    -- Required on every asset for E-E-A-T + legal safety. Empty string means
    -- "I don't know" — better to know we don't know than to omit silently.
    source TEXT NOT NULL DEFAULT '',
    -- License identifier: 'CC0', 'CC-BY-4.0', 'editorial-use-only',
    -- 'custom' (see notes), 'unsplash-license', etc.
    license TEXT NOT NULL DEFAULT '',
    notes TEXT,

    -- Image / file
    url TEXT,                       -- public URL or storage path
    thumb_url TEXT,                 -- generated thumbnail if any
    alt_text TEXT,                  -- mandatory for image type (enforced in app)
    width_px INT,
    height_px INT,
    bytes BIGINT,
    mime_type TEXT,
    original_filename TEXT,

    -- Quote-specific
    quote_text TEXT,
    attributed_to TEXT,
    retrieved_at TIMESTAMPTZ,

    -- Data table (CSV preview)
    columns JSONB,                  -- [{ name, type }, ...]
    row_count INT,

    -- Expert contact
    contact_name TEXT,
    contact_expertise TEXT[],
    contact_email TEXT,
    response_rate NUMERIC(5, 4),

    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_blog_assets_type ON blog_assets(type, created_at DESC);
CREATE INDEX idx_blog_assets_tags ON blog_assets USING GIN(tags);
CREATE INDEX idx_blog_assets_search ON blog_assets USING GIN(to_tsvector('english',
    coalesce(title, '') || ' ' || coalesce(description, '') || ' ' ||
    coalesce(quote_text, '') || ' ' || coalesce(attributed_to, '')));

CREATE TRIGGER blog_assets_updated_at
    BEFORE UPDATE ON blog_assets
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE blog_assets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage blog assets"
    ON blog_assets FOR ALL
    USING (is_system_admin())
    WITH CHECK (is_system_admin());

-- =============================================================================
-- 2. blog_citations
-- =============================================================================

CREATE TABLE blog_citations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES blog_posts(id) ON DELETE CASCADE,

    -- The source itself
    source_url TEXT NOT NULL,
    -- Display name of the source (e.g., "AARP — Caregiver Statistics 2024")
    source_title TEXT NOT NULL,
    -- Author / publisher / agency
    attributed_to TEXT,
    -- The exact quoted or paraphrased excerpt referenced by the post
    excerpt TEXT,
    -- Where in the post this citation supports a claim (free-form)
    anchor_in_post TEXT,
    -- License or use category: 'public-source', 'fair-use', 'permission-granted', etc.
    license TEXT,

    -- When the source was last verified live. The freshness gate for refresh
    -- decisions — anything > 12mo old on a YMYL post is a flag.
    retrieved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_verified_at TIMESTAMPTZ,

    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Don't double-cite the same URL on the same post.
    CONSTRAINT blog_citations_unique_per_post UNIQUE (post_id, source_url)
);

CREATE INDEX idx_blog_citations_post ON blog_citations(post_id, created_at DESC);
CREATE INDEX idx_blog_citations_url ON blog_citations(source_url);

CREATE TRIGGER blog_citations_updated_at
    BEFORE UPDATE ON blog_citations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE blog_citations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage blog citations"
    ON blog_citations FOR ALL
    USING (is_system_admin())
    WITH CHECK (is_system_admin());

-- =============================================================================
-- 3. v_blog_ai_cost — token usage view
-- =============================================================================
--
-- Aggregates input/output/cache tokens per calendar day per "kind":
--   * generation        — initial AI draft (blog_posts.ai_meta)
--   * critique          — self-critic loop iterations (sum of critique_log.iterations)
--   * refresh_proposal  — auto-refresh agent (blog_post_revisions where reason='auto_refresh_proposal')
--   * syndication       — per-platform variants (social_posts.variant_meta.ai_meta)
--
-- Cost is left to the operator (per-model pricing changes too often to bake in).
-- Multiply input/output by your current $/MTok and sum.

CREATE OR REPLACE VIEW v_blog_ai_cost AS
WITH generation AS (
    SELECT
        DATE((p.ai_meta->>'generated_at')::TIMESTAMPTZ) AS day,
        'generation'::TEXT AS kind,
        SUM(COALESCE((p.ai_meta->>'input_tokens')::BIGINT, 0))           AS input_tokens,
        SUM(COALESCE((p.ai_meta->>'output_tokens')::BIGINT, 0))          AS output_tokens,
        SUM(COALESCE((p.ai_meta->>'cache_creation_tokens')::BIGINT, 0))  AS cache_creation_tokens,
        SUM(COALESCE((p.ai_meta->>'cache_read_tokens')::BIGINT, 0))      AS cache_read_tokens,
        COUNT(*) AS calls
    FROM blog_posts p
    WHERE p.ai_meta ? 'generated_at'
      AND p.ai_generated = TRUE
    GROUP BY 1
),
critique AS (
    SELECT
        DATE((p.ai_meta->>'generated_at')::TIMESTAMPTZ) AS day,
        'critique'::TEXT AS kind,
        SUM(COALESCE((iter->>'input_tokens')::BIGINT, 0))   AS input_tokens,
        SUM(COALESCE((iter->>'output_tokens')::BIGINT, 0))  AS output_tokens,
        0::BIGINT AS cache_creation_tokens,
        0::BIGINT AS cache_read_tokens,
        COUNT(*) AS calls
    FROM blog_posts p
    CROSS JOIN LATERAL jsonb_array_elements(
        COALESCE(p.ai_meta->'critique_log'->'iterations', '[]'::jsonb)
    ) AS iter
    WHERE p.ai_meta ? 'generated_at'
    GROUP BY 1
),
refresh_proposal AS (
    SELECT
        DATE(r.created_at) AS day,
        'refresh_proposal'::TEXT AS kind,
        SUM(COALESCE((r.ai_meta->>'input_tokens')::BIGINT, 0))   AS input_tokens,
        SUM(COALESCE((r.ai_meta->>'output_tokens')::BIGINT, 0))  AS output_tokens,
        0::BIGINT AS cache_creation_tokens,
        0::BIGINT AS cache_read_tokens,
        COUNT(*) AS calls
    FROM blog_post_revisions r
    WHERE r.reason = 'auto_refresh_proposal'
    GROUP BY 1
),
syndication AS (
    SELECT
        DATE(s.created_at) AS day,
        'syndication'::TEXT AS kind,
        SUM(COALESCE((s.variant_meta->'ai_meta'->>'input_tokens')::BIGINT, 0))   AS input_tokens,
        SUM(COALESCE((s.variant_meta->'ai_meta'->>'output_tokens')::BIGINT, 0))  AS output_tokens,
        0::BIGINT AS cache_creation_tokens,
        0::BIGINT AS cache_read_tokens,
        COUNT(*) AS calls
    FROM social_posts s
    WHERE s.source_post_id IS NOT NULL
      AND s.variant_meta ? 'ai_meta'
    GROUP BY 1
)
SELECT * FROM generation
UNION ALL SELECT * FROM critique
UNION ALL SELECT * FROM refresh_proposal
UNION ALL SELECT * FROM syndication;

GRANT SELECT ON v_blog_ai_cost TO service_role;

COMMIT;

-- =============================================================================
-- Verification
-- =============================================================================

SELECT
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'blog_assets')         AS assets_table,
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'blog_citations')      AS citations_table,
    (SELECT COUNT(*) FROM information_schema.views  WHERE table_name = 'v_blog_ai_cost')      AS cost_view,
    (SELECT COUNT(*) FROM pg_policies WHERE tablename = 'blog_assets')                        AS assets_rls,
    (SELECT COUNT(*) FROM pg_policies WHERE tablename = 'blog_citations')                     AS citations_rls;
