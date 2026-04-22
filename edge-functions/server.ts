/**
 * Daily OK Edge Functions Server
 *
 * A lightweight HTTP server that routes requests to individual edge functions.
 * Runs as a Docker container alongside self-hosted Supabase on Coolify.
 */

// =============================================================================
// Environment variable validation — fail fast on misconfiguration
// =============================================================================
const REQUIRED_ENV_VARS = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "JWT_SECRET"] as const;

for (const varName of REQUIRED_ENV_VARS) {
  const value = Deno.env.get(varName);
  if (!value || value.trim() === "") {
    console.error(`FATAL: Required environment variable ${varName} is missing or empty. Server cannot start.`);
    Deno.exit(1);
  }
}

const PORT = parseInt(Deno.env.get("PORT") || "9000"); // Optional, defaults to 9000

// Import auth
import { verifyRequest, type AuthResult } from "./shared/auth.ts";
import { checkRateLimit, checkServiceRoleRateLimit } from "./shared/rate-limiter.ts";
import { logInfo, logError, withRequestLogging } from "./shared/logger.ts";

// Import function handlers
import { handleSendCheckinNotification } from "./functions/send-checkin-notification/index.ts";
import { handleProcessCheckinResponse } from "./functions/process-checkin-response/index.ts";
import { handleEscalationTick } from "./functions/escalation-tick/index.ts";
import { handleOnDemandCheckin } from "./functions/on-demand-checkin/index.ts";
import { handleSubscriptionWebhook } from "./functions/subscription-webhook/index.ts";
import { handleInviteReceiver } from "./functions/invite-receiver/index.ts";
import { handleSubscriptionCancellation } from "./functions/subscription-cancellation/index.ts";
import { handleConfirmDelivery } from "./functions/confirm-delivery/index.ts";
import { handleReportLocation } from "./functions/report-location/index.ts";
import { handleHeartbeat } from "./functions/heartbeat/index.ts";
import { handleAutoJoin } from "./functions/auto-join/index.ts";
import { handleRedeemCode } from "./functions/redeem-code/index.ts";
import { handleLinkAppleId } from "./functions/link-apple-id/index.ts";
import { handleAdminMetrics } from "./functions/admin-metrics/index.ts";
import { handleAdminUsers } from "./functions/admin-users/index.ts";
import { handleAdminBlog } from "./functions/admin-blog/index.ts";
import { handleAdminBlogAi } from "./functions/admin-blog-ai/index.ts";
import { handleAdminSocial } from "./functions/admin-social/index.ts";
import { handleGenerateNextArticle } from "./functions/generate-next-article/index.ts";

type FunctionHandler = (req: Request, auth: AuthResult) => Promise<Response>;

// Routes that require service role (internal/pg_cron only)
const serviceRoleOnlyRoutes = new Set([
  "/send-checkin-notification",
  "/escalation-tick",
]);

// Routes authenticated by a shared webhook secret instead of a Supabase JWT.
// Map: route path -> env var name holding the secret. Bypasses verifyRequest;
// the secret is checked before rate limiting and routing.
const webhookSecretRoutes: Record<string, string> = {
  "/generate-next-article": "BLOG_GENERATION_WEBHOOK_SECRET",
};

// All routes
const routes: Record<string, FunctionHandler> = {
  "/send-checkin-notification": handleSendCheckinNotification,
  "/process-checkin-response": handleProcessCheckinResponse,
  "/escalation-tick": handleEscalationTick,
  "/on-demand-checkin": handleOnDemandCheckin,
  "/subscription-webhook": handleSubscriptionWebhook,
  "/invite-receiver": handleInviteReceiver,
  "/subscription-cancellation": handleSubscriptionCancellation,
  "/confirm-delivery": handleConfirmDelivery,
  "/report-location": handleReportLocation,
  "/heartbeat": handleHeartbeat,
  "/auto-join": handleAutoJoin,
  "/redeem-code": handleRedeemCode,
  "/link-apple-id": handleLinkAppleId,
  "/admin-metrics": handleAdminMetrics,
  "/admin-users": handleAdminUsers,
  "/admin-blog": handleAdminBlog,
  "/admin-blog-ai": handleAdminBlogAi,
  "/admin-social": handleAdminSocial,
  "/generate-next-article": handleGenerateNextArticle,
};

const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "https://dailyok.net";

