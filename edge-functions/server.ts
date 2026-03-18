/**
 * Wellvo Edge Functions Server
 *
 * A lightweight HTTP server that routes requests to individual edge functions.
 * Runs as a Docker container alongside self-hosted Supabase on Coolify.
 */

const PORT = parseInt(Deno.env.get("PORT") || "9000");

// Import auth
import { verifyRequest, type AuthResult } from "./shared/auth.ts";

// Import function handlers
import { handleSendCheckinNotification } from "./functions/send-checkin-notification/index.ts";
import { handleProcessCheckinResponse } from "./functions/process-checkin-response/index.ts";
import { handleEscalationTick } from "./functions/escalation-tick/index.ts";
import { handleOnDemandCheckin } from "./functions/on-demand-checkin/index.ts";
import { handleSubscriptionWebhook } from "./functions/subscription-webhook/index.ts";
import { handleInviteReceiver } from "./functions/invite-receiver/index.ts";

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
};

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
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
    return new Response(null, { headers: corsHeaders() });
  }

  // Verify authentication (JWT or service role key)
  const auth = await verifyRequest(req);
  if (!auth.authenticated) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
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
    try {
      const response = await functionHandler(req, auth);
      // Add CORS headers to response
      const headers = new Headers(response.headers);
      for (const [key, value] of Object.entries(corsHeaders())) {
        headers.set(key, value);
      }
      return new Response(response.body, {
        status: response.status,
        headers,
      });
    } catch (error) {
      console.error(`Error in ${path}:`, error);
      return new Response(
        JSON.stringify({ error: "Internal server error" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  return new Response(JSON.stringify({ error: "Not found" }), {
    status: 404,
    headers: { "Content-Type": "application/json" },
  });
}

console.log(`Wellvo Edge Functions server running on port ${PORT}`);
Deno.serve({ port: PORT }, handler);
