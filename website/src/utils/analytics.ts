// Privacy-first analytics events via Cloudflare Web Analytics
// No cookies, no PII, no GDPR banner required
export function trackEvent(name: string) {
  // Cloudflare Web Analytics custom events
  if (typeof window !== 'undefined' && (window as any).__cfBeacon) {
    // CF Web Analytics tracks page views automatically
    // Custom events tracked via performance entries
    performance.mark(`cf-${name}`)
  }
}
