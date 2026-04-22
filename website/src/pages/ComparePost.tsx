import { Link, useParams } from 'react-router-dom'
import { Helmet } from 'react-helmet-async'
import { competitors, getCompetitor, type FeatureRow } from '../data/competitors'
import './Compare.css'

const SLUG_PREFIX = 'daily-ok-vs-'

export default function ComparePost() {
  const { fullSlug } = useParams<{ fullSlug: string }>()
  // URLs follow the /compare/daily-ok-vs-{slug} pattern; the competitor JSON
  // slug is the suffix after the prefix.
  const slug = fullSlug?.startsWith(SLUG_PREFIX) ? fullSlug.slice(SLUG_PREFIX.length) : fullSlug
  const competitor = slug ? getCompetitor(slug) : undefined

  if (!competitor) {
    return (
      <section className="section">
        <div className="container">
          <div className="compare-breadcrumb">
            <Link to="/compare">← All comparisons</Link>
          </div>
          <h1>Comparison not found</h1>
          <p>We don't have a head-to-head for that one yet.</p>
          <p><Link to="/compare">Browse all comparisons →</Link></p>
        </div>
      </section>
    )
  }

  const title = `Daily OK vs. ${competitor.name}: honest comparison (2026)`
  const description = competitor.daily_ok_verdict.split('.').slice(0, 2).join('.') + '.'
  const canonical = `https://dailyok.net/compare/daily-ok-vs-${competitor.slug}`

  const faqJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: competitor.faqs.map((f) => ({
      '@type': 'Question',
      name: f.q,
      acceptedAnswer: { '@type': 'Answer', text: f.a },
    })),
  }

  const articleJsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Article',
    headline: title,
    description,
    datePublished: competitor.last_verified,
    dateModified: competitor.last_verified,
    author: { '@type': 'Organization', name: 'Daily OK Editorial' },
    publisher: {
      '@type': 'Organization',
      name: 'Daily OK',
      url: 'https://dailyok.net',
    },
    mainEntityOfPage: canonical,
  }

  const siblings = competitors.filter((c) => c.slug !== competitor.slug).slice(0, 3)

  return (
    <>
      <Helmet>
        <title>{`${title} | Daily OK`}</title>
        <meta name="description" content={description} />
        <link rel="canonical" href={canonical} />
        <meta property="og:title" content={title} />
        <meta property="og:description" content={description} />
        <meta property="og:type" content="article" />
        <meta property="og:url" content={canonical} />
        <script type="application/ld+json">{JSON.stringify(faqJsonLd)}</script>
        <script type="application/ld+json">{JSON.stringify(articleJsonLd)}</script>
      </Helmet>

      <article className="compare-article">
        <div className="container" style={{ maxWidth: 960 }}>
          <div className="compare-breadcrumb">
            <Link to="/">Home</Link>
            <span>/</span>
            <Link to="/compare">Compare</Link>
            <span>/</span>
            <span>Daily OK vs. {competitor.name}</span>
          </div>

          <h1>Daily OK vs. {competitor.name}</h1>
          <p className="compare-subtitle">{competitor.tagline}</p>

          <div className="compare-snapshot" aria-label="Above-the-fold snapshot">
            <SnapshotRow label="Starting price (Daily OK)" value="$3.99 / month (Caregiver tier)" />
            <SnapshotRow label={`Starting price (${competitor.name})`} value={competitor.snapshot.starting_price} note={competitor.snapshot.starting_price_note} />
            <SnapshotRow label="Platform" value={competitor.snapshot.platform} />
            <SnapshotRow label="Fall detection" value={competitor.snapshot.fall_detection} />
            <SnapshotRow label="GPS / location" value={competitor.snapshot.gps_tracking} />
            <SnapshotRow label="Who gets alerts first" value={competitor.snapshot.who_gets_alerts_first} />
            <SnapshotRow label="Daily check-in" value={competitor.snapshot.daily_check_in} />
            <SnapshotRow label="Contract" value={competitor.snapshot.contract} />
          </div>

          <h2>The one-paragraph verdict</h2>
          <p className="compare-verdict">{competitor.daily_ok_verdict}</p>

          <div className="compare-best-grid">
            <div className="compare-best-card compare-best-card--us">
              <h3>Pick Daily OK if</h3>
              <ul>
                {competitor.best_for_daily_ok.map((b) => <li key={b}>{b}</li>)}
              </ul>
              <Link to="/pricing" className="btn btn-primary compare-best-cta">See Daily OK plans →</Link>
            </div>
            <div className="compare-best-card">
              <h3>Pick {competitor.name} if</h3>
              <ul>
                {competitor.best_for_competitor.map((b) => <li key={b}>{b}</li>)}
              </ul>
              <a href={competitor.company_url} target="_blank" rel="noopener noreferrer nofollow" className="compare-best-cta-secondary">Visit {competitor.name} →</a>
            </div>
          </div>

          <h2>Side-by-side feature matrix</h2>
          <div className="compare-matrix-wrap">
            <table className="compare-matrix">
              <thead>
                <tr>
                  <th>Feature</th>
                  <th>Daily OK</th>
                  <th>{competitor.name}</th>
                </tr>
              </thead>
              <tbody>
                {competitor.feature_matrix.map((row) => (
                  <tr key={row.feature}>
                    <td className="compare-matrix-label">{row.feature}</td>
                    <td className={cellClass(row, 'daily_ok')}>{row.daily_ok}</td>
                    <td className={cellClass(row, 'competitor')}>{row.competitor}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <h2>Pricing breakdown</h2>
          <div className="compare-pricing">
            <p><strong>Monthly:</strong> {competitor.pricing_breakdown.monthly}</p>
            <p><strong>One-year total cost:</strong> {competitor.pricing_breakdown.one_year_tco}</p>
            <p><strong>Three-year total cost:</strong> {competitor.pricing_breakdown.three_year_tco}</p>
          </div>

          {competitor.migration_guide && competitor.migration_guide.length > 0 && (
            <>
              <h2>If you're thinking about switching</h2>
              <ol className="compare-migration">
                {competitor.migration_guide.map((s, i) => <li key={i}>{s}</li>)}
              </ol>
            </>
          )}

          <h2>Frequently asked questions</h2>
          <div className="compare-faq">
            {competitor.faqs.map((f) => (
              <details key={f.q} className="compare-faq-item">
                <summary>{f.q}</summary>
                <p>{f.a}</p>
              </details>
            ))}
          </div>

          <div className="compare-footer-cta">
            <h3>Ready to try Daily OK?</h3>
            <p>
              Plans start at $3.99/month. No pendant, no GPS, no cameras — just one gentle morning
              prompt and a calm family-first alert chain if it's missed. Setup is designed to take
              under two minutes on your phone.
            </p>
            <Link to="/pricing" className="btn btn-primary">See the plans</Link>
          </div>

          {siblings.length > 0 && (
            <>
              <h2>Related comparisons</h2>
              <div className="compare-siblings">
                {siblings.map((s) => (
                  <Link key={s.slug} to={`/compare/daily-ok-vs-${s.slug}`} className="compare-sibling">
                    Daily OK vs. {s.name} →
                  </Link>
                ))}
              </div>
            </>
          )}

          <p className="compare-sources">
            <strong>Sources verified {competitor.last_verified}.</strong>{' '}
            {competitor.sources.map((s, i) => (
              <span key={s.url}>
                <a href={s.url} target="_blank" rel="noopener noreferrer nofollow">{s.title}</a>
                {i < competitor.sources.length - 1 && ' · '}
              </span>
            ))}
          </p>
        </div>
      </article>
    </>
  )
}

function SnapshotRow({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="compare-snapshot-row">
      <span className="compare-snapshot-label">{label}</span>
      <span className="compare-snapshot-value">
        {value}
        {note && <span className="compare-snapshot-note"> — {note}</span>}
      </span>
    </div>
  )
}

function cellClass(row: FeatureRow, side: 'daily_ok' | 'competitor'): string {
  if (!row.winner || row.winner === 'tie' || row.winner === 'different') return 'compare-matrix-cell'
  return row.winner === side ? 'compare-matrix-cell compare-matrix-cell--win' : 'compare-matrix-cell'
}
