-- Daily OK Blog — Conversion Guidance + High-Intent Seed
-- Migration: 00025_blog_conversion_seed
--
-- Adds:
--   * `conversion` section to blog_generation_config.config covering app-store
--     links, CTA placement rules, value-props-by-audience, objection handlers,
--     social-proof honesty rules, and a "don't do" list.
--   * 18 new blog_title_bank rows at priorities 0–17 (interleave with the
--     existing 30 foundation posts; tie-break by created_at).
--
-- Every row carries thorough editor notes so the generator has enough context
-- to write a conversion-aware, honest, on-voice article.

BEGIN;

-- =============================================================================
-- Conversion guidance (merged into existing config JSONB)
-- =============================================================================

UPDATE blog_generation_config
SET config = config || jsonb_build_object(
    'conversion', jsonb_build_object(
        'goal', 'Every article should move the reader toward either downloading the Daily OK app or exploring the pricing page. Never sacrifice helpfulness for sales — readers who feel genuinely helped are far more likely to install. Assume the reader is anxious, time-starved, and has been let down by previous products.',

        'download_links', jsonb_build_object(
            'apple_app_store', 'https://apps.apple.com/us/app/dailyok-daily-check-in/id6760836697',
            'google_play_store', 'https://play.google.com/store/apps/details?id=net.dailyok.android',
            'pricing_page', 'https://dailyok.net/pricing',
            'how_it_works', 'https://dailyok.net/how-it-works',
            'home', 'https://dailyok.net'
        ),

        'cta_placement', jsonb_build_object(
            'rules', jsonb_build_array(
                'Place exactly two CTAs in articles under 2,000 words; three in articles 2,000+ words.',
                'First CTA: soft, contextual, after the first real insight or solution has been explained. Link a natural phrase in prose (e.g., ... which is why we built <a href="/pricing">Daily OK</a>).',
                'Second CTA: explicit, bold, at the close — one <p> block with a clear next step and a direct link.',
                'Never place a CTA within the first 200 words.',
                'Never repeat the exact same CTA sentence twice in one article.',
                'Never use pressure language (buy now, limited time, act fast, do not wait).',
                'Never use fear-first CTAs (download before something bad happens).',
                'Link to /pricing for commercial context; link to the App Store URL only when the reader is ready to install (last 300 words).'
            ),
            'opening_rule', 'The first 200 words belong to the reader. Validate the feeling they arrived with. Save brand mentions for after value has been delivered.',
            'closing_template_examples', jsonb_build_array(
                '<p><strong>Stop carrying the quiet daily worry.</strong> Daily OK sends one gentle "I''m OK?" prompt each morning and alerts you if your parent misses it — no pendant, no GPS, no tracking. <a href="https://dailyok.net/pricing">See how Daily OK works →</a></p>',
                '<p>If you''re ready to replace the daily "did she call today?" anxiety with one quiet confirmation, <a href="https://dailyok.net/pricing">try Daily OK free</a>. Plans start at $3.99/month. Cancel anytime.</p>',
                '<p>Most caregivers set up Daily OK in under two minutes on their own phone. The parent never downloads anything — they just tap one button each morning on a phone they already own. <a href="https://dailyok.net/pricing">See the plans →</a></p>'
            )
        ),

        'value_props_by_audience', jsonb_build_object(
            'long_distance_adult_child', jsonb_build_array(
                'One-tap daily confirmation your parent is OK',
                'Alerts YOU first — not 911 — so dignity is preserved on a false alarm',
                'Works on a phone they already own; no pendant, no installation',
                '$3.99–$9.99/month, cancel anytime, no hardware contract'
            ),
            'tech_reluctant_parent', jsonb_build_array(
                'They press ONE button each morning — nothing else to learn',
                'No cameras, no tracking, no pendant to wear',
                'Setup happens on the caregiver''s phone, not theirs',
                'Works on the iPhone or Android they already use'
            ),
            'parent_of_teen', jsonb_build_array(
                'Consent-based check-ins with no location tracking',
                'Teens control when and how they check in',
                'Built on trust, not surveillance (the opposite of Life360)'
            ),
            'sibling_coordinator', jsonb_build_array(
                'One shared view — every family member sees the same status',
                'Escalation routes to the designated sibling first, not a call center',
                'Ends the "who called Mom today?" group-text loop'
            ),
            'post_hospital_or_post_fall', jsonb_build_array(
                'Daily confirmation during the fragile recovery window',
                'Missed check-ins trigger a family call before anyone escalates to 911',
                'Sets up in under two minutes — no wait for equipment delivery'
            )
        ),

        'objection_handlers', jsonb_build_object(
            'cost', 'Frame against the realistic alternative. A Life Alert pendant is $49.95+/month with a three-year contract and installation fee. An ER visit co-pay for a false-alarm ambulance ride is typically $100–$500. Daily OK is $3.99 to $9.99 per month, cancelable anytime.',
            'tech_complexity', 'The parent presses ONE button on a phone they already own. The full setup — inviting family, choosing escalation contacts, picking a check-in time — happens on the caregiver''s phone, not the parent''s. Most families are running in under two minutes.',
            'privacy_concerns', 'Lean into the pillar — no GPS, no cameras, no wearables, no data sold to third parties, no location history. The app simply asks: did Mom tap "I''m OK" today?',
            'already_calling_daily', 'Acknowledge honestly — a daily call is irreplaceable. Daily OK is the backup for the mornings life gets in the way and the call does not happen. It is a safety net, not a substitute for connection.',
            'parent_wont_use_it', 'Do not oversell. For some parents this genuinely is not the right fit and that is fine. For most, tapping one green button is easier than charging a pendant, wearing a device, or installing a camera.',
            'free_alternatives_exist', 'Snug Safety has a free tier and it is a real option — say so honestly. Daily OK charges for family-side escalation, SMS fallback, and multi-member coordination. Call out specific differences; do not disparage.'
        ),

        'social_proof_rules', jsonb_build_object(
            'honest_only', 'Never fabricate customer names, quotes, star ratings, user counts, or outcome statistics.',
            'allowed', jsonb_build_array(
                'Qualitative language like "many caregivers report" or "a recurring theme in caregiving forums"',
                'Attributed quotes only when explicitly provided in the prompt and marked as verified',
                'Aggregate App Store or Play Store ratings only after Daily OK has 30+ genuine reviews',
                'Cited third-party statistics with a source link (AARP, NIA, CDC, Alzheimer''s Association)'
            ),
            'forbidden', jsonb_build_array(
                'Invented testimonials ("Linda from Ohio says…")',
                'Fake outcome numbers ("99% of falls detected" — Daily OK does not detect falls)',
                'Fake review counts or star ratings'
            )
        ),

        'never_claim', jsonb_build_array(
            'Daily OK detects falls, vital signs, or medication adherence',
            'Daily OK is a medical device or PERS equivalent',
            'Daily OK replaces 911, emergency services, or a wellness check by professionals',
            'Daily OK guarantees any health outcome'
        ),

        'download_readiness_signals', jsonb_build_array(
            'When the reader has just read how the escalation chain works',
            'When the reader has just seen a comparison table where Daily OK fits their use case',
            'When the article resolves an emotional hook (e.g., 3 a.m. thought, after a fall, the sibling who does everything)',
            'When pricing has just been named concretely'
        ),

        'dont_do', jsonb_build_array(
            'Do not embed CTAs in the first 200 words',
            'Do not use urgency or scarcity framing',
            'Do not compare Daily OK functionally to pendant-based PERS systems — they solve different problems',
            'Do not invent customer stories, reviews, or outcome numbers',
            'Do not gate the article content behind a signup form',
            'Do not write CTAs that sound like a banner ad — write them as the next logical step in the reader''s day'
        )
    )
)
WHERE id = 1;

