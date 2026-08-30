import { Link } from 'react-router-dom'
import { Clock, Phone, ShieldAlert, ClipboardList, HelpCircle } from 'lucide-react'
import SEO from '../components/SEO'
import { buildBreadcrumbJsonLd } from '../lib/breadcrumb'
import { LAST_UPDATED } from '../data/whatToDo'
import './ElderlyCare.css'
import './Landing.css'
import './WhatToDo.css'

/**
 * Welfare-check pillar page (US-WEB015).
 *
 * The largest content gap found in docs/SEARCH_CONSOLE_DIAGNOSIS.md: "elderly
 * welfare check", "elderly wellness check" and "wellness check on elderly" run
 * around 500 searches/month each at competition index 6-13 with $5.46-6.18
 * top-of-page bids — the best value-to-difficulty ratio anywhere in the keyword
 * file — and no page on the site targeted any of them. The phrases appeared
 * only as passing mentions across eight files.
 *
 * Editorial constraints, same as src/data/whatToDo.ts:
 *  - YMYL content. Byline is "Daily OK Editorial Team"; no implied medical or
 *    legal credentials until a licensed professional is contracted.
 *  - Police practice genuinely varies by jurisdiction. Nothing here states a
 *    universal rule about what officers will or must do — the page repeatedly
 *    points the reader at their own local agency instead.
 *  - The product argument is the closing section, not the page's purpose. The
 *    page has to be the best answer to the question actually asked before it
 *    earns the right to make one.
 */

const FAQS: { q: string; a: string }[] = [
  {
    q: 'What is a welfare check?',
    a: "A welfare check — also called a wellness check — is a visit by police or another local agency to confirm that someone is safe when a person who knows them cannot reach them and has reason to be concerned. It is a routine request handled through the non-emergency line in most areas, not an emergency call.",
  },
  {
    q: 'Who can request a welfare check on an elderly person?',
    a: 'Anyone with a genuine reason for concern can request one. You do not have to be a relative, a legal guardian, or a listed emergency contact. Neighbours, friends, landlords, church members and colleagues request them routinely. What matters is that you can explain why you are worried and give the address.',
  },
  {
    q: 'How do I request a welfare check?',
    a: "Call the non-emergency number for the police department covering the address — not your own local force, and not 911 unless you believe there is immediate danger. Say you would like to request a welfare check, give the address, and explain in one or two sentences why you are concerned and when you last had contact.",
  },
  {
    q: 'What information should I have ready before I call?',
    a: 'The full address including any apartment or unit number and gate or door codes; the person\'s full name, age and a brief physical description; any medical conditions or mobility issues; when you last had contact and how; what you have already tried; whether anyone else has a key; and whether any weapons are in the home. Having this ready makes the visit faster and safer.',
  },
  {
    q: 'Does a welfare check cost anything?',
    a: 'A police welfare check is generally not billed to the person requesting it. Costs can arise from what follows — a locksmith or a damaged door if forced entry is needed, or an ambulance transport if the person needs medical care. Those are billed separately and vary widely by area and insurance.',
  },
  {
    q: 'When should I call 911 instead of requesting a welfare check?',
    a: 'Call 911 when you have a concrete reason to believe there is an emergency happening right now — for example the person said they felt seriously unwell and then went silent, you heard a fall, or there is evidence of an accident. Use the non-emergency line for genuine worry without specific evidence of an emergency.',
  },
  {
    q: 'What happens if the police find nothing wrong?',
    a: 'That is the most common outcome and it is not a wasted call. Officers will normally confirm the person is safe and, depending on local practice and the person\'s wishes, may or may not be able to tell you much afterwards. Privacy rules limit what they can share about a competent adult, so expect confirmation rather than detail.',
  },
  {
    q: 'Will my elderly parent be angry that I sent the police?',
    a: 'Sometimes, and it is worth preparing for. Being checked on by officers can feel intrusive or embarrassing to someone who values their independence. Explaining afterwards that you could not reach them and had no other way to know helps, as does agreeing a routine together that means it does not need to happen again.',
  },
]

