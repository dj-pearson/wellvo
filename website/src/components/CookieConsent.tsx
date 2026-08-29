import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  getStoredConsent,
  storeConsent,
  loadGoogleAnalytics,
  hasGlobalPrivacyControlOptOut,
} from '../lib/consent'
import './CookieConsent.css'

/**
 * Opt-in cookie-consent banner. Analytics (Google Analytics) stays unloaded
 * until the visitor accepts. Renders nothing during SSR/prerender and until
 * the client decides, so no banner is baked into the static HTML.
 */
export default function CookieConsent() {
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    // Honor an existing choice or a Global Privacy Control opt-out signal.
    if (hasGlobalPrivacyControlOptOut()) {
      storeConsent('denied')
      return
    }
    const stored = getStoredConsent()
    if (stored === 'granted') {
      loadGoogleAnalytics()
      return
    }
    if (stored === 'denied') return
    // Deliberate mount-time reveal: the banner must stay out of the prerendered
    // HTML and appear only after hydration confirms no prior choice exists.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setVisible(true)
  }, [])

  const accept = () => {
    storeConsent('granted')
    loadGoogleAnalytics()
    setVisible(false)
  }

  const decline = () => {
    storeConsent('denied')
    setVisible(false)
  }

  if (!visible) return null

  return (
    <div
      className="cookie-consent"
      role="dialog"
      aria-modal="false"
      aria-labelledby="cookie-consent-title"
      aria-describedby="cookie-consent-desc"
    >
      <div className="cookie-consent-inner">
        <div className="cookie-consent-text">
          <p id="cookie-consent-title" className="cookie-consent-title">
            We value your privacy
          </p>
          <p id="cookie-consent-desc">
            We use strictly necessary cookies to run this site. With your consent we also use
            Google Analytics to understand how the site is used. Analytics stays off unless you
            accept. See our <Link to="/cookies/">Cookie Notice</Link> and{' '}
            <Link to="/privacy/">Privacy Policy</Link>.
          </p>
        </div>
        <div className="cookie-consent-actions">
          <button type="button" className="btn btn-outline" onClick={decline}>
            Decline
          </button>
          <button type="button" className="btn btn-primary" onClick={accept}>
            Accept analytics
          </button>
        </div>
      </div>
    </div>
  )
}
