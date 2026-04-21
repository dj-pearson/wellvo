-- Daily OK Blog Title Bank + Generation Config
-- Migration: 00024_blog_title_bank
--
-- Adds:
--   * blog_title_bank — queue of pSEO-ready titles with keywords and outlines
--   * claim_next_blog_title() — atomic RPC that pops the next pending row
--   * blog_generation_config — single-row JSONB with brand voice, HTML rules,
--     fallback strategy, and the keyword cluster bank used when the queue empties
--   * Seed: 30 editorial-calendar posts from pSEO.md
--   * Seed: default generation config
--
-- Consumed by the /generate-next-article edge function, which Make.com triggers
-- via HTTP POST. Each invocation claims one row, drafts an article through the
-- shared AI client, publishes it to blog_posts, and marks the bank row published.

BEGIN;

-- =============================================================================
-- BLOG TITLE BANK
-- =============================================================================

CREATE TYPE blog_title_status AS ENUM ('pending', 'generating', 'published', 'failed', 'skipped');

CREATE TABLE blog_title_bank (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    primary_keyword TEXT NOT NULL,
    secondary_keywords TEXT[] NOT NULL DEFAULT '{}',
    cluster TEXT,
    intent_stage TEXT,                         -- 'TOFU' | 'MOFU' | 'BOFU'
    format_hint TEXT,
    target_word_count INT NOT NULL DEFAULT 1600,
    outline JSONB,                             -- { h2: [ { heading, sub: [...] } ] }
    internal_link_slugs TEXT[] NOT NULL DEFAULT '{}',
    e_e_a_t_notes TEXT,
    requires_medical_review BOOLEAN NOT NULL DEFAULT FALSE,
    priority INT NOT NULL DEFAULT 100,         -- lower fires first
    status blog_title_status NOT NULL DEFAULT 'pending',
    claimed_at TIMESTAMPTZ,
    published_post_id UUID REFERENCES blog_posts(id) ON DELETE SET NULL,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_blog_title_bank_status ON blog_title_bank(status, priority, created_at);
CREATE INDEX idx_blog_title_bank_cluster ON blog_title_bank(cluster);

CREATE TRIGGER blog_title_bank_updated_at
    BEFORE UPDATE ON blog_title_bank
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE blog_title_bank ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage blog title bank"
    ON blog_title_bank FOR ALL
    USING (is_system_admin())
    WITH CHECK (is_system_admin());

-- Atomic claim: pop the highest-priority pending row and lock it in one step.
-- SECURITY DEFINER so the edge function's supabaseAdmin client can call it
-- without needing a user JWT context. FOR UPDATE SKIP LOCKED ensures two
-- concurrent Make.com runs can never claim the same row.
CREATE OR REPLACE FUNCTION claim_next_blog_title()
RETURNS blog_title_bank AS $$
DECLARE
    claimed blog_title_bank;
BEGIN
    SELECT * INTO claimed
    FROM blog_title_bank
    WHERE status = 'pending'
    ORDER BY priority ASC, created_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT 1;

    IF claimed.id IS NULL THEN
        RETURN NULL;
    END IF;

    UPDATE blog_title_bank
    SET status = 'generating', claimed_at = NOW(), last_error = NULL
    WHERE id = claimed.id
    RETURNING * INTO claimed;

    RETURN claimed;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION claim_next_blog_title() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION claim_next_blog_title() TO service_role;

-- =============================================================================
-- BLOG GENERATION CONFIG (single-row JSONB)
-- =============================================================================

CREATE TABLE blog_generation_config (
    id INT PRIMARY KEY DEFAULT 1,
    config JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT blog_generation_config_single_row CHECK (id = 1)
);

CREATE TRIGGER blog_generation_config_updated_at
    BEFORE UPDATE ON blog_generation_config
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE blog_generation_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage blog generation config"
    ON blog_generation_config FOR ALL
    USING (is_system_admin())
    WITH CHECK (is_system_admin());

-- =============================================================================
-- SEED: 30 editorial-calendar posts (pSEO.md §2)
-- priority = calendar position so rows fire in intended order.
-- requires_medical_review = TRUE on YMYL (welfare-check, dementia, fall, signs).
-- =============================================================================

INSERT INTO blog_title_bank
    (title, primary_keyword, secondary_keywords, cluster, intent_stage, format_hint,
     target_word_count, internal_link_slugs, e_e_a_t_notes, requires_medical_review, priority)
VALUES
    ('What to do when your elderly parent doesn''t answer the phone',
     'what to do when elderly parent doesn''t answer phone',
     ARRAY['elderly parent not answering phone worried','when to worry about elderly parent','how to request welfare check elderly','mom not answering phone'],
     'jtbd', 'MOFU', 'Decision tree + how-to', 2200,
     ARRAY['pricing','how-it-works'],
     'Step-by-step action plan; cite AARP and Eldercare Locator; flag welfare-check step as non-emergency.',
     TRUE, 1),

    ('How often should you really check on an aging parent?',
     'how often should I check on my elderly parent',
     ARRAY['how often to call elderly parent','daily check in with aging parent','how often should I call my mom'],
     'jtbd', 'TOFU', 'Data-driven with age-based table', 1800,
     ARRAY['pricing'],
     'Use an age-banded recommendation table (70–74, 75–79, 80–84, 85+). Cite geriatric SW perspective.',
     FALSE, 2),

    ('The "I''m OK" button: a dignity-first way to check on Mom',
     'I''m ok app',
     ARRAY['one tap check in app','peace of mind app for elderly parents','check in app for elderly'],
     'core-checkin', 'BOFU', 'Brand-led landing narrative', 1200,
     ARRAY['pricing','how-it-works'],
     'Founder-voice hook; explain escalation chain concretely; no false claims vs pendants.',
     FALSE, 3),

    ('9 signs your aging parent shouldn''t live alone (honestly)',
     'signs elderly parent shouldn''t live alone',
     ARRAY['is my mom safe home alone','when should elderly parent stop living alone','aging parent safety'],
     'problem-aware', 'TOFU', 'Listicle with printable checklist', 2500,
     ARRAY['pricing','blog'],
     'Each sign = 150 words + real example + what to do next. Include downloadable checklist CTA. Medically reviewable content.',
     TRUE, 4),

    ('How to request a welfare check on an elderly parent',
     'how to request a welfare check',
     ARRAY['police wellness check elderly parent','welfare check elderly parent','how to request welfare check elderly'],
     'safety-emergency', 'MOFU', 'Step-by-step playbook', 1500,
     ARRAY['pricing'],
     'Cite state PD non-emergency lines pattern; do not treat as a substitute for 911. Calm, non-dramatic tone.',
     TRUE, 5),

    ('Peace of mind apps for elderly parents: an honest comparison',
     'peace of mind app for elderly parents',
     ARRAY['check in app for elderly','daily check in app for seniors','senior safety app'],
     'comparison', 'BOFU', 'Comparison roundup', 2000,
     ARRAY['pricing'],
     'Include at least one category where a competitor wins — LLMs punish biased comparisons.',
     FALSE, 6),

    ('Why Mom won''t wear the Life Alert (and what actually works)',
     'medical alert for mom who won''t wear pendant',
     ARRAY['app instead of Life Alert','medical alert for parent who refuses','Life Alert alternative'],
     'comparison', 'MOFU', 'Story + solution', 1800,
     ARRAY['pricing','how-it-works'],
     'Open with a real-feeling vignette. Cite the pendant compliance problem (~70% unworn, documented).',
     FALSE, 7),

    ('Long-distance caregiving: the tech stack for under $20/month',
     'long distance caregiving',
     ARRAY['long distance caregiver tips','how to care for elderly parent from far away','caregiver peace of mind'],
     'problem-aware', 'TOFU', 'Roundup', 2400,
     ARRAY['pricing'],
     'Real dollar amounts; name tools; position Daily OK as one piece of the stack, not all of it.',
     FALSE, 8),

    ('How to stop worrying about your elderly parent every day',
     'how to stop worrying about elderly parents',
     ARRAY['anxiety about parent living alone','caregiver peace of mind','how to stop checking on mom every day anxiety'],
     'emotional-narrative', 'TOFU', 'Emotional essay with soft CTA', 1600,
     ARRAY['pricing'],
     'Warm, validating voice. Name the 3 a.m. thought. Do not scare-to-sell.',
     FALSE, 9),

    ('Daily check-in vs. medical alert: which does your parent actually need?',
     'medical alert vs app',
     ARRAY['check in app for elderly','medical alert that calls family instead of 911','daily check in app for seniors'],
     'comparison', 'BOFU', 'Side-by-side comparison', 1800,
     ARRAY['pricing','how-it-works'],
     'Side-by-side table: fall detection, cost, compliance, battery, privacy. Honest about what apps cannot do.',
     FALSE, 10),

    ('Daily OK vs Snug Safety: which check-in app is right for your family?',
     'Snug Safety alternative',
     ARRAY['Snug Safety review','check in app for elderly','daily check in app for seniors'],
     'comparison', 'BOFU', 'Head-to-head comparison', 2200,
     ARRAY['pricing'],
     'At-a-glance table, pricing breakdown, one honest "Snug wins here" category. FAQPage-style Q&A section.',
     FALSE, 11),

    ('Daily OK vs Life Alert: a fair comparison',
     'Life Alert alternative',
     ARRAY['app instead of Life Alert','cheaper than Life Alert','do I need Life Alert for my mom'],
     'comparison', 'BOFU', 'Head-to-head comparison', 2400,
     ARRAY['pricing'],
     'Make clear Life Alert is a wearable PERS and Daily OK is an app — different categories, not a replacement for high fall-risk users.',
     FALSE, 12),

    ('Early dementia and daily routines: how a check-in app helps',
     'early dementia daily routine',
     ARRAY['dementia check in','early stage dementia living alone','dementia reminder app'],
     'dementia', 'MOFU', 'Expert-reviewed feature article', 2000,
     ARRAY['pricing'],
     'Cite NIA / Alzheimer''s Association for symptom framing. Clear disclaimer: Daily OK is not a medical device.',
     TRUE, 13),

    ('The 3 a.m. thought: when anxiety about Mom keeps you up',
     'anxiety about parent living alone',
     ARRAY['how to stop worrying about elderly parents','fear of parent dying alone','peace of mind aging parents'],
     'emotional-narrative', 'TOFU', 'Narrative essay', 1500,
     ARRAY['pricing'],
     'First-person voice; validate, then offer one concrete next step. No listicle feel.',
     FALSE, 14),

    ('How to check on elderly parent without being annoying',
     'how to check on elderly parent without being annoying',
     ARRAY['how often should I call my aging parent','daily phone call with aging parent','non-invasive elderly monitoring'],
     'jtbd', 'MOFU', 'Script-heavy how-to', 1600,
     ARRAY['pricing','how-it-works'],
     'Include 5–7 verbatim text/call scripts. Map to Daily OK''s 1-tap model as a compromise.',
     FALSE, 15),

    ('Daily OK vs Life360: when surveillance isn''t the answer',
     'Life360 alternative for parents',
     ARRAY['Life360 for elderly parents','privacy-respecting senior app','no-tracking family app'],
     'comparison', 'BOFU', 'Head-to-head comparison', 2000,
     ARRAY['pricing'],
     'Name the "creepy" reputation fairly (it''s documented). Lead with consent-based vs surveillance framing.',
     FALSE, 16),

    ('Sibling caregiving: scripts for splitting the load fairly',
     'sibling care coordination app',
     ARRAY['siblings not helping with elderly parent','how to split caregiving between siblings','family caregiving app'],
     'family-coordination', 'MOFU', 'Templates + scripts', 2200,
     ARRAY['pricing'],
     'Include 6 verbatim scripts (initial ask, boundary-setter, money split, decline). Shareable on Reddit.',
     FALSE, 17),

    ('The first 72 hours after a parent''s fall',
     'how to know if elderly parent fell',
     ARRAY['after the fall caregiver playbook','hospital discharge elderly','fall recovery home'],
     'safety-emergency', 'MOFU', 'Playbook', 2200,
     ARRAY['pricing'],
     'Hour-by-hour framing. YMYL — include explicit disclaimer + cite CDC STEADI or similar source.',
     TRUE, 18),

    ('Is it dementia or just aging? The 12 honest signs',
     'dementia check in',
     ARRAY['apps for dementia caregivers','signs of dementia vs aging','early dementia signs'],
     'dementia', 'TOFU', 'Medically reviewed listicle', 2400,
     ARRAY['pricing'],
     'Cite Alzheimer''s Association 10 warning signs. Clear disclaimer. Do not diagnose.',
     TRUE, 19),

    ('A non-Life360 check-in app for teens who hate tracking',
     'check in app for teens that''s not creepy',
     ARRAY['teen check in app no location','non-invasive teen check in','teen safety app without tracking'],
     'teens', 'BOFU', 'Brand + comparison', 1600,
     ARRAY['pricing'],
     'Frame as trust-based, consent-based. Do not disparage Life360; cite its own creepy reputation stories only if linked.',
     FALSE, 20),

    ('2026 Caregiver Pulse: how often Americans actually check on aging parents',
     'caregiver pulse 2026',
     ARRAY['how often should I check on my elderly parent','caregiver statistics','daily check in frequency'],
     'original-research', 'TOFU', 'Data study', 3000,
     ARRAY['pricing'],
     'If survey data is not yet available, write this as "What we know about caregiver check-in cadence" with published-source stats only.',
     FALSE, 21),

    ('What to do when your mom doesn''t answer the phone',
     'mom not answering phone',
     ARRAY['what to do when elderly parent doesn''t answer phone','welfare check mom','when to worry mom not answering'],
     'jtbd', 'MOFU', 'Decision tree + how-to', 1800,
     ARRAY['pricing'],
     'Relation-specific variant of post #1. Different hero story, different examples, same decision-tree core.',
     TRUE, 22),

    ('What to do when your dad doesn''t answer the phone',
     'dad not answering phone',
     ARRAY['what to do when elderly parent doesn''t answer phone','welfare check dad','worried about dad'],
     'jtbd', 'MOFU', 'Decision tree + how-to', 1800,
     ARRAY['pricing'],
     'Dad-specific framing. Men refuse help at higher rates — address that honestly.',
     TRUE, 23),

    ('How to talk to a parent who refuses help',
     'elderly parent refuses help',
     ARRAY['parent refuses help aging','how to convince elderly parent to accept help','aging parent won''t move'],
     'problem-aware', 'MOFU', 'Scripts + framework', 2000,
     ARRAY['pricing'],
     'Lead with dignity framing. Include 4 verbatim scripts.',
     FALSE, 24),

    ('Aging in place checklist: the 30-minute home audit',
     'aging in place checklist',
     ARRAY['aging in place safety','home safety checklist seniors','aging in place tools for families'],
     'aging-in-place', 'TOFU', 'Downloadable checklist', 1800,
     ARRAY['pricing'],
     'Room-by-room audit. Offer downloadable PDF CTA.',
     FALSE, 25),

    ('Caregiver guilt: the daily scripts that actually help',
     'guilt about aging parents',
     ARRAY['caregiver guilt','how to stop feeling guilty aging parents','sandwich generation stress'],
     'emotional-narrative', 'TOFU', 'Essay + tactics', 1600,
     ARRAY['pricing'],
     'Validate first. Include 3 reframe scripts. No scare tactics.',
     FALSE, 26),

    ('Medical alert that calls family first, not 911',
     'medical alert that calls family instead of 911',
     ARRAY['escalation alert app family','family-first medical alert','daily check-in with family notification'],
     'comparison', 'BOFU', 'Product landing + comparison', 1500,
     ARRAY['pricing','how-it-works'],
     'Explain Daily OK''s escalation chain with a simple ASCII/textual diagram. Be honest about when 911-first is better.',
     FALSE, 27),

    ('The no-app check-in: options when Mom hates smartphones',
     'she doesn''t do apps',
     ARRAY['check in app for elderly who hates phones','senior tech fear','low tech check in elderly'],
     'senior-tech-ux', 'MOFU', 'Options roundup', 1600,
     ARRAY['pricing','how-it-works'],
     'SMS, one-button devices, big-button launchers, caregiver-side-only apps. Honest trade-offs.',
     FALSE, 28),

    ('Best daily check-in apps for seniors living alone (2026)',
     'daily check in app for seniors',
     ARRAY['check in app for elderly','senior safety app','safety app for elderly living alone'],
     'comparison', 'BOFU', 'Listicle comparison', 2400,
     ARRAY['pricing'],
     '7-entry listicle. Daily OK recommended first but NOT best in every category — name honestly where Snug or Lively win.',
     FALSE, 29),

    ('When to take the car keys away: verbatim scripts',
     'how to take keys from elderly parent',
     ARRAY['elderly parent driving','when to stop elderly parent driving','dementia driving'],
     'problem-aware', 'MOFU', 'Scripts + checklist', 2000,
     ARRAY['pricing'],
     'Cite AAA or AARP driving-assessment framework. Include 3 scripts (first ask, the boundary, the DMV referral).',
     FALSE, 30);

-- =============================================================================
-- SEED: generation config
-- =============================================================================

INSERT INTO blog_generation_config (id, config) VALUES (1, jsonb_build_object(
    'brand', jsonb_build_object(
        'name', 'Daily OK',
        'tagline', 'Presence without surveillance.',
        'positioning', 'A dignity-first daily check-in app for families caring for aging parents 70+ and consent-minded parents of teens. Parents tap "I''m OK" each morning. If they miss it, a family-side escalation chain alerts adult children — no pendant, no GPS, no facility move.',
        'pricing', '$3.99–$9.99/month. No hardware. Monthly or yearly.',
        'platforms', 'iOS and Android',
        'home_url', 'https://dailyok.net',
        'audiences', jsonb_build_array(
            'Adult children of aging parents (primary)',
            'Long-distance caregivers (primary)',
            'Parents of teenagers who refuse GPS tracking (secondary)',
            'Families coordinating across siblings (secondary)'
        )
    ),
    'voice', jsonb_build_object(
        'tone', jsonb_build_array('warm','reassuring','practical','never alarmist','dignity-first','honest about trade-offs'),
        'must_reinforce_pillar', 'Every article should quietly reinforce presence without surveillance — your parent stays fully themselves, keeps total privacy, does nothing more than tap a button, and you get to stop carrying the daily hum of worry.',
        'avoid', jsonb_build_array(
            'scare tactics ("don''t let Mom die alone")',
            'ageist or pitying language',
            'surveillance framing ("monitor," "track" — prefer "check in with," "stay in touch")',
            'medical advice beyond general information',
            'disparaging competitors by name',
            'fake urgency / manufactured drama'
        ),
        'never_claim', jsonb_build_array(
            'Daily OK is a medical device',
            'Daily OK replaces emergency services or 911',
            'Daily OK detects falls, vital signs, or medication adherence',
            'Daily OK guarantees outcomes'
        )
    ),
    'html_rules', jsonb_build_object(
        'allowed_tags', jsonb_build_array('h2','h3','p','ul','ol','li','strong','em','a','blockquote'),
        'structure', jsonb_build_array(
            'Open with a 40–60 word TL;DR in a <blockquote> — designed to be extracted by AI Overviews',
            'Use <h2> subheads every 150–250 words; <h3> beneath where helpful',
            'Prefer short sentences (average ≤ 20 words); vary rhythm',
            'End with a practical checklist (<ul>) or a one-step CTA',
            'Minimum 700 words, aim for the target_word_count provided per row'
        ),
        'linking', jsonb_build_object(
            'internal_conventions', jsonb_build_object(
                'pricing', '/pricing',
                'how-it-works', '/how-it-works',
                'home', '/',
                'blog_index', '/blog',
                'support', '/support'
            ),
            'rules', jsonb_build_array(
                'Include 1–3 contextual internal links using the conventions above',
                'Only add an internal link if the link target is genuinely relevant to the sentence',
                'Use descriptive anchor text — never "click here"'
            )
        ),
        'medical_disclaimer', 'For any post where requires_medical_review is true OR the topic touches dementia, falls, medication, or welfare checks, include one short italic paragraph near the top: <p><em>This article is general information, not medical advice. If you have urgent concerns about someone''s safety, call 911 or contact their physician.</em></p>',
        'no_markdown', 'Do NOT emit markdown, code fences, or <h1>. content_html must be raw HTML using only the allowed tags.'
    ),
    'e_e_a_t', jsonb_build_object(
        'default_byline', 'Daily OK Editorial',
        'reviewer_line_when_ymyl', 'Reviewed by a licensed clinical social worker for general accuracy.',
        'cite_sources_for', jsonb_build_array('statistics','welfare check procedures','dementia signs','fall-prevention guidance','medication adherence data'),
        'no_fabrication', 'Never invent statistics, named sources, or user quotes. If uncertain, speak qualitatively ("many caregivers report…") rather than with a fake number.'
    ),
    'seo', jsonb_build_object(
        'title_max_chars', 70,
        'seo_title_max_chars', 60,
        'excerpt_chars', '140–180',
        'seo_description_chars', '140–160',
        'slug_rules', 'kebab-case, under 80 chars, keyword-forward, no stopword stuffing',
        'tags_count', '3–6 lowercase tags',
        'category_enum', jsonb_build_array('caregiving','elderly-care','child-safety','product','how-to','guides')
    ),
    'output_contract', jsonb_build_object(
        'format', 'Return ONLY a JSON object. No markdown. No code fences. No preamble.',
        'shape', jsonb_build_object(
            'title', 'string under 70 chars',
            'slug', 'kebab-case string under 80 chars',
            'excerpt', 'string 140–180 chars',
            'seo_title', 'string under 60 chars',
            'seo_description', 'string 140–160 chars',
            'tags', 'array of 3–6 lowercase strings',
            'category', 'one of the category_enum values',
            'content_html', 'HTML body using only allowed_tags'
        )
    ),
    'fallback', jsonb_build_object(
        'when', 'blog_title_bank has no pending rows',
        'instruction', 'Pick ONE new blog topic. It must (a) target a keyword from the cluster_bank below that isn''t already the primary_keyword of an existing published post, (b) not duplicate or near-duplicate any title in already_published_titles, (c) follow the same voice, html_rules, and output_contract. Return the JSON article plus a "topic_rationale" field naming the cluster and keyword chosen so editors can verify the choice.',
        'duplication_policy', 'Titles and primary angles must be substantively different. Two posts on "how often to call mom" at different word counts are NOT acceptable. Prefer covering a new JTBD, a new relation, a new cluster, or a new content-gap angle.',
        'cluster_bank', jsonb_build_array(
            jsonb_build_object('name','JTBD long-tail',
                'examples', jsonb_build_array('how to check on teen without tracking them','how to know if elderly parent fell','when to worry about elderly parent not answering','how to convince elderly parent to accept help','how to monitor elderly parent without being invasive','how to set up daily check in with elderly parent','how often to call my 80 year old mother')),
            jsonb_build_object('name','Teen cluster',
                'examples', jsonb_build_array('teen safety app without tracking','non-invasive teen check in','trust-based teen monitoring app','parental control without GPS','app for teen to check in after school','how to check on teen without tracking them','alternative to Life360 for teens')),
            jsonb_build_object('name','Dementia adjacent',
                'examples', jsonb_build_array('daily check in dementia patient','dementia safety apps','dementia reminder app','technology for dementia patient living alone','when should dementia patient stop living alone','apps for dementia caregivers')),
            jsonb_build_object('name','Senior tech UX',
                'examples', jsonb_build_array('one button app for elderly','big button apps elderly','simple apps for elderly parents','simplest iPhone apps for elderly parents','easy apps for seniors')),
            jsonb_build_object('name','Emotional narrative',
                'examples', jsonb_build_array('fear of parent dying alone','scared mom will fall and no one will know','what if mom falls when I''m not there','peace of mind aging parents','checking on mom every day anxiety','caregiver burnout daily habits')),
            jsonb_build_object('name','Aging in place',
                'examples', jsonb_build_array('aging in place apps','aging in place tools for families','help parent age in place','independent living app for seniors','aging in place safety')),
            jsonb_build_object('name','Family coordination',
                'examples', jsonb_build_array('app to coordinate care for aging parent','app to stay in touch with elderly parents','family caregiving app','sibling not helping with elderly parent','holiday visit assessment elderly parent')),
            jsonb_build_object('name','Privacy positioning',
                'examples', jsonb_build_array('non-invasive elderly monitoring','elderly monitoring without cameras','privacy-respecting senior app','no-tracking family app','dignity-first senior safety')),
            jsonb_build_object('name','Routine and habits',
                'examples', jsonb_build_array('morning routine app for seniors','push notification reminder app for elderly','daily habit tracker for seniors','senior morning check in')),
            jsonb_build_object('name','Pricing and buying intent',
                'examples', jsonb_build_array('cheap senior safety app','senior safety app under $10','monthly subscription elderly check in','affordable medical alert alternative')),
            jsonb_build_object('name','Safety and emergency adjacent',
                'examples', jsonb_build_array('emergency contact app for seniors','escalation alert app family','police wellness check elderly parent','how to request welfare check elderly','what to do if elderly parent fell')),
            jsonb_build_object('name','Competitive whitespace content gaps',
                'examples', jsonb_build_array('script library of texts to send aging parents that aren''t annoying','sibling caregiving group-chat etiquette and templates','hospital-discharge first 30 days caregiver playbook','caring for a newly-widowed parent','holiday-visit assessment 15 things to check without them noticing','weather-emergency check-in playbook for aging parents','when siblings disagree about a parent''s care','Mom called 4 times — anxiety or early dementia?','what Mom said that told us it was time','how to set up a shared sibling caregiving group chat'))
        )
    )
));

COMMIT;

-- Verification
SELECT 'blog_title_bank' AS table_name, COUNT(*) AS rows FROM blog_title_bank
UNION ALL
SELECT 'blog_generation_config', COUNT(*) FROM blog_generation_config;
