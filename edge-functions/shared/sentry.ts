/**
 * Sentry error reporting for the Daily OK edge-functions server.
 *
 * All unhandled/handled errors flowing through `logError` (shared/logger.ts) and
 * the top-level request handler are forwarded here and routed to the Daily OK
 * Sentry project. This is the backend half of platform-wide error tracking; the
 * website ships the browser half via `@sentry/react`.
 *
 * Config:
 *   SENTRY_DSN          — override the routing DSN (defaults to the Daily OK DSN)
 *   SENTRY_ENVIRONMENT  — e.g. "production" | "staging" (defaults to "production")
 *   SENTRY_RELEASE      — optional release/version tag for traceability
 *   SENTRY_ENABLED      — set to "false"/"0" to disable reporting entirely
 *
 * A Sentry DSN is a public, write-only ingest key (safe to embed), so the
 * project DSN is baked in as a default and everything works with zero extra
 * config. Init and capture are both wrapped in try/catch — telemetry must never
 * crash the server or fail a request.
 */

import * as Sentry from "@sentry/deno";

// Public Daily OK ingest DSN (write-only; safe to embed). Overridable via env.
const DEFAULT_DSN =
  "https://d729109123ff47e2f0ac8ba1389f7c6f@o4510398791352320.ingest.us.sentry.io/4511770308182016";

function readDsn(): string | null {
  const enabled = (Deno.env.get("SENTRY_ENABLED")?.trim() || "true").toLowerCase();
  if (enabled === "false" || enabled === "0" || enabled === "no") return null;
  return Deno.env.get("SENTRY_DSN")?.trim() || DEFAULT_DSN;
}

let initialized = false;

/**
 * Initialize the Sentry client once at server startup. Idempotent and safe to
 * call unconditionally — never throws.
 */
export function initSentry(): void {
  if (initialized) return;
  const dsn = readDsn();
  if (!dsn) return;
  try {
    Sentry.init({
      dsn,
      environment: Deno.env.get("SENTRY_ENVIRONMENT")?.trim() || "production",
      release: Deno.env.get("SENTRY_RELEASE")?.trim() || undefined,
      // This service is a tight JSON API, not a traced app — errors only.
      tracesSampleRate: 0,
      // Don't capture request bodies / headers by default (PII: user data,
      // JWTs, push tokens). Errors carry their own message + our explicit extras.
      sendDefaultPii: false,
    });
    initialized = true;
  } catch (err) {
    // Never let a telemetry misconfiguration take down the server.
    console.error(
      JSON.stringify({
        timestamp: new Date().toISOString(),
        level: "warn",
        message: "Sentry init failed; continuing without error reporting",
        error: err instanceof Error ? err.message : String(err),
      }),
    );
  }
}

/**
 * Report an error to Sentry. No-op if Sentry never initialized. `message` gives
 * the event a stable title when `error` is not a real Error; `context` is
 * attached as structured extra data. Never throws.
 */
export function captureError(
  message: string,
  error?: unknown,
  context?: Record<string, unknown>,
): void {
  if (!initialized) return;
  try {
    const exception = error instanceof Error ? error : new Error(message);
    Sentry.captureException(exception, (scope) => {
      scope.setContext("logger", { message, ...(context ?? {}) });
      if (context?.path) scope.setTag("route", String(context.path));
      return scope;
    });
  } catch {
    // Swallow — telemetry must never break a request path.
  }
}
