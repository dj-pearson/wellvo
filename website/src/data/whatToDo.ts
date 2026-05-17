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

export interface WhatToDoPage {
  slug: string
  /** Short relationship label used in copy, e.g. "your mom". */
  who: string
  title: string
  metaDescription: string
  h1: string
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
  faqs: WhatToDoFaq[]
}

export const LAST_UPDATED = '2026-05-17'

export const whatToDoPages: WhatToDoPage[] = [
  {
    slug: 'mom-not-answering-phone',
    who: 'your mom',
    title: "What to Do When Your Mom Doesn't Answer the Phone",
    metaDescription:
      "Your mom isn't answering her phone? A calm, step-by-step plan: what to do in the first 30 minutes, the first 24 hours, when to request a welfare check, and how to stop the panic recurring.",
    h1: "What to do when your mom doesn't answer the phone",
    intro:
      "If your mom isn't picking up and your stomach just dropped, take one breath — most missed calls have an ordinary explanation, and you can work through this methodically. This page walks you from the first worried minute to a clear decision about whether to escalate, without either dismissing your worry or feeding it. Print it, or keep it open, and go step by step.",
    context:
      "Advice for a mom specifically depends on what you already know: does she live alone, does she have a health condition, is a missed call unusual for her or completely normal? A mom who always answers within an hour going silent for three is a different signal than one who routinely leaves her phone in another room.",
    first30: [
      'Call a second time, then send a text and (if you have it) a message on any app she uses — some people answer a text faster than a call.',
      'Check whether the call rang normally, went straight to voicemail (phone off / dead battery), or rang out (phone away from her).',
      'Think honestly about the last 24 hours: did she mention a nap, an appointment, errands, a hair appointment, church, or poor sleep?',
      'Message anyone who may be physically near her — a sibling, a neighbor, her building manager — and ask if they can see or hear that she is fine.',
      'Try a landline if she has one, or any device she keeps in a fixed location.',
    ],
    first24: [
      "If 30–60 minutes pass with no reply and silence is unusual for her, escalate effort: call repeatedly, try every contact who lives close.",
      'Ask a nearby person to physically go by and knock — a neighbor, friend, or family member is faster than any remote step.',
      'If no one can go and your concern is rising, move to a welfare check rather than waiting out the day.',
      'Keep a simple log of times you called and what you tried — it helps if you do call a non-emergency line.',
    ],
    escalateWhen: [
      'She has a known heart, fall, diabetes, or cognitive condition and the silence is out of character.',
      'It is well outside any explainable window (e.g. she always answers by mid-morning and it is now afternoon).',
      'Anyone nearby reports something off — uncollected mail, curtains shut all day, car home but no answer at the door.',
    ],
    prevention:
      'The reason this is so frightening is the information gap: silence could mean nothing or everything, and you have no fast way to tell. A daily check-in closes that gap. With Daily OK, your mom taps one "I\'m OK" each day; if she misses it, you find out within your chosen window instead of discovering it during a random unanswered call. The dread stops being a daily background process because the not-knowing has somewhere to go.',
    faqs: [
      { q: 'How long should I wait before worrying that my mom isn\'t answering?', a: 'There is no universal number — it depends on her normal pattern. If she usually answers within an hour and several hours pass with no reply to calls or texts, that is a reasonable point to escalate to someone nearby and consider a welfare check. Trust a clear deviation from her baseline more than the clock.' },
      { q: 'Should I call 911 because my mom didn\'t answer the phone?', a: 'Call 911 if you have a concrete reason to believe she is in immediate danger right now (for example she said she felt unwell then went silent). If you are worried but have no specific emergency indicator, the right tool is usually a non-emergency police welfare check, not 911.' },
      { q: 'What is a welfare check and how do I ask for one?', a: "A welfare check is when police visit an address to confirm a person is safe. Call your mom's local police non-emergency line, say you'd like to request a welfare check, and give her address, a description, your relationship, why you're concerned, and when you last had contact." },
      { q: 'My mom often ignores calls — how do I know when it\'s real?', a: 'Combine signals rather than relying on one. A missed call alone is weak; a missed call plus an unusual time plus no reply to a text plus a neighbor noticing something is a much stronger reason to act. Set up a daily check-in so you are not trying to read meaning into every silence.' },
      { q: 'I live far away and no one is nearby — what can I actually do?', a: 'You can still call repeatedly, contact building management or non-emergency police for a welfare check, and reach any local contact. Long-distance is exactly the situation a daily check-in is built for, because it removes the need to interpret silence from hundreds of miles away.' },
    ],
  },
  {
    slug: 'dad-not-answering-phone',
    who: 'your dad',
    title: "What to Do When Your Dad Doesn't Answer the Phone",
    metaDescription:
      "Your dad isn't answering? Step-by-step: the first 30 minutes, the first 24 hours, when to request a welfare check, and how to prevent the worry from recurring.",
    h1: "What to do when your dad doesn't answer the phone",
    intro:
      "When your dad doesn't pick up, the worry can arrive fast — especially if he's the type who usually answers, or the type who lets it ring and you can never tell which is happening. Work this calmly and in order. Most of the time there's an ordinary reason; the point of a plan is to find out quickly either way rather than spiraling.",
    context:
      "Dads in particular are often under-connected: many are less likely to text back, more likely to leave the phone on a charger in another room, and less likely to mention appointments. That makes a single missed call a weak signal on its own and makes a reliable daily check-in especially useful.",
    first30: [
      'Call again, then text — many older men will respond to a short text ("Just checking you\'re OK, text back") faster than a call.',
      'Note whether it rang out (phone away from him) or went straight to voicemail (off/dead) — they mean different things.',
      'Recall his routine: garage, yard, workshop, golf, a drive, a nap, or a TV turned up loud are common reasons a dad misses a call.',
      'Contact anyone near him — a neighbor he knows, a sibling, a friend he sees regularly.',
      'Try a landline or any fixed device if he keeps one.',
    ],
    first24: [
      'If silence is unusual for him and 30–60 minutes pass, widen the net: call repeatedly and contact every local person.',
      'Ask someone close by to physically check — knocking on the door beats any remote action.',
      'If no one can go and concern is growing, request a welfare check rather than waiting all day.',
      'Log what you tried and when, in case you contact a non-emergency line.',
    ],
    escalateWhen: [
      'He has a known cardiac, fall, or other health risk and the silence breaks his normal pattern.',
      "It is far outside an explainable window for his routine.",
      'A neighbor or contact notices something out of place (car home, no answer at the door; lights/curtains unchanged all day).',
    ],
    prevention:
      "Because dads are often the hardest to reach by phone, the silence-means-nothing-or-everything problem hits especially hard here. A daily check-in fixes it without nagging him: with Daily OK he taps one button a day — far less intrusive than the daily call he may resist — and you're alerted only if he misses it. You stop trying to decode whether he's in the workshop or in trouble.",
    faqs: [
      { q: 'My dad never answers his phone anyway — is a missed call meaningless?', a: 'Not meaningless, but weak by itself. Treat it as one input. A missed call combined with an unusual time, no text reply, and anything odd reported nearby is a real reason to act. A daily check-in is the cleaner fix because it does not depend on him answering calls at all.' },
      { q: 'Should I drive over or call the police first?', a: 'If someone (you or a local contact) can get there quickly, that is usually fastest and least disruptive. If no one can and you are genuinely worried, a non-emergency police welfare check is appropriate. Use 911 only if you believe he is in immediate danger.' },
      { q: 'How do I request a welfare check for my dad?', a: "Call the non-emergency number for the police where he lives. Say you want to request a welfare check, give his address, a physical description, your relationship, the reason for concern, and when you last spoke." },
      { q: 'He lives alone and far from me — what is realistic?', a: 'Repeated calls and texts, contacting any nearby person, and a non-emergency welfare check are all available regardless of distance. To stop this recurring, a one-tap daily check-in removes the guesswork that distance makes worse.' },
      { q: 'How long is too long to wait?', a: 'Judge against his baseline, not a fixed clock. A few hours of silence from someone who always replies promptly is more concerning than a full day from someone who routinely ignores the phone. When in doubt and you cannot reach anyone near him, escalate.' },
    ],
  },
  {
    slug: 'elderly-mother-not-answering-phone',
    who: 'your elderly mother',
    title: "What to Do When Your Elderly Mother Doesn't Answer the Phone",
    metaDescription:
      "Elderly mother not answering the phone? A calm, careful plan for the first 30 minutes and 24 hours, when to escalate to a welfare check, and how to prevent the recurring fear.",
    h1: "What to do when your elderly mother doesn't answer the phone",
    intro:
      "With an elderly mother, a missed call carries more weight, and pretending otherwise doesn't help. The right response is neither to panic nor to brush it off, but to move through a clear sequence quickly. Acting in order — not faster, just in order — is what gets you to a confident answer soonest.",
    context:
      'For an elderly parent, age-related fall risk, medication, and possible cognitive changes mean the threshold to physically verify safety should be lower than for a younger relative. A shorter silence justifies escalation, and an in-person check is worth more than additional remote attempts.',
    first30: [
      'Call again and send a simple text; if she uses a tablet or smart speaker she can answer, try that too.',
      'Note straight-to-voicemail (phone off / uncharged — common for elderly parents) versus ringing out.',
      'Recall known appointments, a nap schedule, day programs, or whether she sleeps deeply or removes hearing aids.',
      'Contact a neighbor, building manager, or nearby family immediately — for an elderly parent, escalate to a person nearby sooner rather than later.',
      'Call any in-home caregiver, aide, or service that may be scheduled today.',
    ],
    first24: [
      'If you cannot confirm she is fine within roughly 30 minutes, treat it as higher-priority than you would for a younger person.',
      'Get someone to the home — neighbor, family, building staff — to physically check.',
      'If no one can go reasonably soon, request a police welfare check rather than waiting hours.',
      'Have her address, conditions, medications, and a recent photo ready in case responders need them.',
    ],
    escalateWhen: [
      'Any known fall risk, cardiac/diabetic condition, or cognitive impairment combined with unusual silence — escalate early.',
      'She missed an expected medication, meal, or caregiver interaction.',
      'A neighbor reports uncollected mail/paper, unchanged blinds, or no response at the door.',
    ],
    prevention:
      "For an elderly mother the stakes are real, which is why a passive daily signal matters so much. Daily OK gives her one large \"I'm OK\" button — usable even with limited tech comfort, answerable from the notification — and escalates to you and siblings automatically if a day is missed. It is the safety net that makes living independently defensible, without a pendant or surveillance she'd reject.",
    faqs: [
      { q: 'Should I worry sooner because she is elderly?', a: 'Yes — a lower escalation threshold is reasonable. Because age raises the chance that silence reflects a fall or medical event, getting eyes on her sooner is prudent. That is not panic; it is matching your response to the actual risk profile.' },
      { q: 'When is it 911 versus a welfare check?', a: 'If you have a specific reason to think she is in immediate danger (she sounded unwell, mentioned chest pain, then went silent), call 911. If you are worried without a specific emergency sign and no one can get there, request a non-emergency police welfare check.' },
      { q: 'How do I ask for a welfare check for an elderly parent?', a: "Call the local police non-emergency line, request a welfare check, and provide her address, age, relevant medical conditions, a description, your relationship, and when you last had contact. Mention fall or cardiac risk explicitly — it helps responders prioritize." },
      { q: 'She forgets to charge her phone constantly — is the silence real?', a: 'A dead phone is the most common benign cause, but with an elderly parent you should still verify rather than assume, because the cost of being wrong is high. The durable fix is a daily check-in so a dead phone alone no longer creates an information blackout.' },
      { q: 'I am far away with no local contacts — what now?', a: 'You can still escalate to a non-emergency welfare check from anywhere, and it is appropriate to do so for an elderly parent when you cannot otherwise confirm safety. Setting up a daily check-in removes the distance problem for the future.' },
    ],
  },
  {
    slug: 'elderly-father-not-answering-phone',
    who: 'your elderly father',
    title: "What to Do When Your Elderly Father Doesn't Answer the Phone",
    metaDescription:
      "Elderly father not picking up? Calm step-by-step guidance for the first 30 minutes and 24 hours, when to escalate, and how to prevent the worry recurring.",
    h1: "What to do when your elderly father doesn't answer the phone",
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
    faqs: [
      { q: 'Is a quicker response justified for an elderly father?', a: 'Generally yes. The combination of higher medical risk and a tendency not to answer means verifying in person sooner is sensible. Matching urgency to risk is not overreacting.' },
      { q: '911 or welfare check?', a: 'Immediate-danger signal (he sounded unwell then went silent) → 911. Worried without a specific emergency indicator and nobody can get there → non-emergency police welfare check.' },
      { q: 'How do I request a welfare check?', a: "Call the police non-emergency number where he lives, request a welfare check, and give his address, age, health conditions, a description, your relationship, and the time of last contact." },
      { q: 'He refuses to keep his phone on him — is the silence meaningful?', a: 'On its own it is weak, but with an elderly parent the safe move is to verify, not assume. A daily check-in is the real solution because it does not rely on him answering a phone at all.' },
      { q: 'No nearby contacts and I am far away — what can I do?', a: 'Request a non-emergency welfare check from anywhere; it is an appropriate step for an elderly parent you cannot otherwise reach. A daily check-in prevents the recurrence.' },
    ],
  },
  {
    slug: 'grandma-wont-pick-up',
    who: 'your grandma',
    title: "What to Do When Your Grandma Won't Pick Up the Phone",
    metaDescription:
      "Grandma won't pick up? A calm plan: first 30 minutes, first 24 hours, when to escalate to a welfare check, and how to set up a daily check-in so it doesn't recur.",
    h1: "What to do when your grandma won't pick up the phone",
    intro:
      "If grandma isn't picking up, you may also be the family member who noticed first but isn't the primary caregiver — which can make it hard to know how far to go. This guide gives you a clear sequence and, importantly, when to loop in whoever coordinates her care so you're acting together, not alone.",
    context:
      "Grandparent situations often involve a layer the parent ones don't: you might not be the main point of contact, may not have her medical details, and may not know her exact routine. Coordinating quickly with whoever does is part of the right response here.",
    first30: [
      'Call again and text; try any tablet or smart device she uses for family video calls.',
      'Note straight-to-voicemail vs ringing out.',
      'Immediately message whoever coordinates her care (a parent, aunt/uncle) — they may know she is at an appointment or simply napping.',
      'Contact a neighbor or anyone who lives near her.',
      'Check any family group chat — someone may already have spoken to her today.',
    ],
    first24: [
      'Agree with the family who is best placed to physically check, and have them do so.',
      'If no one in the family can reach her or get there, escalate to a welfare check.',
      'Make sure whoever holds her medical and address details is informed in case responders need them.',
      'Keep the family chat updated so efforts are not duplicated or dropped.',
    ],
    escalateWhen: [
      'Known health conditions plus unusual silence and no family member can confirm she is fine.',
      'No one in the family has had contact in a timeframe that is unusual for her.',
      'A neighbor or the family notices something physically off at her home.',
    ],
    prevention:
      "Grandparent worry is often worse because responsibility is diffuse — everyone assumes someone else checked. A shared daily check-in fixes exactly that: with Daily OK she taps once a day and the whole family (added as Viewers) sees the same status, so no one is left guessing and no one is the lone designated worrier.",
    faqs: [
      { q: "I'm not grandma's primary caregiver — should I still act?", a: 'Yes. Noticing is enough reason to act. The fastest first step is usually to alert whoever coordinates her care while you also try to reach her, so the family responds together rather than each person assuming someone else has it.' },
      { q: 'When does this become a 911 call?', a: 'Only with a specific reason to believe she is in immediate danger now. Otherwise, when the family cannot confirm she is safe, a non-emergency police welfare check is the appropriate escalation.' },
      { q: 'How do we request a welfare check for a grandparent?', a: "Whoever has her address and details (or you, if you have them) calls the local police non-emergency line, requests a welfare check, and provides address, age, conditions, a description, relationship, and last contact time." },
      { q: 'The family keeps assuming someone else called her — how do we stop that?', a: 'Diffuse responsibility is the core problem with grandparent check-ins. A shared daily check-in with one visible status for the whole family removes the assumption gap entirely.' },
      { q: 'She often just doesn\'t hear the phone — is that all this is?', a: 'Frequently, yes — but verify rather than assume when health conditions are involved. A daily check-in means a missed call no longer triggers a family-wide scramble.' },
    ],
  },
  {
    slug: 'grandpa-wont-pick-up',
    who: 'your grandpa',
    title: "What to Do When Your Grandpa Won't Pick Up the Phone",
    metaDescription:
      "Grandpa won't answer? Calm, ordered steps for the first 30 minutes and 24 hours, when to escalate to a welfare check, and how to prevent it recurring.",
    h1: "What to do when your grandpa won't pick up the phone",
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
    faqs: [
      { q: "I'm not his main caregiver — is it my place to act?", a: 'Yes. Acting on a worry is always appropriate; the efficient move is to alert whoever coordinates his care while you also try him, so the family responds together.' },
      { q: '911 or welfare check for grandpa?', a: 'Specific immediate-danger reason → 911. General worry the family cannot resolve → non-emergency police welfare check.' },
      { q: 'How is a welfare check requested?', a: "Call the police non-emergency line where he lives, ask for a welfare check, and give address, age, conditions, description, relationship, and last contact." },
      { q: 'He never answers anyway — does this mean anything?', a: 'Weak alone; meaningful combined with unusual timing and anything odd reported nearby. A daily check-in removes the reliance on him answering at all.' },
      { q: 'Everyone assumed someone else called — how do we prevent that?', a: 'A shared one-tap daily check-in with a single family-visible status eliminates the "I thought you called him" gap that makes grandparent worry worse.' },
    ],
  },
  {
    slug: 'teenage-son-not-answering-phone',
    who: 'your teenage son',
    title: "What to Do When Your Teenage Son Isn't Answering His Phone",
    metaDescription:
      "Teenage son not answering? A calm, proportionate plan that respects a teen's autonomy: the first 30 minutes, the first 24 hours, when to escalate, and a non-creepy way to prevent it.",
    h1: "What to do when your teenage son isn't answering his phone",
    intro:
      "A teenager not answering is usually exactly what it looks like — a phone on silent, a dead battery, a game, a group of friends — and very rarely an emergency. The goal here is a proportionate response: enough to confirm he's fine, without escalating in a way that damages trust or treats normal teenage behavior as a crisis.",
    context:
      "Teens are different from elderly relatives in almost every way that matters here: the base rate of genuine danger is low, autonomy and trust are central, and over-escalation has real social and relationship costs. The right framing is consent-based, not surveillance.",
    first30: [
      'Text rather than call repeatedly — teens respond to texts far more than calls; a short "Reply so I know you\'re OK" works.',
      'Check known context: school, practice, a job, a friend\'s house, a movie, gaming with notifications off.',
      'Message one or two of his close friends or their parents if it is well past an expected time.',
      'Check any family location or messaging app you both already consented to use — not a new covert one.',
      'Recall whether his phone or charging habits explain it (he routinely lets the battery die).',
    ],
    first24: [
      'If he is past a clearly agreed time (curfew, expected home) and unreachable, contact friends, their parents, and the last place he was expected.',
      'Escalate based on how far past the agreed expectation he is and any specific risk, not on a single missed call.',
      'If he was somewhere specific and no one has seen him well past when he should have left, that is a stronger reason to act.',
      'Reserve police involvement for a genuine, specific concern — most teen non-answers resolve well before this.',
    ],
    escalateWhen: [
      'He is significantly past an agreed, concrete time and no friend or parent can account for him.',
      'There is a specific risk factor (he was distressed, in an unfamiliar place, mentioned something concerning).',
      'His known contacts also cannot reach him and last-seen information is genuinely worrying — then non-emergency police.',
    ],
    prevention:
      "With a teen, the fix is not tracking — it is a low-friction agreement. Daily OK works as a consent-based check-in: he taps \"I'm OK\" at agreed times (after school, on arrival) with no location tracking, so you get reassurance and he keeps autonomy. It builds a habit and trust rather than a surveillance dynamic that teens predictably resist and route around.",
    faqs: [
      { q: 'How long before I worry about a teenager not answering?', a: 'Longer than for an elderly relative. A teen missing a call or even a few texts during normal activities is usually nothing. Anchor concern to a concrete agreed expectation (a curfew or an arrival time) rather than a single unanswered call.' },
      { q: 'Should I track his location secretly?', a: 'Covert tracking tends to backfire — teens discover it, lose trust, and route around it. A consented check-in at agreed times preserves the relationship while still giving you reassurance, which is more durable than surveillance.' },
      { q: 'When is it appropriate to call the police?', a: 'When he is meaningfully past a concrete expected time, his contacts cannot account for him, and there is genuine reason for concern. Use the non-emergency line unless there is a specific immediate-danger indicator.' },
      { q: 'His phone is always dead — how do I get any reliability?', a: 'A dead phone is the classic teen non-answer. A simple agreed daily/である check-in habit (a single tap at set times) is far more reliable than expecting him to answer calls, and it does not feel like monitoring.' },
      { q: "Won't a check-in feel controlling to him?", a: 'A one-tap, no-location, consent-based check-in at times you both agreed is very different from tracking. Framed as "so I do not have to call and bug you," most teens accept it precisely because it reduces parental hovering.' },
    ],
  },
  {
    slug: 'teenage-daughter-not-answering-phone',
    who: 'your teenage daughter',
    title: "What to Do When Your Teenage Daughter Isn't Answering Her Phone",
    metaDescription:
      "Teenage daughter not answering? A proportionate, trust-preserving plan: first 30 minutes, first 24 hours, when to escalate, and a consent-based way to prevent it.",
    h1: "What to do when your teenage daughter isn't answering her phone",
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
    title: "What to Do When Your College Student Isn't Answering the Phone",
    metaDescription:
      "College student not answering? A calm, autonomy-respecting plan: first 30 minutes, first 24 hours, campus resources and welfare checks, and a low-friction way to prevent it.",
    h1: "What to do when your college student isn't answering the phone",
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
    title: "What to Do When Your Spouse Isn't Answering the Phone",
    metaDescription:
      "Spouse not answering? A calm, practical plan: the first 30 minutes, the first 24 hours, when a welfare check is appropriate, and how to prevent the worry recurring.",
    h1: "What to do when your spouse isn't answering the phone",
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
    slug: 'elderly-parent-living-alone-not-answering',
    who: 'your elderly parent who lives alone',
    title: "What to Do When Your Elderly Parent Living Alone Isn't Answering",
    metaDescription:
      "Elderly parent who lives alone not answering? A careful, calm plan for the first 30 minutes and 24 hours, when to escalate to a welfare check, and how to prevent the recurring fear.",
    h1: "What to do when your elderly parent living alone isn't answering",
    intro:
      "An elderly parent living alone who isn't answering is the situation this kind of guide exists for — the stakes are real and there is no one else in the home to notice. That is exactly why a calm, ordered, slightly faster response matters. You are not overreacting by verifying quickly; you are matching your action to a genuine risk profile.",
    context:
      "Living alone removes the built-in safety net of another person in the house, so the threshold to physically confirm safety should be lower and remote attempts should give way to in-person verification sooner than for almost any other relationship.",
    first30: [
      'Call again, text, and try any landline or fixed device.',
      'Note straight-to-voicemail (phone off/dead — very common) vs ringing out.',
      'Recall today: appointments, a day program, a nap pattern, deep sleep, or removed hearing aids.',
      'Contact a neighbor, building manager, or nearby family immediately — with no one in the home, escalate to a person nearby fast.',
      'Call any scheduled home aide, meal service, or regular visitor.',
    ],
    first24: [
      'If you cannot confirm safety within roughly 30 minutes, treat it as higher priority — there is no one else to notice.',
      'Get someone to the home to physically check as the priority action.',
      'If no one can go reasonably soon, request a police welfare check rather than waiting hours.',
      'Have address, medical conditions, medications, and a recent photo ready for responders.',
    ],
    escalateWhen: [
      'Any fall, cardiac, diabetic, or cognitive risk plus unusual silence — escalate early; there is no in-home backup.',
      'A missed medication, meal, aide visit, or expected daily contact.',
      'A neighbor reports uncollected mail, unchanged blinds, lights on/off all day, or no answer at the door.',
    ],
    prevention:
      "Living alone is precisely the case a daily check-in is designed for, because the normal safety net — another person noticing — does not exist. Daily OK supplies that net: one daily \"I'm OK\" tap, large and answerable from the notification, with automatic escalation to you and siblings if a day is missed. It is what makes living independently defensible instead of a daily gamble.",
    faqs: [
      { q: 'Should I respond faster because they live alone?', a: 'Yes. With no one else in the home to notice a fall or medical event, getting eyes on them sooner is the rational response, not panic. A lower escalation threshold is appropriate here.' },
      { q: '911 or welfare check?', a: 'Specific immediate-danger reason (they sounded unwell, then silence) → 911. Worried without a specific emergency sign and no one can get there → non-emergency police welfare check; for someone living alone, do not delay this unnecessarily.' },
      { q: 'How do I request a welfare check?', a: "Call the local police non-emergency line, request a welfare check, and give the address, age, medical conditions (mention fall/cardiac risk and that they live alone), a description, your relationship, and last contact time." },
      { q: 'It is almost always just a dead phone — am I overreacting?', a: 'A dead phone is the most common cause, but for someone living alone the cost of being wrong is high enough that verifying is the prudent default. The lasting fix is a daily check-in so a dead phone no longer creates a total information blackout.' },
      { q: 'I live far away with no local contacts — what can I do?', a: 'You can request a non-emergency welfare check from anywhere, and for an elderly parent living alone it is appropriate to do so when you cannot otherwise confirm safety. A daily check-in removes the distance problem going forward.' },
    ],
  },
  {
    slug: 'adult-child-not-answering-phone',
    who: 'your adult child',
    title: "What to Do When Your Adult Child Isn't Answering the Phone",
    metaDescription:
      "Adult child not answering? A calm, respectful plan that balances concern with their independence: first 30 minutes, first 24 hours, when to escalate, and how to prevent it.",
    h1: "What to do when your adult child isn't answering the phone",
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
