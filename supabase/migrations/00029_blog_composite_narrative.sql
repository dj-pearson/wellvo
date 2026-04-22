-- Daily OK Blog — Composite-Narrative Integrity Fix
-- Migration: 00029_blog_composite_narrative
--
-- The previous integrity rule permitted first-person narrative voice so long
-- as it read as an archetype. The "App I Wish I'd Had Before My Mom's Fall"
-- article slipped through that rule: exact distances (1,400 miles), exact
-- ages (74), exact ownership timelines (thirty-two years), exact incident
-- details (hip fracture after falling in the kitchen), and specific product-
-- outcome claims (set her up three weeks after rehab) together read as a
-- claimed real testimonial. Under FTC endorsement guidelines and Google's
-- YMYL Search Quality rules, a fabricated testimonial presented as fact is
-- as disqualifying as a fabricated reviewer credential.
--
-- This migration:
--   1. Replaces the integrity_rules array with a stronger version that
--      forbids specific-factoid details in first-person voice and requires
--      a composite-story framing note at the top of any such article.
--   2. Patches the already-published mom's-fall article to insert the
--      framing note right after the medical disclaimer.

BEGIN;

-- =============================================================================
-- 1. Replace integrity_rules with strengthened set
-- =============================================================================

UPDATE blog_generation_config
SET config = jsonb_set(
    config,
    '{e_e_a_t,integrity_rules}',
    $$[
      "If verified_reviewer is null in this config, do NOT append any 'Reviewed by' line. No exceptions. Fabricating a reviewer is a disqualifying violation.",
      "Never claim quantified outcomes about Daily OK users or setup ('most families', '58% of caregivers', 'thousands use it', '4.8 stars'). Use design-intent or qualitative phrasing only.",
      "When using a statistic about caregiver behavior, aging, or health: cite a specific named source in the same sentence (AARP, NIA, CDC, Alzheimer's Association, Michael J. Fox Foundation, American Stroke Association, CDC STEADI). If you cannot name a source, use qualitative language ('many', 'often', 'commonly') instead of a number.",
      "First-person narrative voice ('I', 'my mom', 'my dad', 'we set her up') is allowed ONLY when written as a clearly composite archetype — not a specific claimed-true personal account. FORBIDDEN specificities that make a story read as claimed-real: exact distances ('1,400 miles', '2,000 miles away'), exact ages ('74', '82'), exact ownership or relationship timelines ('the house she'd owned for thirty-two years'), specific medical incidents with named injuries ('hip fracture after falling in the kitchen'), exact times of specific events ('Tuesday morning at 9:15 a.m.'), and claimed product-user outcomes ('we set her up on Daily OK three weeks after rehab', 'by 9:15 a.m. I know she's up'). Use approximate language instead: 'about a thousand miles away', 'in her 70s', 'decades in the same house', 'a morning last year', 'after a serious fall', 'many caregivers in this situation report'.",
      "Any article written in first-person narrative voice MUST open with a composite-story framing note in its own paragraph, placed immediately AFTER the TL;DR blockquote and AFTER any medical disclaimer, BEFORE the first narrative paragraph. Use this template or a close paraphrase: <p><em>This story draws on patterns many long-distance caregivers describe — specific names, places, and details are generalized.</em></p>",
      "Never invent customer testimonials, direct user quotes, or named fictional characters presented as real people. Archetype framing ('many caregivers describe...') is fine; named-person framing ('Linda from Ohio says...') is not.",
      "Daily OK does not detect falls, vital signs, medication adherence, or any health event. Never imply it does. Never claim it replaces 911, emergency services, or professional medical care."
    ]$$::jsonb,
    FALSE
)
WHERE id = 1;

-- =============================================================================
-- 2. Patch the published mom's-fall article
--    Inserts the composite-story framing note right after the medical
--    disclaimer paragraph. Matched by a phrase unique to that article.
-- =============================================================================

UPDATE blog_posts
SET content_html = regexp_replace(
    content_html,
    E'(<p><em>This article is general information[^<]*</em></p>)',
    E'\\1\n<p><em>This story draws on patterns many long-distance caregivers describe — specific names, places, and details are generalized.</em></p>',
    'i'
),
updated_at = NOW()
WHERE content_html LIKE '%1,400 miles%'
   OR content_html LIKE '%owned for thirty-two years%'
   OR lower(title) LIKE '%i wish i%had%fall%';

COMMIT;

-- Verification
SELECT
    'integrity_rules count' AS check,
    jsonb_array_length(config -> 'e_e_a_t' -> 'integrity_rules')::text AS value
FROM blog_generation_config WHERE id = 1
UNION ALL
SELECT
    'mom-fall article has framing note',
    (
        SELECT (content_html LIKE '%This story draws on patterns%')::text
        FROM blog_posts
        WHERE lower(title) LIKE '%i wish i%had%fall%'
        LIMIT 1
    );
