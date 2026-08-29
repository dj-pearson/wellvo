import { Link, useParams } from 'react-router-dom'
import { trackEvent } from '../utils/analytics'
import SEO, { APP_STORE_URL } from '../components/SEO'
import { buildBreadcrumbJsonLd } from '../lib/breadcrumb'
import { getWhatToDoPage, LAST_UPDATED } from '../data/whatToDo'
import { ArrowRight, Phone, ShieldAlert, Clock, ClipboardList } from 'lucide-react'
import './ElderlyCare.css'
import './Landing.css'
import './WhatToDo.css'

export default function WhatToDo() {
  const { slug } = useParams<{ slug: string }>()
  const page = slug ? getWhatToDoPage(slug) : undefined

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

  const jsonLd = [
    {
      '@context': 'https://schema.org',
      '@type': 'FAQPage',
      mainEntity: page.faqs.map((f) => ({
        '@type': 'Question',
        name: f.q,
        acceptedAnswer: { '@type': 'Answer', text: f.a },
      })),
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
          <p className="wtd-byline">
            By the Daily OK Editorial Team · Last updated {LAST_UPDATED}
          </p>
          <div className="lp-tldr">
            <strong>Stay calm — work in order</strong>
            {page.intro}
          </div>
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

          <h2>Why this is specific to {page.who}</h2>
          <p>{page.context}</p>

          <h2>
            <Clock size={20} style={{ verticalAlign: '-3px', marginRight: 6 }} />
            The first 30 minutes
          </h2>
          <ol className="wtd-list">
            {page.first30.map((s, i) => (
              <li key={i}>{s}</li>
            ))}
          </ol>

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

          <h2>How to stop the panic happening again</h2>
          <p>{page.prevention}</p>
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
            <Link to="/check-in-app-for-elderly/">Check-in app for elderly parents</Link>
            <Link to="/peace-of-mind-app-for-elderly-parents/">Peace-of-mind app for elderly parents</Link>
            <Link to="/pricing/">Pricing &amp; plans</Link>
          </div>
        </div>
      </section>
    </>
  )
}
