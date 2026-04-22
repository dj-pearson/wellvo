-- Daily OK Blog — Integrity Fixes
-- Migration: 00028_blog_integrity_fixes
--
-- Remove the fabricated "Reviewed by a licensed clinical social worker"
-- reviewer line that was appearing on YMYL articles without an actual
-- reviewer having signed off on them. This is an E-E-A-T violation under
-- Google's Search Quality guidelines and a consumer-protection risk. Until
-- a real LCSW (or other credentialed reviewer) is contracted, no reviewer
-- line should appear on any article.
--
-- This migration:
--   1. Removes the reviewer_line_when_ymyl instruction from the config.
--   2. Adds a verified_reviewer placeholder (null) — when populated with a
--      real name, credential, and date, the generator will emit a truthful
--      reviewer line. Template provided in comments.
--   3. Strengthens the no_fabrication rule with explicit prohibitions.
--   4. Adds an integrity_rules array for the generator to read.
--   5. Replaces the "Most caregivers set up in under two minutes"
--      closing-CTA template with design-intent phrasing.
--   6. Patches all existing blog_posts to strip the fabricated reviewer
--      paragraph from their content_html.
--
-- How to turn the reviewer line back on once a real LCSW is contracted:
--
--   UPDATE blog_generation_config
--   SET config = jsonb_set(
--       config,
--       '{e_e_a_t,verified_reviewer}',
--       jsonb_build_object(
--           'name', 'Jane Smith',
--           'credential', 'LCSW',
--           'reviewed_at', '2026-05-01'
--       )
--   )
--   WHERE id = 1;
--
-- With that populated, buildSystemPrompt will instruct the generator to
-- append a truthful line: "Medically reviewed by Jane Smith, LCSW on
-- 2026-05-01." Only on YMYL articles.

BEGIN;

-- =============================================================================
-- 1. Remove the fabricated reviewer line instruction
-- =============================================================================

UPDATE blog_generation_config
SET config = config #- '{e_e_a_t,reviewer_line_when_ymyl}'
WHERE id = 1;

-- =============================================================================
-- 2. Add verified_reviewer placeholder (null until contracted)
-- =============================================================================

UPDATE blog_generation_config
SET config = jsonb_set(config, '{e_e_a_t,verified_reviewer}', 'null'::jsonb, TRUE)
WHERE id = 1;

-- =============================================================================
-- 3. Strengthen the no_fabrication rule
-- =============================================================================

UPDATE blog_generation_config
SET config = jsonb_set(
    config,
    '{e_e_a_t,no_fabrication}',
    $$"Absolute integrity rules. (1) Never invent reviewer credentials or professional review lines. Do NOT write 'Reviewed by a licensed clinical social worker' or any similar credentialed-review line unless a verified_reviewer object with a specific name and credential is explicitly provided in the system prompt. (2) Never invent statistics, percentages, named sources, user names, testimonials, or star ratings. (3) Never assert quantified outcomes about Daily OK setup times, user counts, or satisfaction rates. Phrases like 'most families set up in under two minutes', 'thousands of caregivers trust Daily OK', or 'rated 4.8 stars' are forbidden. Use design-intent language instead: 'setup is designed to take', 'built for', 'intended for'. (4) When describing caregiver behavior patterns, use qualitative language — 'many caregivers report', 'commonly', 'often', 'in our experience' — and do NOT quantify with 'most', 'a majority', or specific percentages unless a named source is cited in the same sentence."$$::jsonb,
    FALSE
)
WHERE id = 1;

-- =============================================================================
-- 4. Add integrity_rules array (rendered as its own block in system prompt)
-- =============================================================================

UPDATE blog_generation_config
SET config = jsonb_set(
    config,
    '{e_e_a_t,integrity_rules}',
    $$[
      "If verified_reviewer is null in this config, do NOT append any 'Reviewed by' line. No exceptions. Fabricating a reviewer is a disqualifying violation.",
      "Never claim quantified outcomes about Daily OK users or setup ('most families', '58% of caregivers', 'thousands use it', '4.8 stars'). Use design-intent or qualitative phrasing only.",
      "When using a statistic about caregiver behavior, aging, or health: cite a specific named source in the same sentence (AARP, NIA, CDC, Alzheimer's Association, Michael J. Fox Foundation, American Stroke Association, CDC STEADI). If you cannot name a source, use qualitative language ('many', 'often', 'commonly') instead of a number.",
      "Never invent customer testimonials, direct user quotes, or fictional caregiver stories presented as real. First-person narrative framing is allowed ('I live 2000 miles from my parents') but must be recognizable as an archetype, not a claimed real person.",
      "Daily OK does not detect falls, vital signs, medication adherence, or any health event. Never imply it does. Never claim it replaces 911, emergency services, or professional medical care."
    ]$$::jsonb,
    TRUE
)
WHERE id = 1;

-- =============================================================================
-- 5. Replace closing_template_examples (remove "Most caregivers" phrasing)
-- =============================================================================

UPDATE blog_generation_config
SET config = jsonb_set(
    config,
    '{conversion,cta_placement,closing_template_examples}',
    $$[
      "<p><strong>Stop carrying the quiet daily worry.</strong> Daily OK sends one gentle \"I'm OK?\" prompt each morning and alerts you if your parent misses it — no pendant, no GPS, no tracking. <a href=\"https://dailyok.net/pricing\">See how Daily OK works →</a></p>",
      "<p>If you're ready to replace the daily \"did she call today?\" anxiety with one quiet confirmation, <a href=\"https://dailyok.net/pricing\">try Daily OK free</a>. Plans start at $3.99/month. Cancel anytime.</p>",
      "<p>Setup is designed to take under two minutes on the caregiver's own phone. The parent never downloads anything — they just tap one button each morning on a phone they already own. <a href=\"https://dailyok.net/pricing\">See the plans →</a></p>"
    ]$$::jsonb,
    FALSE
)
WHERE id = 1;

-- =============================================================================
-- 6. Strip the fabricated reviewer paragraph from published posts
--    Handles <p>...</p> and <p><em>...</em></p> variants, case-insensitive.
-- =============================================================================

UPDATE blog_posts
SET content_html = regexp_replace(
    content_html,
    E'<p>\\s*(<em>)?\\s*Reviewed by a licensed clinical social worker[^<]*(</em>)?\\s*</p>\\s*',
    '',
    'gi'
),
updated_at = NOW()
WHERE content_html ~* 'Reviewed by a licensed clinical social worker';

COMMIT;

-- Verification
SELECT
    'config reviewer_line_when_ymyl removed' AS check,
    (config -> 'e_e_a_t' -> 'reviewer_line_when_ymyl') IS NULL AS pass
FROM blog_generation_config WHERE id = 1
UNION ALL
SELECT
    'verified_reviewer placeholder is null',
    (config -> 'e_e_a_t' -> 'verified_reviewer') = 'null'::jsonb
FROM blog_generation_config WHERE id = 1
UNION ALL
SELECT
    'integrity_rules present',
    jsonb_typeof(config -> 'e_e_a_t' -> 'integrity_rules') = 'array'
FROM blog_generation_config WHERE id = 1
UNION ALL
SELECT
    'no posts still contain fabricated reviewer line',
    NOT EXISTS (
        SELECT 1 FROM blog_posts
        WHERE content_html ~* 'Reviewed by a licensed clinical social worker'
    );
