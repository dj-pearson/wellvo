import { Link } from 'react-router-dom'
import { Helmet } from 'react-helmet-async'
import { canonicalUrl } from '../lib/canonical'
import { competitors } from '../data/competitors'
import './Compare.css'

export default function Compare() {
  return (
    <>
      <Helmet>
        <title>Daily OK vs. alternatives — honest comparisons | Daily OK</title>
        <meta
          name="description"
          content="Side-by-side comparisons of Daily OK versus the most-searched medical alert and family safety apps. Honest verdicts, real pricing, no manufactured star ratings."
        />
        <link rel="canonical" href={canonicalUrl('/compare')} />
        <meta property="og:title" content="Daily OK vs. alternatives — honest comparisons" />
        <meta
          property="og:description"
          content="Honest head-to-head comparisons of Daily OK against Life Alert, Life360, Snug Safety, and more."
        />
        <meta property="og:type" content="website" />
        <meta property="og:url" content={canonicalUrl('/compare')} />
      </Helmet>

      <section className="section compare-hero">
        <div className="container">
          <div className="compare-breadcrumb">
            <Link to="/">Home</Link>
            <span>/</span>
            <span>Compare</span>
          </div>
          <h1>Daily OK vs. the alternatives</h1>
          <p className="compare-lede">
            Honest head-to-head comparisons — including the categories where the other tool is the
            better choice. We write these the way we'd want a friend to explain it over coffee, not
            the way a product team would pitch it. Pricing, feature matrices, and migration notes
            for each.
          </p>
        </div>
      </section>

      <section className="section">
        <div className="container">
          <div className="compare-grid">
            {competitors.map((c) => (
              <Link key={c.slug} to={`/compare/daily-ok-vs-${c.slug}/`} className="compare-card">
                <div className="compare-card-title">Daily OK vs. {c.name}</div>
                <div className="compare-card-tagline">{c.tagline}</div>
                <div className="compare-card-verdict">
                  {c.daily_ok_verdict.split('.')[0] + '.'}
                </div>
                <div className="compare-card-cta">Read the full comparison →</div>
              </Link>
            ))}
          </div>
        </div>
      </section>

      <section className="section compare-cta">
        <div className="container" style={{ textAlign: 'center' }}>
          <h2>Already know which one you want?</h2>
          <p>Daily OK plans start at $3.99/month. No hardware. No contract. Cancel anytime.</p>
          <Link to="/pricing/" className="btn btn-primary">See Daily OK plans</Link>
          <p className="compare-cta-links">
            Still deciding what you actually need? Read what a{' '}
            <Link to="/check-in-app-for-elderly/">check-in app for elderly parents</Link> does
            and does not do, why a{' '}
            <Link to="/daily-check-in-app-for-seniors/">daily check-in app for seniors</Link>{' '}
            suits aging in place, or how Daily OK works as a{' '}
            <Link to="/peace-of-mind-app-for-elderly-parents/">
              peace-of-mind app for elderly parents
            </Link>{' '}
            when you live far away.
          </p>
        </div>
      </section>
    </>
  )
}
