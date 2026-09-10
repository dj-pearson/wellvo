import { Link } from 'react-router-dom'
import SEO from '../components/SEO'
import './NotFound.css'

/**
 * The 404 page (US-SEO016).
 *
 * This component existed and was routed, but nothing ever prerendered it, so
 * Cloudflare Pages answered every unknown URL with its own generic page. It
 * could only render on a client-side navigation inside an already-loaded SPA —
 * which is the one situation where nobody is lost. A direct hit, a stale
 * backlink and a crawler all got the generic page instead.
 *
 * scripts/emit-404.mjs now writes this to dist/client/404.html, which Pages
 * serves for any unmatched path with a real 404 status.
 *
 * The recovery links are the point. A 404 with one "Back to Home" button ends
 * the visit for anyone who arrived from a stale link to a specific guide; the
 * hubs below give them somewhere to go that is probably what they wanted.
 */
export default function NotFound() {
  return (
    <div className="not-found section">
      {/*
        noindex, follow — this page must never rank, but its links are worth
        crawling. It also keeps itself out of sitemap.xml and llms.txt, both of
        which skip any page carrying a noindex robots tag.
      */}
      <SEO
        title="Page not found"
        description="That page doesn't exist or has moved. Here's where to find what you were looking for on Daily OK."
        path="/404"
        noindex
      />

      <div className="container not-found-inner">
        <div className="not-found-code">404</div>
        <h1>Page not found</h1>
        <p>The page you're looking for doesn't exist or has been moved.</p>

        <h2>Try one of these instead</h2>
        <ul className="not-found-links">
          <li>
            <Link to="/">How Daily OK works</Link> — the once-a-day "I'm OK"
            check-in, and what happens when it's missed.
          </li>
          <li>
            <Link to="/what-to-do/">
              What to do when someone won't answer the phone
            </Link>{' '}
            — step-by-step guides by relationship.
          </li>
          <li>
            <Link to="/compare/">Daily OK vs. the alternatives</Link> — honest
            head-to-heads with medical alert and family safety apps.
          </li>
          <li>
            <Link to="/pricing/">Pricing &amp; plans</Link>
          </li>
          <li>
            <Link to="/support/">Support &amp; FAQ</Link> — or email{' '}
            <a href="mailto:support@dailyok.net">support@dailyok.net</a>.
          </li>
        </ul>

        <Link to="/" className="btn btn-primary">Back to Home</Link>
      </div>
    </div>
  )
}
