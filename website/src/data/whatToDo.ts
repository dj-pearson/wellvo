/** Content model for the /what-to-do/* "doesn't answer the phone" pages
 *  (US-WEB005, pSEO Template #3). One entry = one page. Bodies are
 *  hand-differentiated per relationship because the right advice for a
 *  dementia parent, a teenager, a college student and a spouse genuinely
 *  differ — near-duplicate pages are pSEO.md's #1 flagged risk.
 *
 *  YMYL note: this is health-adjacent content. Until a licensed clinician
 *  (LCSW) is contracted (pSEO.md §7 operational task) the byline must NOT
 *  imply medical credentials — it is rendered as "Daily OK Editorial Team".
 *  The shared layout also renders a not-medical-advice disclaimer.
 */

export interface WhatToDoFaq {
  q: string
  a: string
}

/**
 * A relationship-specific section absorbed from a page consolidated into this
 * one (US-WEB013). Five pages answering "my elderly parent isn't picking up"
 * were one query intent to Google, which selected one and filtered the rest —
 * 9 of 12 guides earned zero impressions in four months. Consolidating means
 * the advice that genuinely differed by relationship has to survive as a
 * section on the page that remains, not be deleted with the URL.
 */
export interface WhatToDoVariant {
  /** e.g. "If it's your mother" */
  heading: string
  /** What actually differs for this relationship. */
  body: string
  /** Relationship-specific steps worth keeping from the merged page. */
  points?: string[]
}

export interface WhatToDoPage {
  slug: string
  /** Short relationship label used in copy, e.g. "your mom". */
  who: string
  title: string
  metaDescription: string
  h1: string
  /**
   * 40–60 words, phrased to stand alone (US-WEB014). These pages rank around
   * position 8.6 but converted 333 impressions into 1 click: at that position
   * the result sits below an AI Overview and a People Also Ask block, which
   * absorb the answer. This paragraph is written to BE the quoted answer, and
   * to say something the summary above it will not — the concrete first move.
   */
  directAnswer: string
  /** ~100–140 word empathetic, non-scaremongering opener. */
  intro: string
  /** Why the situation is relation-specific (unique framing). */
  context: string
  /** First 30 minutes — calm, ordered, relation-specific. */
  first30: string[]
  /** First 24 hours — escalation, relation-specific. */
  first24: string[]
  /** Relation-specific criteria for escalating to a welfare check / 911. */
  escalateWhen: string[]
  /** Unique prevention paragraph mapping Daily OK to this relationship. */
  prevention: string
  /**
   * Sections absorbed from pages consolidated into this one (US-WEB013).
   * Absent on guides that were never consolidated into.
   */
  variants?: WhatToDoVariant[]
  faqs: WhatToDoFaq[]
}

export const LAST_UPDATED = '2026-08-29'

