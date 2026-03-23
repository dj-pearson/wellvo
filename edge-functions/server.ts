/**
 * Wellvo Edge Functions Server
 *
 * A lightweight HTTP server that routes requests to individual edge functions.
 * Runs as a Docker container alongside self-hosted Supabase on Coolify.
 */

const PORT = parseInt(Deno.env.get("PORT") || "9000");

// Import auth
import { verifyRequest, type AuthResult } from "./shared/auth.ts";
import { checkRateLimit } from "./shared/rate-limiter.ts";
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

type FunctionHandler = (req: Request, auth: AuthResult) => Promise<Response>;

// Routes that require service role (internal/pg_cron only)
const serviceRoleOnlyRoutes = new Set([
  "/send-checkin-notification",
  "/escalation-tick",
]);

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
};

const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "https://wellvo.net";

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

async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;

  // Health check (no auth required)
  if (path === "/health") {
    return new Response(JSON.stringify({ status: "ok", service: "wellvo-edge-functions" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  // CORS preflight
  if (req.method === "OPTIONS") {
    const origin = req.headers.get("Origin") || "";
    if (origin && origin !== ALLOWED_ORIGIN) {
      return new Response(JSON.stringify({ error: "Forbidden: origin not allowed" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }
    return new Response(null, { headers: corsHeaders(req) });
  }

  // Verify authentication (JWT or service role key)
  const auth = await verifyRequest(req);
  if (!auth.authenticated) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Rate limiting (service-role requests from pg_cron bypass rate limits)
  if (!auth.isServiceRole && auth.userId) {
    const rateLimitResult = checkRateLimit(auth.userId, path);
    if (!rateLimitResult.allowed) {
      return new Response(JSON.stringify({ error: "Too many requests" }), {
        status: 429,
        headers: {
          "Content-Type": "application/json",
          "Retry-After": String(rateLimitResult.retryAfterSeconds),
        },
      });
    }
  }

  // Service-role-only routes (internal calls from pg_cron)
  if (serviceRoleOnlyRoutes.has(path) && !auth.isServiceRole) {
    return new Response(JSON.stringify({ error: "Forbidden: service role required" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Route to function handler
  const functionHandler = routes[path];
  if (functionHandler) {
    return withRequestLogging(path, auth.userId, async () => {
      try {
        const response = await functionHandler(req, auth);
        // Add CORS headers to response
        const headers = new Headers(response.headers);
        for (const [key, value] of Object.entries(corsHeaders(req))) {
          headers.set(key, value);
        }
        return new Response(response.body, {
          status: response.status,
          headers,
        });
      } catch (error) {
        logError(`Unhandled error in ${path}`, error, { path, userId: auth.userId });
        return new Response(
          JSON.stringify({ error: "Internal server error" }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }
    });
  }

  return new Response(JSON.stringify({ error: "Not found" }), {
    status: 404,
    headers: { "Content-Type": "application/json" },
  });
}

console.log(`Wellvo Edge Functions server running on port ${PORT}`);
Deno.serve({ port: PORT }, handler);
