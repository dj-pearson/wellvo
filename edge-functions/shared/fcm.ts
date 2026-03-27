/**
 * FCM (Firebase Cloud Messaging) client using HTTP v1 API.
 * Uses service account credentials for OAuth2 authentication.
 */

const FIREBASE_SERVICE_ACCOUNT_JSON = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") || "";

interface ServiceAccountKey {
  project_id: string;
  private_key: string;
  client_email: string;
  token_uri: string;
}

interface FCMPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

let cachedAccessToken: string | null = null;
let tokenExpiry = 0;

function base64url(input: string): string {
  return btoa(input)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  if (cachedAccessToken && tokenExpiry > now + 60) {
    return cachedAccessToken;
  }

  if (!FIREBASE_SERVICE_ACCOUNT_JSON) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON environment variable not set");
  }

  const sa: ServiceAccountKey = JSON.parse(FIREBASE_SERVICE_ACCOUNT_JSON);

  // Create JWT for OAuth2
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: sa.token_uri || "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })
  );

  const signInput = `${header}.${claim}`;

  // Import the private key
  const pemKey = sa.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\n/g, "");

  const keyData = Uint8Array.from(atob(pemKey), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signatureData = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signInput)
  );

  const signature = base64url(
    String.fromCharCode(...new Uint8Array(signatureData))
  );

  const jwt = `${signInput}.${signature}`;

  // Exchange JWT for access token
  const tokenUrl = sa.token_uri || "https://oauth2.googleapis.com/token";
  const tokenResponse = await fetch(tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  if (!tokenResponse.ok) {
    const errBody = await tokenResponse.text();
    throw new Error(`Failed to get FCM access token: ${errBody}`);
  }

  const tokenData = await tokenResponse.json();
  cachedAccessToken = tokenData.access_token;
  tokenExpiry = now + (tokenData.expires_in || 3600);

  return cachedAccessToken!;
}

function getProjectId(): string {
  if (!FIREBASE_SERVICE_ACCOUNT_JSON) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON environment variable not set");
  }
  const sa: ServiceAccountKey = JSON.parse(FIREBASE_SERVICE_ACCOUNT_JSON);
  return sa.project_id;
}

export async function sendFCMNotification(
  token: string,
  payload: FCMPayload
): Promise<{ success: boolean; statusCode: number; reason?: string }> {
  try {
    const accessToken = await getAccessToken();
    const projectId = getProjectId();
    const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    const message: Record<string, unknown> = {
      message: {
        token,
        notification: {
          title: payload.title,
          body: payload.body,
        },
        android: {
          priority: "high",
          notification: {
            channel_id: "checkin_requests",
            sound: "default",
          },
        },
        data: payload.data || {},
      },
    };

    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(message),
    });

    if (response.ok) {
      console.log(`FCM send success: token=${token.slice(0, 8)}...`);
      return { success: true, statusCode: response.status };
    }

    const errorBody = await response.json().catch(() => ({}));
    const errorDetails = (errorBody as Record<string, unknown>).error as
      | Record<string, unknown>
      | undefined;
    const errorCode = errorDetails?.code as number | undefined;
    const errorMessage = errorDetails?.message as string | undefined;
    const reason = errorMessage || "Unknown FCM error";

    console.error(`FCM send failed: token=${token.slice(0, 8)}..., status=${errorCode || response.status}, reason=${reason}`);

    return {
      success: false,
      statusCode: errorCode || response.status,
      reason,
    };
  } catch (err) {
    const reason = (err as Error).message;
    console.error(`FCM send error: token=${token.slice(0, 8)}..., error=${reason}`);
    return {
      success: false,
      statusCode: 500,
      reason,
    };
  }
}

export function buildFCMAlertPayload(
  title: string,
  body: string,
  data: Record<string, string>
): FCMPayload {
  return { title, body, data };
}

export function buildFCMCheckinPayload(
  receiverName: string,
  requestId: string,
  receiverId: string,
  type: "scheduled" | "on_demand" | "escalation",
  escalationStep?: number,
  receiverMode?: string
): FCMPayload {
  let title: string;
  let body: string;

  if (receiverMode === "kid") {
    const titles: Record<string, string> = {
      scheduled: "Hey! 👋",
      on_demand: "Your parent wants to hear from you!",
      escalation: "Don't forget!",
    };
    const bodies: Record<string, string> = {
      scheduled: "Time to check in! Let your parents know how you're doing.",
      on_demand: "Tap to let them know you're OK!",
      escalation: "Your parents are waiting to hear from you.",
    };
    title = titles[type];
    body = bodies[type];
  } else {
    const titles: Record<string, string> = {
      scheduled: "Good morning!",
      on_demand: "Someone is checking on you",
      escalation: "Reminder: Check in",
    };
    const bodies: Record<string, string> = {
      scheduled: "Tap to let your family know you're OK.",
      on_demand: `${receiverName} is checking on you. Tap to let them know you're OK.`,
      escalation: `This is reminder #${escalationStep || 1}. Please tap to check in.`,
    };
    title = titles[type];
    body = bodies[type];
  }

  return {
    title,
    body,
    data: {
      type: "CHECKIN_REQUEST",
      request_id: requestId,
      receiver_id: receiverId,
      receiver_name: receiverName,
      notification_type: type,
      title,
      body,
    },
  };
}
