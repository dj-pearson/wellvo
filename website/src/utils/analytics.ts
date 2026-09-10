// Privacy-first analytics events via Cloudflare Web Analytics.
// No cookies, no PII, no GDPR banner required — which is why this one is not
// behind the consent gate that GA4 needs (see src/lib/consent.ts).
//
// The beacon script sets window.__cfBeacon when it loads. Since US-SEO004 that
// only happens when VITE_CF_ANALYTICS_TOKEN is configured at build time, so the
// guard below is the normal path in development, not an edge case.

declare global {
  interface Window {
    /** Present once static.cloudflareinsights.com/beacon.min.js has loaded. */
    __cfBeacon?: unknown
  }
}

export function trackEvent(name: string) {
  if (typeof window === 'undefined' || !window.__cfBeacon) return
  // Cloudflare Web Analytics tracks page views automatically; custom events
  // ride along as performance marks.
  performance.mark(`cf-${name}`)
}