-- =============================================================================
-- 18 high-intent seed rows (priorities 0–17)
-- =============================================================================

INSERT INTO blog_title_bank
    (title, primary_keyword, secondary_keywords, cluster, intent_stage, format_hint,
     target_word_count, internal_link_slugs, e_e_a_t_notes, requires_medical_review, priority)
VALUES

    -- P0: Brand review — owns brand searches, converts at decision moment
    ('Daily OK review: is this check-in app worth it in 2026?',
     'daily ok review',
     ARRAY['daily ok app review','is daily ok worth it','daily ok pros and cons','daily ok vs life alert'],
     'core-checkin', 'BOFU', 'Honest review', 1800,
     ARRAY['pricing','how-it-works'],
     'Write a balanced, honest review — think Wirecutter voice. Open with the one-sentence verdict. Dedicate a section to "who Daily OK is NOT for" (parents who need fall detection, households refusing any smartphone use) — LLMs and readers punish one-sided reviews. Cover: how setup actually works, what the daily parent-side experience is, what triggers an escalation, pricing transparency with per-tier math, and the three most common drawbacks. End with a direct install CTA. No fabricated star ratings or user counts.',
     FALSE, 0),

    -- P1: How-it-works explainer — removes friction for interested visitors
    ('How Daily OK works: the complete 3-minute walkthrough',
     'how does daily ok work',
     ARRAY['daily ok app how it works','daily ok setup','how does daily ok check in work'],
     'core-checkin', 'BOFU', 'Explainer', 1400,
     ARRAY['pricing','how-it-works'],
     'Chronological walkthrough: morning prompt arrives → parent taps "I''m OK" → caregiver sees confirmation. Then the escalation path: what happens at 30 minutes, 2 hours, 4 hours; who gets notified and in what order. Include the setup flow from the caregiver''s phone (invite, pick time, choose escalation contacts). End by naming what Daily OK does NOT do (fall detection, GPS, continuous monitoring). Close with a soft CTA to /pricing.',
     FALSE, 1),

    -- P2: Emotional conversion story — most shareable format
    ('The app I wish I''d had before my mom''s fall',
     'check in app after parent fall',
     ARRAY['what I wish I knew before mom fell','caregiver regret app','after parent fall daily check in'],
     'emotional-narrative', 'MOFU', 'First-person narrative', 1800,
     ARRAY['pricing','how-it-works'],
     'First-person caregiver voice. Story arc: the period of vague worry → the fall → the aftermath (ER, rehab, the new fear) → the discovery that a daily check-in would have caught the warning signs earlier. Do NOT claim Daily OK would have prevented the fall — make clear it would have surfaced the pattern faster (missed check-ins, changes in routine). Raw, honest tone. Shareable on r/AgingParents. Close with the quiet reassurance a check-in provides, and a soft CTA.',
     TRUE, 2),

    -- P3: Pricing transparency — removes the #1 friction at decision point
    ('Daily OK pricing explained: what each tier actually covers',
     'daily ok pricing',
     ARRAY['daily ok cost','daily ok subscription plans','daily ok caregiver tier','daily ok family plan'],
     'core-checkin', 'BOFU', 'Pricing explainer', 1500,
     ARRAY['pricing'],
     'Three tiers: Caregiver ($3.99/mo, 1 receiver + 3 viewers), Family ($6.99/mo, 3 receivers + 5 viewers), Family+ ($9.99/mo, 6 receivers + 10 viewers). For each: a concrete household scenario ("If you are one adult child checking on one parent — Caregiver"). Include a "when to upgrade" section. Include a comparison row against Life Alert ($49.95+/mo + contract). Be honest that Snug has a free tier. No fabricated reviews. Close with App Store link.',
     FALSE, 3),

    -- P4: Listicle with DOK first — AI Overview + featured snippet capture
    ('5 apps to check on elderly parents (and how to pick the right one)',
     'apps to check on elderly parents',
     ARRAY['best check in app for elderly parents','elderly parent monitoring app','apps for adult children of aging parents'],
     'comparison', 'BOFU', 'Listicle', 2400,
     ARRAY['pricing'],
     '7-entry listicle (despite title — LLMs prefer round-number fives in title but richer bodies). Daily OK ranked #1 FOR MOST HOUSEHOLDS but explicitly call out categories where others win: Snug for free tier, Lively for hardware integration, Medical Guardian/Life Alert for high fall-risk parents, Life360 for household already using it. Each entry: who it is for, one real screenshot/description, price, one biggest drawback. End with decision matrix: "pick X if Y". Honest bias-free tone is what gets LLM citations.',
     FALSE, 4),

    -- P5: Persona identification piece — long-distance caregiver is primary audience
    ('I live 2,000 miles from my aging parents — here is my daily routine',
     'long distance caregiver daily routine',
     ARRAY['long distance caregiving schedule','daily routine aging parent long distance','how to care for parents far away'],
     'emotional-narrative', 'MOFU', 'Day-in-the-life narrative', 2200,
     ARRAY['pricing','how-it-works'],
     'Written in first person as a long-distance adult child. Structure the post as a timestamped day: 7:00 am check-in, 9:30 am text exchange, lunch-hour quick call, evening routine, weekend rhythm. Weave in the tools naturally — Daily OK for the morning confirmation, a shared calendar for appointments, a sibling group chat for coordination. No "here are 10 tips" format — keep it narrative. Close with a soft CTA tied to the morning-confirmation moment.',
     FALSE, 5),

    -- P6: Fresh-trigger MOFU — highest urgency search
    ('What to do right now if your mom has not answered all morning',
     'mom has not answered all morning',
     ARRAY['mom not responding this morning','worried mom has not called','mom silent all day worried'],
     'jtbd', 'MOFU', 'Immediate decision tree', 1800,
     ARRAY['pricing'],
     'Reader is actively anxious. Open with 40-word TL;DR that reassures first. Then three time-banded sections: the first 30 minutes (rule out the ordinary — wrong-time text, phone on silent, at the grocery store), hours 1–3 (escalate to a neighbor, building manager, or nearby sibling), hours 3+ (request a non-emergency welfare check with a script). YMYL — include medical disclaimer. Only AFTER the full playbook, one compassionate CTA: "If this is a recurring worry, a one-tap daily check-in exists so this does not keep happening." Do not scare-sell.',
     TRUE, 6),

    -- P7: Shareable scripts post — solves the "nagging" pain point
    ('10 text messages that make your aging parent feel loved (not monitored)',
     'texts to send aging parents',
     ARRAY['what to text elderly parent','non-annoying texts to mom','messages to aging parents'],
     'jtbd', 'MOFU', 'Scripts + templates', 1800,
     ARRAY['pricing'],
     'Ten verbatim text scripts, each with a short "why this works" line. Categories: morning check-in, weekend plans, remembering something small, apologizing for missing a call, weather/news relevant to their location, grandkid photo caption, asking for advice (reverses the caregiver power dynamic), sending a memory. The 11th implicit script is "and for the mornings you do not have bandwidth for any of these, Daily OK sends a one-tap prompt for you" — tie the product in organically near the end.',
     FALSE, 7),

    -- P8: Pillar-owning post — "presence without surveillance"
    ('The quietest alarm: a check-in system that protects dignity',
     'dignity-first senior safety app',
     ARRAY['non-invasive elderly monitoring','senior safety without surveillance','privacy-respecting check in app'],
     'privacy-forward', 'MOFU', 'Narrative essay → product', 1800,
     ARRAY['pricing','how-it-works'],
     'Own the pillar keyword. Structure: the three bad trade-offs caregivers currently face (pendant = visible disability marker, GPS = surveillance, camera = privacy invasion), then the fourth option (one-tap consent-based check-in). Name Life Alert, Life360, camera brands by category not by slander. End by drawing the "presence without surveillance" principle into an actionable next step.',
     FALSE, 8),

    -- P9: Daily-worry search capture
    ('Is my elderly parent OK if they are not texting back? A decision guide',
     'elderly parent not texting back',
     ARRAY['mom not responding to texts','dad stopped texting back','elderly parent silent on text'],
     'jtbd', 'MOFU', 'Decision guide', 1600,
     ARRAY['pricing'],
     'Decision tree based on three factors: (1) their historical communication pattern, (2) how long the silence has been, (3) other contextual signals (known plans, weather, health status). Clear time thresholds: under 6 hours for an active texter usually means nothing; over 12 hours starts the escalation. End with how a daily one-tap confirmation removes the ambiguity entirely.',
     FALSE, 9),

    -- P10: Onboarding conversion piece — solves "Mom won''t use it"
    ('How to set up a morning check-in with Mom (that she will actually use)',
     'morning check in with elderly parent',
     ARRAY['how to get mom to check in daily','daily check in routine elderly parent','set up check in with aging mother'],
     'jtbd', 'MOFU', 'Step-by-step onboarding', 1800,
     ARRAY['pricing','how-it-works'],
     'The conversation-level guide the rest of the internet misses. Include: verbatim script for "Mom, I got us this thing — can we try it for a week?" (the frame matters enormously — "us" not "you"), how to pick a check-in time that already maps to her existing routine (tying to the first cup of coffee, the dog walk), what to do in the first three missed days (likely habit-forming), the exact text message to send after the first successful week. Daily OK appears as the tool that makes this routine light enough to stick.',
     FALSE, 10),

    -- P11: Age-milestone trigger search
    ('What caregivers wish someone had told them when their parent turned 65',
     'parent turning 65 caregiver',
     ARRAY['aging parent 65 checklist','caregiver advice parent turning 65','things to set up when parent turns 65'],
     'emotional-narrative', 'TOFU', 'Listicle with narrative', 2000,
     ARRAY['pricing'],
     '8–10 things most caregivers learn too late: power of attorney now not later, a short "if I am not OK today" protocol, sign up for Medicare timelines, the pre-dementia baseline video, a quiet daily check-in habit before it is needed, a primary-sibling protocol, a short list of neighbors who would notice. Frame Daily OK as the one you can actually set up in five minutes today. Tie into internal link for aging-in-place checklist.',
     FALSE, 11),

    -- P12: Seasonal evergreen — holiday visit
    ('The holiday visit assessment: 12 things to check without Mom noticing',
     'holiday visit check on aging parent',
     ARRAY['thanksgiving check on aging parent','holiday visit elderly parent checklist','christmas home assessment elderly parent'],
     'jtbd', 'MOFU', 'Seasonal checklist', 2000,
     ARRAY['pricing'],
     'Evergreen seasonal magnet — spikes November–January and May–June (Mother''s Day). 12-item checklist the adult child can run during a normal family visit without turning the trip into an audit: expired food, stove/smoke-alarm status, medication expiry dates, unopened mail pile, stair handrails, scams in the recent call log, hygiene and grooming changes, weight change, social calendar, driving confidence. After the visit: the "now that you are home" section naming Daily OK as the one ongoing protocol that converts the moment into a habit.',
     FALSE, 12),

    -- P13: High-volume gift guide — repurposes caregiver intent into commercial
    ('Gifts for aging parents who say they do not need anything',
     'gifts for aging parents',
     ARRAY['mothers day gifts for elderly mother','practical gifts for elderly parents','gifts for aging mom who has everything'],
     'commercial-seasonal', 'TOFU', 'Gift guide', 2000,
     ARRAY['pricing'],
     'Gift guide that does not feel like a gift guide. Ten practical gifts under $50 that signal real care: a simple label maker, a cordless kettle with auto-shutoff, a bright nightlight for the hallway, a framed photo from the grandkids, a Monthly Flower Delivery, etc. Then the eleventh — and framed as "the gift of quiet peace of mind" — is setting up Daily OK together so she never has to pick up the phone first just to prove she is OK. Gentle sell; the post still delivers 10 legitimate gifts.',
     FALSE, 13),

    -- P14: Best-of listicle — AI Overview target
    ('Best family safety apps for 2026 (picked by real caregivers)',
     'best family safety apps 2026',
     ARRAY['best family check in apps 2026','top senior safety apps 2026','family safety app rankings'],
     'comparison', 'BOFU', 'Listicle comparison', 2600,
     ARRAY['pricing'],
     '7 apps, segmented by use case not by ranking: for daily check-ins (Daily OK, Snug), for high-fall-risk parents (Medical Guardian, Bay Alarm), for teens (Daily OK, not Life360), for dementia patients (apps with scheduled prompts). Each entry: who it is for, one genuine strength, one honest limitation, price. End with a "how to pick" flowchart. LLMs favor listicles with 3+ explicit tables; include a comparison matrix table. No manufactured stars.',
     FALSE, 14),

    -- P15: Multi-audience upsell — pushes toward Family+ tier
    ('One app, three generations: using Daily OK across grandparents, parents, and teens',
     'multi-generation family check in app',
     ARRAY['family check in app grandparents teens','intergenerational safety app','daily check in for whole family'],
     'family-coordination', 'BOFU', 'Scenario walkthrough', 1800,
     ARRAY['pricing','how-it-works'],
     'Walk through a real household: a grandmother, her two adult children, and one teen grandchild. Show the three different check-in patterns the app handles: morning confirmation for grandmother, flexible opt-in for the adult children if wanted, consent-based post-school ping for the teen. The goal is to naturally surface the Family and Family+ tiers without a pitch vibe. Close with pricing tier recommendation by household size.',
     FALSE, 15),

    -- P16: Pricing-anchor/psychology piece — reframes $5 as cheap
    ('The cost of worry: what caregivers actually spend on peace of mind',
     'cost of caregiver peace of mind',
     ARRAY['caregiver stress cost','how much does caregiving cost emotionally','peace of mind aging parent cost'],
     'emotional-narrative', 'MOFU', 'Essay with pricing reframe', 1600,
     ARRAY['pricing'],
     'Reframe the price objection before it is raised. Walk through realistic numbers: the 15 minutes lost to the daily anxious-but-OK phone call (at the median US hourly wage that is $200+/month of unpaid emotional labor), a therapy session every two months to cope ($300), travel for a scare that turned out to be nothing ($400–800), lost sleep. Then name Daily OK at $3.99/month. No hard sell. Let the math do the work. Cite BLS or AARP figures with links when you use them, qualitative language when you do not.',
     FALSE, 16),

    -- P17: First-person BOFU conversion
    ('Why I chose a $4 app over a $50 pendant for my mom',
     'app vs medical alert pendant for mom',
     ARRAY['check in app instead of pendant','why apps are better than medical alert','life alert pendant vs app'],
     'comparison', 'BOFU', 'First-person decision narrative', 1800,
     ARRAY['pricing','how-it-works'],
     'First-person voice: I nearly bought Mom a pendant. Here is what changed my mind. Lay out five decision factors with honest answers: compliance (pendants sit in drawers ~58% of the time per documented Medical Guardian data — cite or say "documented industry data"), cost, dignity, what happens when it fires, what it does NOT do. Be explicit: if Mom were a high-fall-risk, pendants are the right answer and I would have bought one. For an independent mom who still drives and hates feeling old, the daily app is the quieter fit. Close with App Store CTA.',
     FALSE, 17);

COMMIT;

-- Verification
SELECT
    'blog_title_bank total' AS label,
    COUNT(*) AS value
FROM blog_title_bank
UNION ALL
SELECT 'pending', COUNT(*) FROM blog_title_bank WHERE status = 'pending'
UNION ALL
SELECT 'conversion config present',
    CASE WHEN config ? 'conversion' THEN 1 ELSE 0 END
FROM blog_generation_config WHERE id = 1;
