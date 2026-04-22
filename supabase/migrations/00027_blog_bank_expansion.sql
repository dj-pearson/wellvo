-- Daily OK Blog — Second Wave of Title Bank Rows
-- Migration: 00027_blog_bank_expansion
--
-- Adds 20 new blog_title_bank rows at priorities 31–50, filling the gaps in
-- the existing bank: condition-specific posts (Parkinson's, post-stroke),
-- life-transition triggers (hospital discharge, widowed parent, retirement),
-- seasonal safety (heat wave, power outage, snowbird), family coordination
-- (grandkids, tough conversations), and senior-tech onboarding (iPhone setup).
--
-- Each row emphasizes a specific triggering moment — the instant someone types
-- the query — so the generator can open with genuine validation of the reader's
-- state rather than pivoting to product too fast. Conversion moments (where
-- Daily OK naturally enters the narrative) are called out in e_e_a_t_notes.

BEGIN;

INSERT INTO blog_title_bank
    (title, primary_keyword, secondary_keywords, cluster, intent_stage, format_hint,
     target_word_count, internal_link_slugs, e_e_a_t_notes, requires_medical_review, priority)
VALUES

    -- P31: Year-tagged listicle — AI Overview + featured-snippet target
    ('The 10 best apps for elderly parents in 2026 (what actually works)',
     'best apps for elderly parents 2026',
     ARRAY['top rated apps for elderly parents','senior parent apps 2026','apps for adult children of aging parents'],
     'comparison', 'BOFU', 'Listicle roundup', 2600,
     ARRAY['pricing','how-it-works'],
     'Broader than the existing "best check-in apps" listicle — cover 10 apps across check-in, medication, transportation, telehealth, communication. Daily OK appears as the check-in pillar alongside a named med-reminder app, a telehealth app, a grocery-delivery app, etc. Each entry: who it is for, one real strength, one honest limitation, price. End with a decision matrix. Include comparison table. No manufactured star ratings.',
     FALSE, 31),

    -- P32: Major decision piece — DOK positions as "the interim" before a move
    ('When is it time to move Mom to assisted living? A clear-eyed framework',
     'when to move elderly parent to assisted living',
     ARRAY['should mom move to assisted living','signs mom needs assisted living','how to know when to move parent'],
     'problem-aware', 'TOFU', 'Decision framework', 2400,
     ARRAY['pricing'],
     'High-stakes decision piece. Lead with validation that this question is hard, not solvable by checklist alone. Include an honest 10-factor framework: ADL independence, medication management, fall history, social isolation, cognitive signs, financial sustainability, caregiver bandwidth. Position Daily OK as the honest MIDDLE option — the thing that often buys 6–24 more months of independence before a move is truly necessary. Cite AARP and Alzheimer''s Association data. Do not pretend Daily OK replaces assisted living when it''s truly needed.',
     TRUE, 32),

    -- P33: Complementary-app listicle — no cannibalization, high intent
    ('Medication reminder apps for elderly parents: the 5 that actually work',
     'medication reminder app for elderly',
     ARRAY['best medication reminder app seniors','pill reminder app elderly parent','apps to help elderly remember medications'],
     'comparison', 'BOFU', 'Listicle comparison', 2000,
     ARRAY['pricing','how-it-works'],
     'Complementary to Daily OK (not a competitor). Roundup of 5 med-reminder apps (Medisafe, MyTherapy, Pill Reminder, Round Health, Mango Health) with honest pros/cons. Daily OK appears near the end as the "but what if they miss the reminder and no one knows?" piece. Framework: med apps remind; Daily OK alerts family when something is off. No claim that Daily OK tracks medication.',
     FALSE, 33),

    -- P34: Voice-assistant comparison — popular adjacent category
    ('Alexa vs a daily check-in app for elderly parents: an honest comparison',
     'alexa for elderly parents check in',
     ARRAY['alexa drop in elderly parent','voice assistant senior safety','amazon echo for aging parents'],
     'comparison', 'BOFU', 'Head-to-head comparison', 2000,
     ARRAY['pricing','how-it-works'],
     'Name specific Alexa features (Drop-In, Care Hub, routines). Walk through a day with each: Alexa = voice-initiated, requires parent awareness and intentional action; Daily OK = structured one-tap daily confirmation with automatic family escalation. Be honest: Alexa is better for hands-free communication, weather, music, reminders. Daily OK is better for the "did they check in today?" question. Many caregivers use both. End with practical "use both like this" guidance.',
     FALSE, 34),

    -- P35: Trigger event — hospital discharge, 30-day window
    ('What to set up after your parent''s hospital discharge (the first 30 days)',
     'after hospital discharge elderly parent',
     ARRAY['hospital to home elderly parent','post hospital care elderly','discharge planning aging parent'],
     'safety-emergency', 'MOFU', 'Playbook by week', 2400,
     ARRAY['pricing','how-it-works'],
     'Trigger-event playbook. Structure: Day 1 (discharge day setup), Week 1 (medication, follow-up appointments, home safety), Weeks 2–4 (recovery milestones, red flags). Include CDC STEADI fall-prevention pointers. YMYL — medical disclaimer. Daily OK enters as "the light-touch daily check-in during the fragile window when they''re home but not fully themselves yet." Cite discharge planning resources from AARP or a named hospital system if possible.',
     TRUE, 35),

    -- P36: High-volume dementia signal search
    ('Mom''s memory is slipping: is it normal aging or early dementia?',
     'mom memory getting worse',
     ARRAY['is mom getting dementia','signs early dementia mother','mild cognitive impairment vs dementia'],
     'dementia', 'TOFU', 'Medically reviewed explainer', 2200,
     ARRAY['pricing'],
     'YMYL. Cite Alzheimer''s Association 10 warning signs of Alzheimer''s and NIA normal-aging-vs-MCI-vs-dementia framing. Three columns: normal aging, mild cognitive impairment, early dementia — with concrete examples in each column. Clear disclaimer: Daily OK is not a diagnostic tool. Where Daily OK fits: baseline pattern-tracking. Over weeks, missed check-ins or changes in check-in time can surface a pattern that helps you (and her doctor) notice change earlier. Do not overclaim.',
     TRUE, 36),

    -- P37: Safety authority piece — CDC-backed
    ('Senior fall prevention checklist: 15 things to fix in your parent''s home today',
     'senior fall prevention home',
     ARRAY['elderly fall prevention checklist','aging parent home safety','fall risk assessment home'],
     'safety-emergency', 'TOFU', 'Downloadable checklist', 2200,
     ARRAY['pricing'],
     'Room-by-room — bathroom (grab bars, non-slip mats), stairs (handrails), bedroom (nightlight path), living room (cords, rugs), kitchen (reachable items). Cite CDC STEADI. Include printable PDF CTA. Daily OK appears in the "and if they do fall" section as the family-first alert chain — honest that it is not a fall-detection device. Escalation chain catches missed check-ins that could indicate an injury.',
     TRUE, 37),

    -- P38: Loneliness epidemic — high emotional valence, highly shareable
    ('Signs your aging parent is lonely (and the check-ins that actually reach them)',
     'signs aging parent lonely',
     ARRAY['elderly loneliness signs','lonely aging mother','social isolation older adults'],
     'emotional-narrative', 'TOFU', 'Symptom + solution narrative', 2000,
     ARRAY['pricing'],
     'Cite the CDC / Surgeon General loneliness framing and NIA data on social isolation health risks. Eight signs: declining hygiene, withdrawn communication, over-calling or zero calling, appetite changes, reduced social calendar, excessive TV, clutter accumulation, bringing up the past constantly. For each sign: what you can do this week. Daily OK''s role: the structured daily touch point that feels like being thought of, without being a surveillance mechanism.',
     FALSE, 38),

    -- P39: Grief + safety in the critical 6 months
    ('The first 6 months after Mom lost Dad: a widowed parent checklist',
     'widowed parent checklist',
     ARRAY['newly widowed mother care','widowed elderly parent help','after spouse dies elderly parent'],
     'emotional-narrative', 'MOFU', 'Grief-aware checklist', 2200,
     ARRAY['pricing'],
     'The widowhood effect is real — elevated mortality risk for 6–12 months after losing a spouse. Cite academic sources (study: Rees and Lutkins, or more recent follow-ups). Grief-aware tone, not checklist-tone. Cover: grief counseling resources, medication management when the other spouse was the tracker, finances, driving reassessment, and daily social contact. Daily OK as the quiet morning presence that bridges the sudden silence of the empty house.',
     TRUE, 39),

    -- P40: Trigger event — post-stroke 30 days
    ('Post-stroke recovery at home: a caregiver''s first 30 days',
     'post stroke home recovery caregiver',
     ARRAY['stroke recovery at home','caregiving after stroke','first days home after stroke'],
     'safety-emergency', 'MOFU', 'Week-by-week playbook', 2400,
     ARRAY['pricing','how-it-works'],
     'YMYL. Structure: Days 1–3 (homecoming, medication reconciliation, mobility), Week 1 (therapy routines, warning signs of second stroke — BE FAST acronym), Weeks 2–4 (rebuilding routines, caregiver pacing). Cite American Stroke Association. Daily OK as the check-in during recovery — when simple confirmation that "they got out of bed today" is meaningful. Never claim detection of medical events; only the missed-check-in alert chain.',
     TRUE, 40),

    -- P41: Parkinson''s — condition-specific MOFU
    ('Daily check-ins for parents with Parkinson''s: what caregivers need to know',
     'parkinsons caregiver daily routine',
     ARRAY['apps for parkinsons patients','parkinsons home care routine','check in on parent with parkinsons'],
     'dementia', 'MOFU', 'Expert-reviewed feature', 2000,
     ARRAY['pricing'],
     'Parkinson''s brings specific daily challenges: medication timing windows, tremor-related phone difficulty, off-period risks. Cite Michael J. Fox Foundation or Parkinson''s Foundation. Daily OK angle: large one-tap button works even with tremors; missed check-in timing can surface medication-schedule drift. YMYL — clear disclaimer.',
     TRUE, 41),

    -- P42: Scripts-heavy MOFU — shareable
    ('The 3 conversations every adult child dreads (and verbatim scripts for each)',
     'tough conversations aging parents',
     ARRAY['how to talk to aging parent about driving','how to talk to parent about moving','talking to parent about money'],
     'problem-aware', 'MOFU', 'Scripts + framework', 2400,
     ARRAY['pricing'],
     'The three: giving up driving, moving out of the family home, handing over financial decisions. For each: why it is hard, when to have it, the opening line that works, two scripts (the direct ask + the compromise). Daily OK enters in the "compromise" column for two of the three — "we''ll keep the current setup, but add a daily check-in so I can sleep at night" is a genuine win-win. Validate the dread. Do not oversell the app.',
     FALSE, 42),

    -- P43: Caregiver self-care — retention + brand loyalty
    ('Caregiver burnout: when the daily worry stops being manageable',
     'caregiver burnout signs',
     ARRAY['caregiver stress symptoms','burned out caregiver elderly parent','how to avoid caregiver burnout'],
     'emotional-narrative', 'TOFU', 'Essay + self-care framework', 1800,
     ARRAY['pricing'],
     'Cite AARP/NAC caregiver stats (61% of caregivers are also working, 40% report high emotional stress). Seven signs: irritability, sleep disruption, resentment, declining personal health, withdrawing from friends, constant background worry, catastrophizing. For each: one concrete counter-move. Daily OK''s role: reduces the cognitive load of "did she call today?" by replacing it with a simple structured confirmation. Self-care framing, not product-first.',
     FALSE, 43),

    -- P44: Senior-tech onboarding — high intent, value-dense
    ('Setting up an iPhone for an elderly parent: the 20-minute first-day guide',
     'iphone setup for elderly parent',
     ARRAY['iphone for elderly parent','setting up phone for senior','simplifying iphone for elderly'],
     'senior-tech-ux', 'TOFU', 'Step-by-step tutorial', 2200,
     ARRAY['pricing','how-it-works'],
     'Concrete walkthrough: Display & Text Size (to Larger), Accessibility (VoiceOver basics, button shapes, reduce motion), emergency contacts, Medical ID in Health app, one-screen home layout with 6–8 essential apps, Face ID or passcode choice, RELIABLE photos app setup. Daily OK appears as one of the essential 6–8 apps with setup instructions specific to the caregiver-managed pattern. Practical, no filler. Printable.',
     FALSE, 44),

    -- P45: Family-coordination TOFU upsell to Family/Family+ tier
    ('Getting grandkids involved: how kids can help check on Grandma',
     'grandchildren check on grandparents',
     ARRAY['grandkids help with grandma','teaching kids to call grandparents','intergenerational family care'],
     'family-coordination', 'TOFU', 'Age-banded ideas', 1800,
     ARRAY['pricing','how-it-works'],
     'Cute-dangerous topic — keep it genuinely practical, not saccharine. Age bands: 6–9 (drawings in the mail, short video calls), 10–13 (weekly text check-ins, shared hobby like puzzles), 14–17 (tech help, real conversations, picking up errands). Daily OK angle: the app''s shared viewer tier means one grandchild can see morning check-ins too — being included, without being the primary alert contact. Natural upsell to Family or Family+ tier.',
     FALSE, 45),

    -- P46: Life transition — retirement, worry about dads
    ('My dad just retired — and I''m worried about him. Now what?',
     'worried about retired father',
     ARRAY['dad retired depressed','father struggling after retirement','retired dad isolated'],
     'emotional-narrative', 'TOFU', 'First-person narrative', 1800,
     ARRAY['pricing'],
     'Men''s post-retirement depression and identity shift are under-discussed. Cite studies on increased mortality risk and depression rates 1–2 years post-retirement in men. First-person voice: what I noticed, what I tried, what actually helped. Daily OK enters as the light-touch daily contact that says "I''m thinking about you" without being heavy-handed. Do not pathologize retirement; normalize the adjustment.',
     FALSE, 46),

    -- P47: Mental health in aging men — YMYL but underserved
    ('When Dad withdraws: spotting depression in aging men',
     'elderly father depression signs',
     ARRAY['depression in older men','aging father isolated','elderly dad depressed signs'],
     'emotional-narrative', 'TOFU', 'Symptom guide + action', 2000,
     ARRAY['pricing'],
     'YMYL. Cite NIA and APA data on older men''s depression (often undiagnosed, higher suicide risk in men 75+). Six signs specific to men: loss of interest in longtime hobbies, irritability masking sadness, physical complaints without medical cause, alcohol increase, withdrawal from longtime friends. Concrete actions: how to ask the direct question, resources like 988 Suicide & Crisis Lifeline. Daily OK''s role: the structured touchpoint that is easier for him than initiating calls himself.',
     TRUE, 47),

    -- P48: Seasonal — heat wave
    ('Checking on elderly parents during a heat wave: the summer safety playbook',
     'elderly heat wave safety',
     ARRAY['elderly heat stroke prevention','hot weather safety seniors','elderly parent hot weather check'],
     'safety-emergency', 'MOFU', 'Seasonal playbook', 1800,
     ARRAY['pricing'],
     'Evergreen summer spike. Cite CDC heat-related illness data for adults 65+. Warning signs of heat exhaustion vs heat stroke (YMYL — this matters). Action items: AC access, hydration reminders, cooling centers (211 line), medication considerations (diuretics, beta blockers interact with heat). Daily OK as the morning confirmation during the worst stretches — a missed check-in on a 100°F day matters more than a missed check-in on a normal day.',
     TRUE, 48),

    -- P49: Seasonal — power outage
    ('Power outage preparedness for elderly parents living alone',
     'elderly parent power outage',
     ARRAY['senior power outage kit','elderly parent storm prep','power loss aging parent'],
     'safety-emergency', 'MOFU', 'Checklist + kit', 1800,
     ARRAY['pricing'],
     'Storm season evergreen. Checklist: flashlights (not candles), battery bank for phone, cordless phone backup plan, medication refrigeration plan, heating/cooling alternatives, food shelf stability, neighbor buddy system. Daily OK angle: the cellular-network check-in still works when home WiFi is out, so the family still gets a confirmation — or the silence they need to know to act on.',
     FALSE, 49),

    -- P50: Niche high-intent — snowbird parents
    ('Keeping tabs on snowbird parents: daily check-ins across state lines',
     'snowbird parent check in',
     ARRAY['check on snowbird elderly parent','parents who winter in florida','long distance snowbird family'],
     'jtbd', 'MOFU', 'Scenario-based how-to', 1600,
     ARRAY['pricing','how-it-works'],
     'Specific to the snowbird scenario — parents who winter 1,000+ miles from their adult children. Challenges: distance from their usual healthcare team, new social isolation in a seasonal community, adjustments to medication access. Daily OK as the consistent thread across locations — the app doesn''t care whether they''re in Michigan or Florida. Emphasize low setup burden. Gentle close.',
     FALSE, 50);

COMMIT;

-- Verification
SELECT
    'new rows inserted' AS label,
    COUNT(*) AS value
FROM blog_title_bank
WHERE priority BETWEEN 31 AND 50
UNION ALL
SELECT 'total rows in bank', COUNT(*) FROM blog_title_bank
UNION ALL
SELECT 'pending', COUNT(*) FROM blog_title_bank WHERE status = 'pending';