function corsHeaders(req?: Request): Record<string, string> {
  const origin = req?.headers.get("Origin") || "";
  // Allow requests with no Origin header (iOS app, server-to-server, pg_cron)
  // Only set CORS headers when the request origin matches the allowed origin
  if (!origin || origin === ALLOWED_ORIGIN) {
    return {
      "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
    };
  }
  // Disallowed origin — return empty CORS headers (browser will block the response)
  return {};
}

const MAX_BODY_SIZE = 102400; // 100 KB

/**
 * JSON response with CORS headers applied. Use this for every non-OPTIONS
 * response so browsers can always read the body (including error responses).
 */
function jsonWithCors(body: unknown, status: number, req: Request, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders(req),
      ...extraHeaders,
    },
  });
}

/** Re-wrap a handler response so CORS is guaranteed on the outbound response. */
function withCors(response: Response, req: Request): Response {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(corsHeaders(req))) {
    headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    headers,
  });
}

async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;

  // Health check (no auth required)
  if (path === "/health") {
    return jsonWithCors({ status: "ok", service: "dailyok-edge-functions" }, 200, req);
  }

  // Enforce request body size limit for POST requests
  if (req.method === "POST") {
    const contentLength = req.headers.get("Content-Length");
    if (contentLength && parseInt(contentLength, 10) > MAX_BODY_SIZE) {
      return jsonWithCors({ error: "Request body too large" }, 413, req);
    }
  }

  // CORS preflight
  if (req.method === "OPTIONS") {
    const origin = req.headers.get("Origin") || "";
    if (origin && origin !== ALLOWED_ORIGIN) {
      return jsonWithCors({ error: "Forbidden: origin not allowed" }, 403, req);
    }
    return new Response(null, { headers: corsHeaders(req) });
  }

  // Webhook-secret routes: bypass JWT verification and authenticate via
  // X-Webhook-Secret header. Used by Make.com scenarios that don't hold a
  // Supabase JWT. Each route declares which env var holds its expected secret.
  let auth: AuthResult;
  const secretEnvVar = webhookSecretRoutes[path];
  if (secretEnvVar) {
    const expected = Deno.env.get(secretEnvVar);
    if (!expected || expected.trim() === "") {
      logError(`${path} misconfigured: ${secretEnvVar} not set`, new Error("missing secret env"), { path });
      return jsonWithCors({ error: "Service misconfigured" }, 500, req);
    }
    const provided = req.headers.get("X-Webhook-Secret") || "";
    if (provided !== expected) {
      return jsonWithCors({ error: "Unauthorized" }, 401, req);
    }
    auth = { authenticated: true, isServiceRole: true };
  } else {
    // Verify authentication (JWT or service role key)
    auth = await verifyRequest(req);
    if (!auth.authenticated) {
      return jsonWithCors({ error: "Unauthorized" }, 401, req);
    }
  }

  // Rate limiting
  if (auth.isServiceRole) {
    const rateLimitResult = checkServiceRoleRateLimit(path);
    if (!rateLimitResult.allowed) {
      return jsonWithCors({ error: "Too many requests" }, 429, req, {
        "Retry-After": String(rateLimitResult.retryAfterSeconds),
      });
    }
  } else if (auth.userId) {
    const rateLimitResult = checkRateLimit(auth.userId, path);
    if (!rateLimitResult.allowed) {
      return jsonWithCors({ error: "Too many requests" }, 429, req, {
        "Retry-After": String(rateLimitResult.retryAfterSeconds),
      });
    }
  }

  // Service-role-only routes (internal calls from pg_cron)
  if (serviceRoleOnlyRoutes.has(path) && !auth.isServiceRole) {
    return jsonWithCors({ error: "Forbidden: service role required" }, 403, req);
  }

  // Route to function handler
  const functionHandler = routes[path];
  if (functionHandler) {
    return withRequestLogging(path, auth.userId, async () => {
      try {
        const response = await functionHandler(req, auth);
        return withCors(response, req);
      } catch (error) {
        logError(`Unhandled error in ${path}`, error, { path, userId: auth.userId });
        const message = error instanceof Error ? error.message : String(error);
        return jsonWithCors({ error: "Internal server error", details: message }, 500, req);
      }
    });
  }

  return jsonWithCors({ error: "Not found" }, 404, req);
}

console.log(`Daily OK Edge Functions server running on port ${PORT}`);
Deno.serve({ port: PORT }, handler);
