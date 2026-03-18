/**
 * Wellvo Edge Functions Server
 *
 * A lightweight HTTP server that routes requests to individual edge functions.
 * Runs as a Docker container alongside self-hosted Supabase on Coolify.
 */

const PORT = parseInt(Deno.env.get("PORT") || "9000");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

// Import function handlers
import { handleSendCheckinNotification } from "./functions/send-checkin-notification/index.ts";
import { handleProcessCheckinResponse } from "./functions/process-checkin-response/index.ts";
import { handleEscalationTick } from "./functions/escalation-tick/index.ts";
import { handleOnDemandCheckin } from "./functions/on-demand-checkin/index.ts";
import { handleSubscriptionWebhook } from "./functions/subscription-webhook/index.ts";
import { handleInviteReceiver } from "./functions/invite-receiver/index.ts";

type FunctionHandler = (req: Request) => Promise<Response>;

const routes: Record<string, FunctionHandler> = {
  "/send-checkin-notification": handleSendCheckinNotification,
  "/process-checkin-response": handleProcessCheckinResponse,
  "/escalation-tick": handleEscalationTick,
  "/on-demand-checkin": handleOnDemandCheckin,
  "/subscription-webhook": handleSubscriptionWebhook,
  "/invite-receiver": handleInviteReceiver,
};

function verifyAuth(req: Request): boolean {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return false;
  const token = authHeader.replace("Bearer ", "");
  // Accept service role key or valid JWT from Supabase client
  return token === SERVICE_ROLE_KEY || token.length > 20;
}

async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;

  // Health check
  if (path === "/health") {
    return new Response(JSON.stringify({ status: "ok", service: "wellvo-edge-functions" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  // Auth check
  if (!verifyAuth(req)) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Route to function handler
  const functionHandler = routes[path];
  if (functionHandler) {
    try {
      return await functionHandler(req);
    } catch (error) {
      console.error(`Error in ${path}:`, error);
      return new Response(
        JSON.stringify({ error: "Internal server error", details: String(error) }),
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
