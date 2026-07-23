/**
 * Cookie-consent + Google Analytics gating for the Daily OK website.
 *
 * Google Analytics (GA4) sets cookies and transfers data to Google, so under
 * the EU ePrivacy Directive / GDPR it requires PRIOR opt-in consent. This
 * module keeps GA fully unloaded until the visitor explicitly accepts:
 *   - No stored choice  -> banner shown, GA not loaded.
 *   - "granted"         -> GA loaded.
 *   - "denied"          -> GA never loaded.
 *   - Global Privacy Control present -> treated as an opt-out, GA never loaded.
 *
 * The GA tag is intentionally NOT in the prerendered <head> (see
 * pages/+onRenderHtml.tsx); it is injected here only after consent.
 */

const CONSENT_KEY = 'dailyok_cookie_consent'
const GA_MEASUREMENT_ID = 'G-J2H67EW9JY'

export type ConsentChoice = 'granted' | 'denied'

export function getStoredConsent(): ConsentChoice | null {
  if (typeof window === 'undefined') return null
  try {
    const value = window.localStorage.getItem(CONSENT_KEY)
    return value === 'granted' || value === 'denied' ? value : null
  } catch {
    return null
  }
}

export function storeConsent(choice: ConsentChoice): void {
  if (typeof window === 'undefined') return
  try {
    window.localStorage.setItem(CONSENT_KEY, choice)
  } catch {
    // Storage may be unavailable (private mode / blocked); fail closed.
  }
}

/**
 * Global Privacy Control — a legally recognized opt-out preference signal
 * (honored under CPRA, Colorado, Connecticut, etc.). When present we treat
 * analytics as declined without prompting.
 */
export function hasGlobalPrivacyControlOptOut(): boolean {
  if (typeof navigator === 'undefined') return false
  return (navigator as Navigator & { globalPrivacyControl?: boolean }).globalPrivacyControl === true
}

let gaLoaded = false

/**
 * Inject and initialize GA4. Idempotent and safe to call more than once.
 * Only call after consent === 'granted'.
 */
export function loadGoogleAnalytics(): void {
  if (gaLoaded || typeof window === 'undefined' || typeof document === 'undefined') return
  gaLoaded = true

  const script = document.createElement('script')
  script.async = true
  script.src = `https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}`
  document.head.appendChild(script)

  const w = window as unknown as { dataLayer: unknown[]; gtag: (...args: unknown[]) => void }
  w.dataLayer = w.dataLayer || []
  w.gtag = function gtag() {
    // GA expects the raw `arguments` object pushed onto dataLayer.
    // eslint-disable-next-line prefer-rest-params
    w.dataLayer.push(arguments)
  }
  w.gtag('js', new Date())
  w.gtag('config', GA_MEASUREMENT_ID, { anonymize_ip: true })
}
