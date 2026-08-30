import { Link } from 'react-router-dom'
import SEO from '../components/SEO'
import { buildBreadcrumbJsonLd } from '../lib/breadcrumb'
import { whatToDoPages, LAST_UPDATED } from '../data/whatToDo'
import './ElderlyCare.css'
import './Landing.css'
import './WhatToDo.css'

export default function WhatToDoIndex() {
  const jsonLd = buildBreadcrumbJsonLd([
    { name: 'Home', path: '/' },
    { name: 'What to do', path: '/what-to-do' },
  ])

  return (
    <>
      <SEO
        title="What to Do When Someone Doesn't Answer the Phone — Calm Guides"
        description="Calm, step-by-step guides for when a parent, grandparent, teen, college student or spouse isn't answering the phone: the first 30 minutes, the first 24 hours, and when to escalate."
        path="/what-to-do"
        jsonLd={jsonLd}
      />

      <section className="ec-hero">
        <div className="container ec-hero-inner">
          <nav className="lp-breadcrumb" aria-label="Breadcrumb">
            <Link to="/">Home</Link> &nbsp;/&nbsp; What to do
          </nav>
          <h1 className="ec-hero-title">
            "They're not answering the phone." <span className="hero-highlight">Here's a calm plan.</span>
          </h1>
          <p className="wtd-byline">By the Daily OK Editorial Team · Last updated {LAST_UPDATED}</p>
          <div className="lp-tldr">
            <strong>Pick the situation</strong>
            Each guide walks the same calm sequence — the first 30 minutes, the
            first 24 hours, and exactly when to escalate to a welfare check or 911 —
            tailored to the specific relationship, because the right advice for a
            dementia parent is not the right advice for a teenager.
          </div>
        </div>
      </section>

      <section className="section">
        <div className="container lp-prose">
          <div className="wtd-disclaimer" role="note">
            <strong>General guidance, not medical or emergency advice.</strong> If
            you believe someone is in immediate danger, call 911 (US) now.
          </div>
          <h2>Choose the guide that fits</h2>
          <div className="wtd-index-grid">
            {whatToDoPages.map((p) => (
              <Link key={p.slug} to={`/what-to-do/${p.slug}/`} className="wtd-index-card">
                <span className="wtd-index-card-title">{p.h1}</span>
                <span className="wtd-index-card-sub">{p.metaDescription}</span>
              </Link>
            ))}
          </div>

          <h2>Stop having to look this up</h2>
          <p>
            Every guide here ends at the same place: the reason an unanswered call is
            frightening is that silence could mean nothing or everything, and there is no fast
            way to tell. A once-a-day check-in closes that gap. Depending on who you are
            worried about, start with the{' '}
            <Link to="/check-in-app-for-elderly/">check-in app for elderly parents</Link>, the{' '}
            <Link to="/daily-check-in-app-for-seniors/">daily check-in app for seniors</Link>{' '}
            aging in place, or the{' '}
            <Link to="/peace-of-mind-app-for-elderly-parents/">
              peace-of-mind app for elderly parents
            </Link>{' '}
            if you are the one doing the worrying from a distance.
          </p>
        </div>
      </section>
    </>
  )
}
