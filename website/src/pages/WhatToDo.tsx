import { Link, useParams } from 'react-router-dom'
import { trackEvent } from '../utils/analytics'
import SEO, { APP_STORE_URL } from '../components/SEO'
import { buildBreadcrumbJsonLd } from '../lib/breadcrumb'
import { getWhatToDoPage, LAST_UPDATED } from '../data/whatToDo'
import { ArrowRight, Phone, ShieldAlert, Clock, ClipboardList } from 'lucide-react'
import './ElderlyCare.css'
import './Landing.css'
import './WhatToDo.css'

/**
 * The landing page that best fits each relationship (US-WEB011).
 *
 * These pages previously appeared only in the "Related guides" list at the
 * foot of the page, alongside a generic CTA. Google reads a repeated
 * footer-style block as boilerplate, which is a large part of why all three
 * cornerstone pages had zero impressions while these guides ranked around
 * position 8.6. A contextual link inside the prevention section — the one
 * place on the page where the product is genuinely the answer — carries
 * real weight, and varying the destination and anchor per relationship keeps
 * it from collapsing into the same boilerplate.
 *
 * Teen, college, spouse and adult-child pages point at /child-safety/
 * instead: sending a worried parent of a teenager to a page about aging in
 * place would be worse for the reader, and a link nobody clicks helps nothing.
 */
const PREVENTION_LINK: Record<string, { path: string; anchor: string; label: string }> = {
  'elderly-father-not-answering-phone':
    { path: '/check-in-app-for-elderly/', anchor: 'how the check-in app for elderly parents works', label: 'Check-in app for elderly parents' },
  'grandpa-wont-pick-up':
    { path: '/daily-check-in-app-for-seniors/', anchor: 'a daily check-in app for seniors', label: 'Daily check-ins for seniors' },
  'teenage-daughter-not-answering-phone':
    { path: '/child-safety/', anchor: 'a check-in app for teens that is not location tracking', label: 'Check-ins for teens, without tracking' },
  'college-student-not-answering-phone':
    { path: '/child-safety/', anchor: 'a low-friction check-in for a student living away', label: 'Check-ins for a student living away' },
  'spouse-not-answering-phone':
    { path: '/check-in-app-for-elderly/', anchor: 'how a daily check-in works', label: 'How a daily check-in works' },
  'adult-child-not-answering-phone':
    { path: '/check-in-app-for-elderly/', anchor: 'how a daily check-in works', label: 'How a daily check-in works' },
}

const DEFAULT_PREVENTION_LINK = {
  path: '/check-in-app-for-elderly/',
  anchor: 'how a daily check-in works',
  label: 'How a daily check-in works',
}

