/**
 * APNs (Apple Push Notification Service) client using HTTP/2.
 * Uses jose for JWT signing as required by APNs token-based auth.
 */

import { SignJWT, importPKCS8 } from "jose";

const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") || "";
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") || "";
const APNS_PRIVATE_KEY_BASE64 = Deno.env.get("APNS_PRIVATE_KEY") || "";
const APNS_ENVIRONMENT = Deno.env.get("APNS_ENVIRONMENT") || "development";

const APNS_HOST =
  APNS_ENVIRONMENT === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";

const BUNDLE_ID = "com.wellvo.ios";

interface APNsPayload {
  aps: {
    alert: {
      title: string;
      body: string;
    };
    sound?: string;
    badge?: number;
    category?: string;
    "thread-id"?: string;
    "interruption-level"?: "passive" | "active" | "time-sensitive" | "critical";
    "relevance-score"?: number;
  };
  // Custom data
  [key: string]: unknown;
}

let cachedToken: string | null = null;
let tokenExpiry = 0;

async function getAPNsToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  // Reuse token if still valid (tokens last 1 hour, refresh at 50 min)
  if (cachedToken && tokenExpiry > now + 600) {
    return cachedToken;
  }

  const privateKeyPem = atob(APNS_PRIVATE_KEY_BASE64);
  const privateKey = await importPKCS8(privateKeyPem, "ES256");

  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: APNS_KEY_ID })
    .setIssuer(APNS_TEAM_ID)
    .setIssuedAt(now)
    .sign(privateKey);

  cachedToken = token;
  tokenExpiry = now + 3600;

  return token;
}

export async function sendPushNotification(
  deviceToken: string,
  payload: APNsPayload,
  options?: { expiration?: number; priority?: number; collapseId?: string }
): Promise<{ success: boolean; statusCode: number; reason?: string }> {
  const token = await getAPNsToken();
  const url = `${APNS_HOST}/3/device/${deviceToken}`;

  const headers: Record<string, string> = {
    Authorization: `bearer ${token}`,
    "apns-topic": BUNDLE_ID,
    "apns-push-type": "alert",
    "apns-priority": String(options?.priority ?? 10),
    "Content-Type": "application/json",
  };

  if (options?.expiration) {
    headers["apns-expiration"] = String(options.expiration);
  }
  if (options?.collapseId) {
    headers["apns-collapse-id"] = options.collapseId;
  }

  const response = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });

  if (response.ok) {
    return { success: true, statusCode: response.status };
  }

  const errorBody = await response.json().catch(() => ({}));
  return {
    success: false,
    statusCode: response.status,
    reason: (errorBody as Record<string, string>).reason || "Unknown error",
  };
}

export function buildCheckinPayload(
  receiverName: string,
  requestId: string,
  type: "scheduled" | "on_demand" | "escalation",
  escalationStep?: number,
  receiverMode?: string
): APNsPayload {
  let titles: Record<string, string>;
  let bodies: Record<string, string>;

  if (receiverMode === "kid") {
    titles = {
      scheduled: "Hey! 👋",
      on_demand: "Your parent wants to hear from you!",
      escalation: "Don't forget!",
    };
    bodies = {
      scheduled: "Time to check in! Let your parents know how you're doing.",
      on_demand: "Tap to let them know you're OK!",
      escalation: "Your parents are waiting to hear from you.",
    };
  } else {
    titles = {
      scheduled: "Good morning!",
      on_demand: "Someone is checking on you",
      escalation: "Reminder: Check in",
    };
    bodies = {
      scheduled: "Tap to let your family know you're OK.",
      on_demand: `${receiverName} is checking on you. Tap to let them know you're OK.`,
      escalation: `This is reminder #${escalationStep || 1}. Please tap to check in.`,
    };
  }

  const interruptionLevel =
    type === "escalation" && (escalationStep || 0) >= 2
      ? "critical"
      : type === "escalation"
        ? "time-sensitive"
        : "active";

  return {
    aps: {
      alert: {
        title: titles[type],
        body: bodies[type],
      },
      sound: type === "escalation" ? "urgent.caf" : "default",
      category: "CHECKIN_REQUEST",
      "thread-id": `checkin-${requestId}`,
      "interruption-level": interruptionLevel as APNsPayload["aps"]["interruption-level"],
    },
    checkin_request_id: requestId,
    type,
  };
}
