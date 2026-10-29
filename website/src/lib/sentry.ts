import type { Breadcrumb, ErrorEvent as SentryEvent } from '@sentry/react'

/**
 * Browser error reporting for the Daily OK website (admin console + marketing).
 * This is the frontend half of platform-wide error tracking; the edge-functions
 * server ships the backend half via `@sentry/deno`. Both route to the same
 * Daily OK Sentry project.
 *
 * The DSN is a public, write-only ingest key (safe to embed in client JS), so
 * the project DSN is baked in as a default and reporting works with zero build
 * config. Override or disable per-environment via Vite env vars:
 *   VITE_SENTRY_DSN      — override the routing DSN
 *   VITE_SENTRY_ENABLED  — set to "false" to disable (e.g. local dev)
 *
 * The SDK (~28 KB gz) is not on the critical path: it is imported dynamically
 * once the browser is idle after hydration. Errors raised before then (window
 * errors, rejections, and captureError calls) are buffered and replayed. The
 * ingest host must stay in public/_headers connect-src or every event is
 * blocked by CSP.
 */

// Public Daily OK ingest DSN (write-only; safe to embed). Overridable via env.
const DEFAULT_DSN =
  'https://d729109123ff47e2f0ac8ba1389f7c6f@o4510398791352320.ingest.us.sentry.io/4511770308182016'

// Bound the pre-load buffer so an error loop can't grow memory unbounded.
const MAX_PENDING = 20

type SentryModule = typeof import('@sentry/react')
type Pending = { error: unknown; context?: Record<string, unknown> }

let started = false
let sentry: SentryModule | null = null
let pending: Pending[] = []

function resolveDsn(): string | null {
  const enabled = (import.meta.env.VITE_SENTRY_ENABLED ?? 'true').toString().toLowerCase()
  if (enabled === 'false' || enabled === '0' || enabled === 'no') return null
  return import.meta.env.VITE_SENTRY_DSN || DEFAULT_DSN
}

/**
 * Strip the query string and fragment from a URL and collapse invite tokens.
 * Invite links carry secrets (`/invite/<token>?code=…`) and auth redirects put
 * `#access_token=…` in the fragment; none of it may leave the browser.
 */
export function scrubUrl(url: string): string {
  const cut = url.search(/[?#]/)
  const bare = cut === -1 ? url : url.slice(0, cut)
  return bare.replace(/\/invite\/[^/]+/g, '/invite/:token')
}

/** beforeSend: scrub the page URL and any URL-bearing request fields. */
export function scrubEvent(event: SentryEvent): SentryEvent {
  const req = event.request
  if (req) {
    if (req.url) req.url = scrubUrl(req.url)
    delete req.query_string
    delete req.cookies
    if (req.headers) {
      for (const key of Object.keys(req.headers)) {
        if (key.toLowerCase() === 'referer') req.headers[key] = scrubUrl(req.headers[key])
      }
    }
  }
  if (event.breadcrumbs) event.breadcrumbs = event.breadcrumbs.map(scrubBreadcrumb)
  return event
}

/** beforeBreadcrumb: scrub navigation from/to and fetch/xhr request URLs. */
export function scrubBreadcrumb(crumb: Breadcrumb): Breadcrumb {
  const data = crumb.data
  if (data) {
    for (const key of ['url', 'from', 'to']) {
      if (typeof data[key] === 'string') data[key] = scrubUrl(data[key])
    }
  }
  return crumb
}

function enqueue(error: unknown, context?: Record<string, unknown>): void {
  if (pending.length < MAX_PENDING) pending.push({ error, context })
}

const onWindowError = (e: ErrorEvent) => enqueue(e.error ?? e.message)
const onRejection = (e: PromiseRejectionEvent) => enqueue(e.reason)

async function load(dsn: string): Promise<void> {
  try {
    const mod = await import('@sentry/react')
    mod.init({
      dsn,
      environment: import.meta.env.VITE_SENTRY_ENVIRONMENT || 'production',
      release: import.meta.env.VITE_SENTRY_RELEASE || undefined,
      // Errors only for this static marketing/admin site — no perf tracing.
      tracesSampleRate: 0,
      sendDefaultPii: false,
      beforeSend: scrubEvent,
      beforeBreadcrumb: scrubBreadcrumb,
    })
    sentry = mod
    // Sentry's own global handlers are live now; hand over and replay.
    window.removeEventListener('error', onWindowError)
    window.removeEventListener('unhandledrejection', onRejection)
    const queued = pending
    pending = []
    for (const p of queued) captureError(p.error, p.context)
  } catch {
    // Telemetry must never break the app (offline, blocked by an extension…).
    pending = []
    window.removeEventListener('error', onWindowError)
    window.removeEventListener('unhandledrejection', onRejection)
  }
}

/**
 * Schedule Sentry to load once the browser is idle. Idempotent and never
 * throws. Call from the client entry (`+onRenderClient`); prerender/SSR skips it.
 */
export function initSentry(): void {
  if (started) return
  if (typeof window === 'undefined') return
  const dsn = resolveDsn()
  if (!dsn) return
  started = true
  try {
    window.addEventListener('error', onWindowError)
    window.addEventListener('unhandledrejection', onRejection)
    const run = () => void load(dsn)
    if (typeof window.requestIdleCallback === 'function') {
      window.requestIdleCallback(run, { timeout: 5000 })
    } else {
      setTimeout(run, 2000)
    }
  } catch {
    // Swallow — never let telemetry surface as an app error.
  }
}

/**
 * Report a handled error (e.g. from a React error boundary). Buffered until
 * the SDK has loaded; dropped if initSentry() never ran. Never throws.
 */
export function captureError(error: unknown, context?: Record<string, unknown>): void {
  if (!started) return
  if (!sentry) {
    enqueue(error, context)
    return
  }
  try {
    sentry.captureException(error, context ? { extra: context } : undefined)
  } catch {
    // Swallow — never let telemetry surface as an app error.
  }
}