export default function WelfareCheck() {
  const jsonLd = [
    {
      '@context': 'https://schema.org',
      '@type': 'FAQPage',
      mainEntity: FAQS.map((f) => ({
        '@type': 'Question',
        name: f.q,
        acceptedAnswer: { '@type': 'Answer', text: f.a },
      })),
    },
    buildBreadcrumbJsonLd([
      { name: 'Home', path: '/' },
      { name: 'Welfare check on an elderly parent', path: '/welfare-check-on-elderly-parent' },
    ]),
  ]

  return (
    <>
      <SEO
        title="Welfare Check on an Elderly Parent: How to Request One"
        description="Who can request a welfare check or wellness check on an elderly parent, the non-emergency number to call, exactly what to say and have ready, what happens when officers arrive, what it costs, and when to call 911 instead."
        path="/welfare-check-on-elderly-parent"
        ogType="article"
        jsonLd={jsonLd}
      />

      <section className="ec-hero">
        <div className="container ec-hero-inner">
          <nav className="lp-breadcrumb" aria-label="Breadcrumb">
            <Link to="/">Home</Link> &nbsp;/&nbsp; Welfare check on an elderly parent
          </nav>
          <h1 className="ec-hero-title">
            How to request a welfare check on an elderly parent
          </h1>
          <p className="wtd-answer">
            A welfare check — also called a wellness check — is a visit by police to
            confirm an elderly person is safe when you cannot reach them. Call the
            non-emergency number for the area where they live, not 911 unless you believe
            there is immediate danger. Anyone with a genuine concern can request one; you
            do not have to be next of kin.
          </p>
          <p className="wtd-byline">
            By the Daily OK Editorial Team · Last updated {LAST_UPDATED}
          </p>
        </div>
      </section>

      <section className="section">
        <div className="container lp-prose">
          <div className="wtd-disclaimer" role="note">
            <strong>This is general guidance, not legal, medical or emergency advice.</strong>{' '}
            If you believe someone is in immediate danger, call your local emergency number
            (911 in the US) now. Police practice, terminology and cost vary by jurisdiction —
            always follow what your own local agency tells you. Daily OK is not a medical
            device and does not provide monitoring or emergency dispatch.
          </div>

          <h2>
            <Phone size={20} style={{ verticalAlign: '-3px', marginRight: 6 }} />
            What to say when you call
          </h2>
          <p>
            Keep it short and factual. Dispatchers take these calls constantly and the
            useful version is four sentences, not a story:
          </p>
          <div className="wtd-script">
            <p>
              "I'd like to request a welfare check. My mother, Jane Doe, is 82 and lives
              alone at 14 Elm Street, apartment 3B. She always answers by mid-morning and
              I haven't reached her since yesterday afternoon — I've called six times and
              a neighbour knocked with no answer. She has a heart condition."
            </p>
          </div>
          <p>
            That gives them the four things they need: what you want, who and where, why
            it is out of the ordinary, and what raises the stakes. If they ask questions
            you cannot answer, say so plainly — a gap in what you know is normal and does
            not invalidate the request.
          </p>

          <h2>
            <ClipboardList size={20} style={{ verticalAlign: '-3px', marginRight: 6 }} />
            Have this ready before you dial
          </h2>
          <ul className="wtd-list">
            <li>
              <strong>The full address</strong>, including apartment or unit number, and
              any gate code, building entry code or lockbox location.
            </li>
            <li>
              <strong>Their full name, age and a brief description</strong> — height,
              build, hair, anything that helps identify them.
            </li>
            <li>
              <strong>Relevant health information</strong>: heart or lung conditions,
              diabetes, epilepsy, dementia, mobility limits, oxygen, a pacemaker.
            </li>
            <li>
              <strong>When you last had contact and how</strong>, and what you have tried
              since — calls, texts, neighbours, the building manager.
            </li>
            <li>
              <strong>Who else has access</strong> — a neighbour, a family member, a
              superintendent with a key. This can avoid a forced entry.
            </li>
            <li>
              <strong>Whether there are weapons in the home</strong>, and whether they
              have a hearing impairment or would be slow to reach the door. Officers
              approach differently when they know.
            </li>
            <li>
              <strong>A pet in the house</strong>, if there is one, and whether it is
              likely to be protective.
            </li>
          </ul>

          <h2>Welfare check or wellness check — is there a difference?</h2>
          <p>
            In everyday use, no. "Welfare check" and "wellness check" describe the same
            thing: someone asks police or another local agency to confirm that a person is
            safe. Which term you hear depends mostly on where you live and which agency
            you are speaking to — some departments use one officially, some the other, and
            dispatchers understand both. Use whichever comes naturally; you will not be
            misunderstood.
          </p>
          <p>
            One distinction is worth knowing. A few areas run a separate{' '}
            <em>senior wellness check</em> or telephone reassurance programme through a
            sheriff's office, an Area Agency on Aging, or a volunteer organisation —
            scheduled, non-emergency contact rather than a one-off response to a worried
            call. If your underlying problem is recurring rather than urgent, ask your
            local Area Agency on Aging whether such a programme exists near them.
          </p>

          <h2>
            <HelpCircle size={20} style={{ verticalAlign: '-3px', marginRight: 6 }} />
            Who can request one
          </h2>
          <p>
            Anyone with a genuine reason to be concerned. You do not need to be next of
            kin, a legal guardian, or a listed emergency contact — neighbours, friends,
            landlords, faith-community members, pharmacists and long-distance relatives
            all request welfare checks routinely. If you are hesitating because you think
            you are not "official" enough to ask, that is not a real barrier.
          </p>
          <p>
            You can usually request one from anywhere. Being in another state or another
            country changes nothing except which number you dial: you want the
            non-emergency line for the agency covering <em>their</em> address, which is
            findable by searching the town or county name plus "police non-emergency".
          </p>

          <h2>
            <ShieldAlert size={20} style={{ verticalAlign: '-3px', marginRight: 6 }} />
            Welfare check or 911?
          </h2>
          <p>
            These are different tools and picking the wrong one has a real cost in either
            direction. <strong>Call 911</strong> when you have a concrete reason to believe
            something is happening <em>right now</em> — they told you they felt seriously
            unwell and then went quiet, you heard a fall or a cry, a neighbour reports
            something visibly wrong. <strong>Use the non-emergency line</strong> when you
            are genuinely worried but have no specific evidence of an emergency and simply
            cannot confirm they are safe.
          </p>
          <p>
            Worth saying plainly: requesting a welfare check is a normal, appropriate use
            of the non-emergency line. People hesitate because they are afraid of
            overreacting or wasting someone's time. Dispatchers handle these constantly.
            The failure mode that actually costs people is waiting an extra day because
            calling felt dramatic.
          </p>

          <h2>
            <Clock size={20} style={{ verticalAlign: '-3px', marginRight: 6 }} />
            What happens when officers arrive
          </h2>
          <p>
            This varies by jurisdiction and by how busy the agency is, so treat the
            following as the common shape rather than a guarantee. Typically officers
            knock, announce themselves, and try to get a response — often loudly, and
            often for longer than you would expect. They may walk the perimeter and look
            through windows. If someone answers and is clearly fine, that is the end of it.
          </p>
          <p>
            If nobody answers and there is reason to believe someone inside needs help,
            officers may look for a key holder, or may force entry. Whether and when they
            can do that is governed by local law and department policy — it is not
            automatic, and it is not something you can insist on. If you know a neighbour
            or building manager has a key, saying so on the call can spare a broken door.
          </p>
          <p>
            Timing varies widely. A welfare check is generally not dispatched ahead of
            active emergencies, so it can take anywhere from minutes to several hours. Ask
            the dispatcher what to expect, and ask whether you can be called back.
          </p>

          <h2>What it costs</h2>
          <p>
            The check itself is generally not billed to the person requesting it. Costs
            come from what follows: a locksmith or repair if entry is forced, or ambulance
            transport if they need medical care. Both vary considerably by area and by
            insurance, and neither is something to weigh against making the call.
          </p>

          <h2>If they find nothing wrong</h2>
          <p>
            This is the most common outcome, and it is not a wasted call — it is the
            answer you wanted. Two things are worth expecting.
          </p>
          <p>
            First, you may be told less than you hoped. Privacy rules limit what officers
            can disclose about a competent adult, so you may get confirmation that the
            person is safe without further detail. That is not obstruction; it is the same
            rule that protects your parent from anyone else who calls about them.
          </p>
          <p>
            Second, your parent may be upset. Being checked on by police can feel
            intrusive or humiliating to someone whose independence matters to them.
            Explaining that you could not reach them and had no other way to know usually
            helps more than apologising for overreacting — because you did not overreact.
            The thing worth changing is not your judgement, it is the information gap that
            forced you to guess.
          </p>

          <h2>How to not need this again</h2>
          <p>
            The reason an unanswered phone escalates to police is an information gap:
            silence could mean nothing or everything, and there is no fast way to tell
            which. Everything above is a way of resolving that gap after the fact, at the
            cost of a police visit and a difficult conversation.
          </p>
          <p>
            A daily check-in closes the gap before it opens. With{' '}
            <Link to="/daily-check-in-app-for-seniors/">Daily OK</Link>, your parent taps
            one button a day; if they miss it, you are alerted within a window you choose,
            rather than finding out during a call that happens to go unanswered. It is not
            monitoring — there is no tracking, no camera, and nothing to wear. It answers
            one question, once a day, which is the question you were trying to answer by
            calling the police.
          </p>
          <p>
            It also will not help in every case. If your worry is a fall that needs an
            immediate response, a medical alert pendant with dispatch is a better fit, and
            we say so on our{' '}
            <Link to="/compare/daily-ok-vs-life-alert/">comparison with Life Alert</Link>.
            A check-in tells you something is wrong; it does not summon help on its own.
          </p>

          <h2>Frequently asked questions</h2>
          {FAQS.map((f) => (
            <div key={f.q}>
              <h3>{f.q}</h3>
              <p>{f.a}</p>
            </div>
          ))}

          <h2>Related guides</h2>
          <div className="lp-links">
            <Link to="/what-to-do/elderly-father-not-answering-phone/">
              Elderly parent not answering: the first 30 minutes
            </Link>
            <Link to="/what-to-do/grandpa-wont-pick-up/">
              Grandparent won't pick up the phone
            </Link>
            <Link to="/what-to-do/">All "not answering the phone" guides</Link>
            <Link to="/daily-check-in-app-for-seniors/">Daily check-ins for seniors</Link>
          </div>
        </div>
      </section>
    </>
  )
}