export default function WhatToDo() {
  const { slug } = useParams<{ slug: string }>()
  const page = slug ? getWhatToDoPage(slug) : undefined
  const preventionLink =
    (page && PREVENTION_LINK[page.slug]) || DEFAULT_PREVENTION_LINK

  if (!page) {
    return (
      <section className="section">
        <div className="container lp-prose">
          <h1>Guide not found</h1>
          <p>We don't have that specific guide. Browse all of them:</p>
          <p>
            <Link to="/what-to-do/">All "didn't answer the phone" guides →</Link>
          </p>
        </div>
      </section>
    )
  }

  // The escalation criteria are the highest-intent thing on the page and were
  // previously prose only. Expressing them as a Question makes them eligible
  // for AI Overview and People Also Ask extraction, which is where the click
  // is currently going (US-WEB014).
  //
  // HowTo markup is deliberately NOT used here. Google removed HowTo rich
  // results from Search, so it would add weight to the payload and change
  // nothing — and the first-30-minutes list is a triage sequence with branches,
  // not the linear procedure HowTo describes.
  // page.who is written in second person for body copy ("your elderly
  // parent"); a question asked in the searcher's own voice needs first person.
  const whoFirstPerson = page.who.replace(/^your\b/, 'my')

  const escalationQuestion = {
    '@type': 'Question',
    name: `When should I escalate if ${whoFirstPerson} isn't answering the phone?`,
    acceptedAnswer: {
      '@type': 'Answer',
      text: `Escalate to a welfare check or emergency services if any of the following is true: ${page.escalateWhen
        .map((e) => e.replace(/\.$/, ''))
        .join('; ')}. Call 911 only if you have a concrete reason to believe there is immediate danger; otherwise the right route is a non-emergency police welfare check.`,
    },
  }

  const jsonLd = [
    {
      '@context': 'https://schema.org',
      '@type': 'FAQPage',
      mainEntity: [
        escalationQuestion,
        ...page.faqs.map((f) => ({
          '@type': 'Question',
          name: f.q,
          acceptedAnswer: { '@type': 'Answer', text: f.a },
        })),
      ],
    },
    buildBreadcrumbJsonLd([
      { name: 'Home', path: '/' },
      { name: 'What to do', path: '/what-to-do' },
      { name: page.h1, path: `/what-to-do/${page.slug}` },
    ]),
  ]

  return (
    <>
      <SEO
        title={page.title}
        description={page.metaDescription}
        path={`/what-to-do/${page.slug}`}
        ogType="article"
        jsonLd={jsonLd}
      />

      <section className="ec-hero">
        <div className="container ec-hero-inner">
          <nav className="lp-breadcrumb" aria-label="Breadcrumb">
            <Link to="/">Home</Link> &nbsp;/&nbsp; <Link to="/what-to-do/">What to do</Link> &nbsp;/&nbsp;{' '}
            {page.who}
          </nav>
          <h1 className="ec-hero-title">{page.h1}</h1>
          {/*
            Immediately under the H1 and written to stand alone (US-WEB014):
            at position 8.6 this result sits below an AI Overview, so the page
            has to supply a quotable answer rather than an empathetic warm-up.
          */}
          <p className="wtd-answer">{page.directAnswer}</p>
          <p className="wtd-byline">
            By the Daily OK Editorial Team · Last updated {LAST_UPDATED}
          </p>
        </div>
      </section>

      <section className="section">
        <div className="container lp-prose">
          <div className="wtd-disclaimer" role="note">
            <strong>This is general guidance, not medical or emergency advice.</strong>{' '}
            If you believe someone is in immediate danger, call your local emergency
            number (911 in the US) now. Daily OK is not a medical device and does not
            provide monitoring or emergency dispatch.
          </div>

          {/*
            The checklist is the first substantive thing on the page, above the
            empathetic framing, as a clean <ol> that can be lifted whole into a
            featured snippet (US-WEB014). Someone arriving here is frightened and
            wants the next action, not a warm-up.
          */}
          <h2>
            <Clock size={20} style={{ verticalAlign: '-3px', marginRight: 6 }} />
            The first 30 minutes
          </h2>
          <ol className="wtd-list">
            {page.first30.map((s, i) => (
              <li key={i}>{s}</li>
            ))}
          </ol>

          <h2>Why this is specific to {page.who}</h2>
          <p>{page.intro}</p>
          <p>{page.context}</p>

          <h2>
            <ClipboardList size={20} style={{ verticalAlign: '-3px', marginRight: 6 }} />
            The first 24 hours
          </h2>
          <ol className="wtd-list">
            {page.first24.map((s, i) => (
              <li key={i}>{s}</li>
            ))}
          </ol>

          <h2>
            <ShieldAlert size={20} style={{ verticalAlign: '-3px', marginRight: 6 }} />
            When to call 911 vs. request a welfare check
          </h2>
          <p>
            These are different tools. <strong>Call 911</strong> when you have a
            concrete, specific reason to believe there is an emergency happening{' '}
            <em>right now</em> — for example, the person said they felt seriously
            unwell and then went silent, or there is evidence of an accident. 911 is
            for immediate danger, not general worry.
          </p>
          <p>
            <strong>Request a welfare check</strong> (via the police{' '}
            <em>non-emergency</em> line) when you are genuinely worried but have no
            specific evidence of an emergency, and you cannot otherwise confirm the
            person is safe. A welfare check is a routine, appropriate use of the
            non-emergency line — you are not wasting anyone's time by requesting one
            when you have a real reason for concern.
          </p>
          <p>For {page.who}, escalate toward a welfare check or 911 when:</p>
          <ul className="wtd-list">
            {page.escalateWhen.map((s, i) => (
              <li key={i}>{s}</li>
            ))}
          </ul>

          <h2>
            <Phone size={20} style={{ verticalAlign: '-3px', marginRight: 6 }} />
            How to request a welfare check (script)
          </h2>
          <p>Call the police non-emergency line for the area where they live and say:</p>
          <blockquote className="wtd-script">
            "Hello, I'd like to request a welfare check. I'm concerned about{' '}
            <em>[name]</em>, my <em>[relationship]</em>, who lives at{' '}
            <em>[full address, including apartment/unit]</em>. I haven't been able
            to reach them since <em>[time/date of last contact]</em>, which is
            unusual for them. They are <em>[age, relevant medical conditions, a
            brief physical description]</em>. Could an officer check that they're
            okay? My name is <em>[your name]</em> and my number is{' '}
            <em>[your phone]</em>."
          </blockquote>
          <p>
            Have the address, a description, any health conditions, and your last
            contact time ready before you call — it makes the request faster and
            helps officers prioritize.
          </p>

          {page.variants?.map((v) => (
            <section key={v.heading}>
              <h2>{v.heading}</h2>
              <p>{v.body}</p>
              {v.points && (
                <ul>
                  {v.points.map((pt) => (
                    <li key={pt}>{pt}</li>
                  ))}
                </ul>
              )}
            </section>
          ))}

          <h2>How to stop the panic happening again</h2>
          <p>{page.prevention}</p>
          <p>
            If that is where you have landed, read{' '}
            <Link to={preventionLink.path}>{preventionLink.anchor}</Link> — it covers what the
            daily check-in looks like on both sides, and what happens when one is missed.
          </p>
          <div className="hero-actions" style={{ marginTop: '1rem' }}>
            <a
              href={APP_STORE_URL}
              className="btn btn-primary btn-lg"
              target="_blank"
              rel="noopener noreferrer"
              onClick={() => trackEvent('download_cta_click')}
            >
              Set up a daily check-in
              <ArrowRight size={18} />
            </a>
            <Link to="/pricing/" className="btn btn-secondary btn-lg">
              View plans
            </Link>
          </div>

          <h2>Frequently asked questions</h2>
          <div className="faq-list">
            {page.faqs.map((f, i) => (
              <details key={i} className="faq-item-detail">
                <summary>{f.q}</summary>
                <p>{f.a}</p>
              </details>
            ))}
          </div>

          <h2>Related guides</h2>
          <div className="lp-links">
            <Link to="/what-to-do/">All "didn't answer the phone" guides</Link>
            <Link to={preventionLink.path}>{preventionLink.label}</Link>
            <Link to="/pricing/">Pricing &amp; plans</Link>
          </div>
        </div>
      </section>
    </>
  )
}
