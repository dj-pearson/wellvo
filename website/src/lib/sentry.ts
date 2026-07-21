import * as Sentry from '@sentry/react'

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
 */

// Public Daily OK ingest DSN (write-only; safe to embed). Overridable via env.
const DEFAULT_DSN =
  'https://d729109123ff47e2f0ac8ba1389f7c6f@o4510398791352320.ingest.us.sentry.io/4511770308182016'

let initialized = false

function resolveDsn(): string | null {
  const enabled = (import.meta.env.VITE_SENTRY_ENABLED ?? 'true').toString().toLowerCase()
  if (enabled === 'false' || enabled === '0' || enabled === 'no') return null
  return import.meta.env.VITE_SENTRY_DSN || DEFAULT_DSN
}

/**
 * Initialize Sentry once, in the browser only. Idempotent and never throws.
 * Call from the client entry (`+onRenderClient`); prerender/SSR skips it.
 */
export function initSentry(): void {
  if (initialized) return
  if (typeof window === 'undefined') return
  const dsn = resolveDsn()
  if (!dsn) return
  try {
    Sentry.init({
      dsn,
      environment: import.meta.env.VITE_SENTRY_ENVIRONMENT || 'production',
      release: import.meta.env.VITE_SENTRY_RELEASE || undefined,
      // Errors only for this static marketing/admin site — no perf tracing.
      tracesSampleRate: 0,
      sendDefaultPii: false,
    })
    initialized = true
  } catch {
    // Telemetry must never break the app.
  }
}

/**
 * Report a handled error (e.g. from a React error boundary). No-op until
 * initSentry() has run. Never throws.
 */
export function captureError(error: unknown, context?: Record<string, unknown>): void {
  if (!initialized) return
  try {
    Sentry.captureException(error, context ? { extra: context } : undefined)
  } catch {
    // Swallow — never let telemetry surface as an app error.
  }
}