export const whatToDoPages: WhatToDoPage[] = [
  {
    slug: 'elderly-father-not-answering-phone',
    who: 'your elderly parent',
    title:
      "Elderly Parent Not Answering: The First 30 Minutes",
    metaDescription:
      "An ordered plan for the first 30 minutes and the first 24 hours, the point at which silence justifies escalating, and the exact words to use when requesting a police welfare check.",
    h1: "What to do when an elderly parent doesn't answer the phone",
    directAnswer:
      "Call twice, then text. Note whether it rang out or went straight to voicemail — that tells you whether the phone is off or simply out of reach. Message anyone who lives nearby and ask them to knock. If an hour passes and the silence is unusual for them, request a police welfare check rather than waiting out the day.",
    intro:
      "An elderly father who isn't answering deserves a measured, slightly faster response than a younger relative — not because panic helps, but because the realistic risks are higher and verification is cheap relative to the cost of being wrong. Work the steps in order and you'll reach a confident answer quickly.",
    context:
      "Elderly fathers combine two patterns that make phone silence ambiguous: age-related fall and cardiac risk, and a common reluctance to carry or answer a phone. Together they argue for a lower threshold to get someone physically to him and for a passive daily check-in he doesn't have to actively manage.",
    first30: [
      'Call again, text simply, and try any fixed-location device he uses.',
      'Distinguish straight-to-voicemail (phone off/dead — very common for him) from ringing out.',
      'Recall routine: yard, garage, workshop, a drive, a nap, deep sleep, or hearing aids removed.',
      'Contact a neighbor or nearby family right away — for an elderly parent, get to a real person fast.',
      'Call any scheduled aide, home service, or friend who sees him regularly.',
    ],
    first24: [
      'If you cannot confirm safety within ~30 minutes, prioritize this above a normal missed call.',
      'Get someone to the door to physically verify.',
      'If no one can go soon, request a welfare check rather than waiting out the day.',
      'Keep his address, conditions, and a recent photo to hand for responders.',
    ],
    escalateWhen: [
      'Known fall, cardiac, or other risk plus out-of-character silence — escalate early.',
      'A missed medication, meal, or expected caregiver contact.',
      'A neighbor notices uncollected mail, unchanged curtains, or no answer at a door with the car home.',
    ],
    prevention:
      "Because an elderly father is often both higher-risk and harder to reach by phone, the silence problem is acute. Daily OK replaces the fragile daily call with one tap he controls; miss it and you and your siblings are alerted automatically. It preserves the independence he values while giving you a reliable daily signal you currently lack.",
    variants: [
      {
        heading: "If it's your mother",
        body:
          "Mothers are more likely than fathers to have a dense, predictable weekly routine — a standing hair appointment, church, a class, a friend she drives — and more likely to carry the phone but not hear it. That makes a deviation from her baseline a stronger signal than the clock: several hours of silence from someone who normally replies within one is more concerning than a whole afternoon from someone who routinely misses calls.",
        points: [
          'If she uses a tablet or a smart speaker for family video calls, try that — many older parents answer a screen they can see before a phone in another room.',
          'Check whether the call went straight to voicemail (phone off or uncharged, very common) or rang out (phone away from her). They mean different things.',
          'Run through today specifically: an appointment, a day programme, a nap, deep sleep, or hearing aids taken out.',
        ],
      },
      {
        heading: "If it's your father",
        body:
          "Fathers are more often under-connected: less likely to text back, more likely to leave the phone on a charger in another room, and less likely to have mentioned where they were going. A single missed call is therefore a weak signal on its own — but that same weakness is why the silence is so hard to read, and why a daily check-in helps more here than anywhere else.",
        points: [
          'Send a short text with a low bar to clear: "Just checking you\'re OK, text back."',
          'Think about the garage, the yard, a workshop, golf, a drive, a nap, or a TV turned up loud before assuming the worst.',
        ],
      },
      {
        heading: 'If they live alone',
        body:
          'Living alone removes the built-in safety net of another person in the house, so the threshold to physically confirm safety should be lower than for almost any other relationship. Remote attempts should give way to an in-person check sooner — one neighbour knocking on the door is worth more than another hour of calling.',
        points: [
          'Try a landline or any device that stays in a fixed place in the house.',
          'Go to a nearby person earlier than you otherwise would: a neighbour, a building manager, a friend on the same street.',
        ],
      },
    ],
    faqs: [
      { q: 'Is a quicker response justified for an elderly father?', a: 'Generally yes. The combination of higher medical risk and a tendency not to answer means verifying in person sooner is sensible. Matching urgency to risk is not overreacting.' },
      { q: '911 or welfare check?', a: 'Immediate-danger signal (he sounded unwell then went silent) → 911. Worried without a specific emergency indicator and nobody can get there → non-emergency police welfare check.' },
      { q: 'How do I request a welfare check?', a: "Call the police non-emergency number where he lives, request a welfare check, and give his address, age, health conditions, a description, your relationship, and the time of last contact." },
      { q: 'He refuses to keep his phone on him — is the silence meaningful?', a: 'On its own it is weak, but with an elderly parent the safe move is to verify, not assume. A daily check-in is the real solution because it does not rely on him answering a phone at all.' },
      { q: 'No nearby contacts and I am far away — what can I do?', a: 'Request a non-emergency welfare check from anywhere; it is an appropriate step for an elderly parent you cannot otherwise reach. A daily check-in prevents the recurrence.' },
    ],
  },
  {
    slug: 'grandpa-wont-pick-up',
    who: 'your grandparent',
    title:
      "Grandparent Won't Pick Up: The First 30 Minutes",
    metaDescription:
      "What to do first when a grandparent isn't answering, who to contact before escalating, when silence justifies a welfare check, and exactly what to say when you call.",
    h1: "What to do when a grandparent won't pick up the phone",
    directAnswer:
      "Call again and send a text, then message whoever coordinates their care — a parent, an aunt, an uncle. They often already know why the phone is unanswered. If nobody can reach them and nobody can call in, phone the non-emergency police line for their area and request a welfare check.",
    intro:
      "Grandpa not answering can be unsettling precisely because you may not have his routine or medical details at your fingertips. The plan below moves you through verification quickly and tells you when to bring in whoever coordinates his care, so the family acts as one.",
    context:
      "As with grandmothers, the complication is often coordination rather than the steps themselves: you may not be the primary contact and may lack his information. Many older men also under-answer phones, making a single missed call a weak signal and a shared daily check-in particularly valuable.",
    first30: [
      'Call again and text; try any device he uses for family calls.',
      'Note straight-to-voicemail vs ringing out.',
      'Message whoever coordinates his care immediately — he may be out, napping, or simply not hearing it.',
      'Contact a neighbor or nearby relative.',
      'Check the family chat for any contact with him today.',
    ],
    first24: [
      'Decide as a family who can physically check, and have them go.',
      'If no family member can reach or get to him, escalate to a welfare check.',
      'Ensure whoever holds his details is informed for responders.',
      'Keep the family updated to avoid dropped or duplicated effort.',
    ],
    escalateWhen: [
      'Known conditions plus unusual silence and no family confirmation he is fine.',
      'No family contact within a window that is unusual for him.',
      'Something physically off at the home noticed by a neighbor or family.',
    ],
    prevention:
      "The grandpa version of this problem is usually a coordination failure plus a man who doesn't answer phones. Daily OK solves both: one daily tap he controls, and one shared status the whole family sees as Viewers — so nobody assumes someone else checked, and nobody is decoding his silence alone.",
    variants: [
      {
        heading: 'If you are not the main point of contact',
        body:
          "Grandparent situations carry a layer the parent ones don't: you may not be the person who coordinates their care, may not have their medical details, and may not know their exact routine. That is not a reason to hesitate — it is a reason to make one extra call first. Whoever does coordinate can usually resolve the worry in a minute, and can escalate faster than you can from outside.",
        points: [
          'Message whoever coordinates their care — a parent, an aunt or uncle, a sibling — before escalating further. They may already know why the phone is unanswered.',
          'Ask that person for the address, any condition worth mentioning, and the name of a neighbour, so you have it ready if a welfare check becomes necessary.',
          'If they use a tablet or smart device for family video calls, try that as well as the phone.',
        ],
      },
    ],
    faqs: [
      { q: "I'm not his main caregiver — is it my place to act?", a: 'Yes. Acting on a worry is always appropriate; the efficient move is to alert whoever coordinates his care while you also try him, so the family responds together.' },
      { q: '911 or welfare check for grandpa?', a: 'Specific immediate-danger reason → 911. General worry the family cannot resolve → non-emergency police welfare check.' },
      { q: 'How is a welfare check requested?', a: "Call the police non-emergency line where he lives, ask for a welfare check, and give address, age, conditions, description, relationship, and last contact." },
      { q: 'He never answers anyway — does this mean anything?', a: 'Weak alone; meaningful combined with unusual timing and anything odd reported nearby. A daily check-in removes the reliance on him answering at all.' },
      { q: 'Everyone assumed someone else called — how do we prevent that?', a: 'A shared one-tap daily check-in with a single family-visible status eliminates the "I thought you called him" gap that makes grandparent worry worse.' },
    ],
  },
  {
    slug: 'teenage-daughter-not-answering-phone',
    who: 'your teenager',
    title:
      "Teen Not Answering: What to Do in the First Hour",
    metaDescription:
      "A proportionate plan for the first hour: what to check before you worry, who to contact, when a missed call is genuinely a signal, and how to agree an escalation rule that doesn't feel like surveillance.",
    h1: "What to do when your teenager isn't answering the phone",
    directAnswer:
      "Text rather than call again — teenagers answer texts far more readily than calls. Check the ordinary explanations first: school, practice, a shift, a friend's house, gaming with notifications off. If it is well past a time you agreed on, message one or two close friends or their parents before escalating further.",
    intro:
      "A teenage daughter not picking up is, the overwhelming majority of the time, ordinary — silenced phone, dead battery, busy with friends, in a class or activity. The aim is a calm, proportionate check that confirms she's fine without overreacting or turning a normal moment into a trust-damaging confrontation.",
    context:
      "As with any teenager, the genuine-danger base rate is low and autonomy matters, so the response should be measured and consent-based rather than surveillance-driven. Anchor concern to agreed expectations, not to a single missed call.",
    first30: [
      'Text instead of calling repeatedly — a short "Text me back so I know you\'re OK" is more likely to land.',
      'Check known context: school, practice, work, a friend\'s, an event where phones are away.',
      'If well past an expected time, message a close friend or a friend\'s parent.',
      'Check any messaging or location app you both already agreed to — not a covert new one.',
      'Account for her phone habits (silent mode, low battery) before assuming the worst.',
    ],
    first24: [
      'If she is past a concrete agreed time and unreachable, contact friends, their parents, and the place she was expected.',
      'Escalate in proportion to how far past expectation she is and any specific risk — not on one missed call.',
      'If no one has seen her well past when she should have left a known location, treat that as a stronger signal.',
      'Keep police involvement for a genuine specific concern; most non-answers resolve before that.',
    ],
    escalateWhen: [
      'Well past an agreed concrete time with no friend or parent able to account for her.',
      'A specific risk factor (distress, an unfamiliar place, something concerning she said).',
      'Her contacts also cannot reach her and last-seen details are genuinely worrying — then non-emergency police.',
    ],
    prevention:
      "The durable answer for a teen is a consented habit, not tracking. With Daily OK she taps \"I'm OK\" at agreed times with no location sharing — reassurance for you, autonomy for her. Presented as a way to reduce check-up calls rather than to monitor, it builds trust instead of the cat-and-mouse dynamic covert tracking creates.",
    variants: [
      {
        heading: 'Keep the response proportionate',
        body:
          'Teenagers differ from elderly relatives in almost every way that matters here: the base rate of genuine danger is low, autonomy and trust are central, and over-escalation carries real social and relationship costs. The right framing is consent-based rather than surveillance — a plan you have both agreed to beats anything you impose after a scare.',
        points: [
          'Text rather than call repeatedly. Teens answer texts far more readily than calls, and a short "Reply so I know you\'re OK" clears a low bar.',
          'Check the obvious context first: school, practice, a job, a friend\'s house, a cinema, or gaming with notifications muted.',
          'Message one or two close friends, or their parents, if it is well past a time you agreed on.',
          'Agree the escalation rule together in advance, so using it later is not experienced as a betrayal.',
        ],
      },
    ],
    faqs: [
      { q: 'How long is normal for a teen not to answer?', a: 'Often a while, and usually harmlessly. Tie your concern to a concrete agreed expectation (curfew, arrival time) rather than a single missed call during ordinary activity.' },
      { q: 'Is secret location tracking a good idea?', a: 'It generally erodes trust once discovered and teaches avoidance. A consent-based check-in at agreed times is more sustainable and still gives you reassurance.' },
      { q: 'When should police be involved?', a: 'When she is well past a concrete expected time, contacts cannot account for her, and there is real concern. Use the non-emergency line unless there is a specific immediate-danger sign.' },
      { q: 'Her phone is always on silent — how do I get reliability?', a: 'Expecting answered calls is unreliable for teens. A single-tap agreed check-in habit is far more dependable and does not feel like surveillance.' },
      { q: "She'll think a check-in means I don't trust her — how do I frame it?", a: 'Frame it honestly: a one-tap, no-location check-in exists so you do not have to call and hover. Most teens accept that trade because it gives them more space, not less.' },
    ],
  },
  {
    slug: 'college-student-not-answering-phone',
    who: 'your college student',
    title:
      "College Student Not Answering: What to Do First",
    metaDescription:
      "The first steps when a student isn't picking up, why campus security is the right escalation before police, and when a quiet phone is worth acting on.",
    h1: "What to do when your college student isn't answering the phone",
    directAnswer:
      "Text first, then account for the ordinary: a class, a shift, a library with no signal, or sleep. If several hours pass and it is unlike them, contact a roommate, then the residence adviser. Campus security can carry out a room check faster than police, and that is usually the right first escalation.",
    intro:
      "A college student going quiet for a day is, far more often than not, a packed schedule, a silenced phone, exams, or simply the normal independence of someone building their own life. The right response respects that independence while still giving you a clear path to confirm they're fine — including campus-specific options most families don't know about.",
    context:
      "College students are legal adults living away from home, so the resources differ: resident advisors, campus police, roommates, and the university wellness office matter more than for a minor, and over-escalation can be both unnecessary and embarrassing for them. Calm proportionality is key.",
    first30: [
      'Text rather than call repeatedly; reference something specific so they know it matters ("Just need a quick text back today").',
      'Consider the academic calendar: exams, deadlines, late nights, time-zone gaps, and travel all routinely cause silence.',
      'Message a roommate, a close friend, or anyone in their group you can reach.',
      'Check any app or shared calendar you both already use by agreement.',
      'Recall their normal pattern — many students simply do not check in daily and that is normal for them.',
    ],
    first24: [
      'If silence is genuinely unusual for them and a day passes, contact the roommate and friends directly.',
      'Contact the residence hall front desk or the Resident Advisor (RA) — they can do an informal room check.',
      'If still no contact and you are worried, campus police can perform a welfare check on campus housing.',
      'Use the university dean-of-students / wellness office for non-emergency concerns; reserve 911 for specific immediate danger.',
    ],
    escalateWhen: [
      'It is well outside their normal pattern and the roommate/friends also cannot account for them.',
      'There is a specific concern (they sounded distressed, mentioned a crisis, missed something they would never miss).',
      'Campus contacts cannot confirm safety — escalate to campus police for a room welfare check.',
    ],
    prevention:
      "For a college student the fix is the lowest-friction reassurance possible, because anything heavy-handed gets ignored. Daily OK is a one-tap, no-location check-in at a time they choose — reassurance for you without intruding on their independence or asking roommates and RAs to be your eyes. It replaces the awkward \"why didn't you call me back\" loop with a habit they actually keep.",
    faqs: [
      { q: 'How long should I wait before worrying about a college student?', a: 'Usually longer than you instinctively want to. A day of silence during a normal semester is common. Concern is more justified when it clearly breaks their established pattern or coincides with a specific worry.' },
      { q: 'Can I get someone to check their dorm?', a: "Yes. The residence hall front desk or Resident Advisor can often do an informal check, and campus police can perform a formal welfare check on university housing. Have their full name, dorm, and room number ready." },
      { q: 'Is it 911 or campus police?', a: 'For a specific immediate-danger concern, 911. For "I cannot reach my student and I am worried," campus police or the dean of students / wellness office is the appropriate, proportionate route.' },
      { q: "They're an adult — will the school even talk to me?", a: 'Schools generally will accept a welfare-concern request and check on a student even when privacy rules limit what they can share back. You can ask them to confirm contact was made without expecting detailed information.' },
      { q: "They find daily contact smothering — what's realistic?", a: 'A single daily tap with no location and no call is about the least intrusive option that still gives reassurance. Framed as replacing check-up calls, most students tolerate it far better than phone expectations.' },
    ],
  },
  {
    slug: 'spouse-not-answering-phone',
    who: 'your spouse',
    title:
      "Spouse Not Answering: The First Hour, Step by Step",
    metaDescription:
      "What to do in the first hour when a partner isn't answering, how to judge whether the silence is out of character, and the point at which contacting their workplace or police is reasonable.",
    h1: "What to do when your spouse isn't answering the phone",
    directAnswer:
      "Call twice, then text. Note whether it rang out or went straight to voicemail. Work through today's plan — a meeting, a commute, a dead battery, a dead zone. If the silence is genuinely out of character and several hours pass, contact their workplace or a close friend before calling police.",
    intro:
      "A spouse not answering usually has an ordinary explanation — a meeting, driving, a dead battery, deep focus, or poor signal — but because you know their normal patterns intimately, a real deviation can feel obvious and alarming. Use what you know about their routine as data, and work through this calmly and in order.",
    context:
      "The spouse case is distinct because you typically have far more context than for any other relationship: their schedule, who they're with, where they were going, and their health. That context lets you judge a true anomaly quickly — and makes a shared daily signal a light, mutual safety net rather than monitoring.",
    first30: [
      'Call again, text, and message any app you both use; one channel often gets through when another does not.',
      'Map it against today: a known meeting, a commute, a flight, a no-phone activity (gym, medical appointment, driving).',
      'Check whether straight-to-voicemail (phone off/dead) or ringing out (busy/away) — you likely know which is normal for them.',
      'Contact their workplace, a colleague, or whoever they were with or going to meet today.',
      'Consider location/signal: tunnels, rural areas, and flights routinely cause total silence.',
    ],
    first24: [
      'If the silence genuinely breaks their pattern and you have a health or safety reason to worry, escalate sooner.',
      'Call their workplace or the last known destination and ask if they arrived or left as expected.',
      'If they were driving a known route and are badly overdue with no contact, that is a stronger, more specific concern.',
      'If you have a concrete safety reason and cannot locate them, a non-emergency welfare check (or 911 for immediate danger) is appropriate.',
    ],
    escalateWhen: [
      'A known medical condition plus unusual, unexplained silence.',
      'They were traveling a known route and are significantly overdue with no contact and no arrival confirmation.',
      'Anything specific they said or did before going silent that raises genuine concern.',
    ],
    prevention:
      "Between spouses the issue is usually not surveillance but a shared, low-effort safety net — especially if one of you travels, commutes alone, or has a health condition. Daily OK can be a mutual one-tap check-in: a quick \"I'm OK\" on ordinary days, an automatic alert on the day it's missed. It is reassurance you give each other, not monitoring.",
    faqs: [
      { q: 'How long before I should worry about my spouse?', a: 'Use your knowledge of their day. If they are in a known meeting or commuting, longer silence is expected. If it clearly breaks a pattern you know well and there is a health or travel reason to worry, escalate sooner.' },
      { q: 'When is a welfare check or 911 appropriate for a spouse?', a: 'If you have a specific reason to believe they are in immediate danger (a health event, an accident on a known route), 911. If you are worried with a concrete reason but no immediate-danger sign and cannot locate them, a non-emergency welfare check is reasonable.' },
      { q: 'They were driving and are very late — what should I do?', a: 'Call the destination to confirm arrival, try alternate contact channels, and contact anyone expecting them. If they are badly overdue on a known route with no contact, that specific pattern justifies escalating to police.' },
      { q: 'Poor signal where they travel makes silence normal — how do I cope?', a: 'Known dead zones are a common benign cause. A mutual daily check-in with a defined window removes the ambiguity so a predictable signal gap no longer reads as an emergency.' },
      { q: "Isn't a check-in between spouses a sign of distrust?", a: 'Framed as mutual — both of you tap, both get peace of mind — it is the opposite of distrust. It is most valuable when one partner travels or commutes alone, where it is simply a shared safety habit.' },
    ],
  },
  {
    slug: 'adult-child-not-answering-phone',
    who: 'your adult child',
    title:
      "Adult Child Not Answering: When to Worry, What to Do",
    metaDescription:
      "How long to wait before a grown child's silence is worth acting on, who to contact first, and when requesting a welfare check is proportionate rather than an overreaction.",
    h1: "What to do when your adult child isn't answering the phone",
    directAnswer:
      "Call and text once each, then allow a few hours — adult children miss calls for entirely ordinary reasons. If it is unlike them and a full day passes, contact a partner, housemate or close friend. Request a police welfare check only if you have a concrete reason to believe something is wrong.",
    intro:
      "An adult child not answering is usually just adult life — work, a busy weekend, a silenced phone, or simply not feeling obligated to answer immediately. The challenge here is mostly emotional: balancing genuine concern against their autonomy so you confirm they're fine without straining the relationship.",
    context:
      "Your adult child is an independent adult with their own household, so the resources resemble the spouse case (their partner, roommates, workplace, friends) and the main risk is over-escalation that feels intrusive. Proportionality and respect for their independence are central.",
    first30: [
      'Text instead of calling repeatedly; keep it light and specific ("No need to call, just text me a thumbs up").',
      'Consider their normal life: work hours, travel, a new baby, shift work, or simply not being a frequent caller.',
      'If genuinely unusual and time has passed, contact their partner, roommate, or a sibling who may have spoken to them.',
      'Check any group chat — a sibling may have heard from them today.',
      'Account for their actual habits before assuming the worst; many adults simply do not answer promptly.',
    ],
    first24: [
      'If silence truly breaks their pattern, contact their partner or someone who lives with or near them.',
      'Reach their workplace only if it is proportionate and you have real concern, not on a single missed call.',
      'If a specific worry exists (they were unwell, distressed, or somewhere concerning) and no one can reach them, escalate.',
      'A non-emergency welfare check is appropriate for a specific, genuine concern; 911 only for immediate danger.',
    ],
    escalateWhen: [
      'It clearly breaks their normal pattern and their partner/roommate/close contacts also cannot reach them.',
      'A specific reason for concern (a health issue, distress, or something worrying they said).',
      'Their household contacts cannot confirm safety and the situation is genuinely worrying — then non-emergency police.',
    ],
    prevention:
      "With an independent adult child the fix has to be light enough not to feel like parenting. Daily OK is a one-tap, no-location, mutually framed check-in — they tap once on agreed days, you are alerted only if it is missed. Presented as \"so I do not call and worry,\" it gives you reassurance while explicitly respecting that they run their own life.",
    faqs: [
      { q: 'How long before I worry about an adult child?', a: 'Generally a good while. Adults are not obliged to answer promptly, and a day of silence is often nothing. Concern is more justified when it clearly breaks their pattern or there is a specific reason.' },
      { q: 'Is it overstepping to call their workplace or partner?', a: 'For a single missed call, usually yes. For a genuine, specific concern when you cannot reach them, contacting their partner or a close contact is reasonable — lead with concern, not accusation.' },
      { q: 'When is a welfare check or 911 appropriate?', a: 'A specific immediate-danger reason → 911. A specific genuine concern with no way to confirm safety → non-emergency police welfare check. Avoid escalating purely on an unanswered call.' },
      { q: 'They feel I worry too much — how do I handle that?', a: 'Acknowledge it and shift to the lowest-friction option: a single agreed daily tap with no location and no call replaces anxious phoning with a habit, which most adult children find less intrusive, not more.' },
      { q: "Won't a check-in feel like I'm treating them like a kid?", a: 'Only if it is framed as control. Framed as mutual and minimal — one tap, no tracking, so you stop calling to check — it reads as respect for their time rather than distrust.' },
    ],
  },
]

export function getWhatToDoPage(slug: string): WhatToDoPage | undefined {
  return whatToDoPages.find((p) => p.slug === slug)
}
