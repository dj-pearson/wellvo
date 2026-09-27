/**
 * Google Play Developer API: what an Android subscription purchase really is
 * (androidpublisher v3 purchases.subscriptionsv2.get).
 *
 * Until now /subscription-webhook took an Android purchase at its word:
 * product_id from the request body, no expiry at all (shipped Android builds
 * send none), so an Android plan never lapsed and anyone could post any
 * product id with a made-up purchase_token. With a service account configured,
 * the webhook asks Google instead and stores Google's expiry.
 *
 * Configuration:
 *   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON — the service account key file's JSON
 *       (raw, or base64 of it). The account needs "View financial data" /
 *       subscription read access for the app in Play Console.
 *   GOOGLE_PLAY_PACKAGE_NAME — defaults to net.dailyok.android.
 * Without the key, lookups report "not_configured" and the webhook behaves as
 * before (log mode), whatever SUBSCRIPTION_VERIFY_MODE says.
 *
 * Pure parts (parsing, JWT claims, response interpretation, RTDN decoding)
 * are exported for tests; network parts are thin wrappers around them.
 */

export const GOOGLE_PLAY_PACKAGE = (typeof Deno !== "undefined" ? Deno.env.get("GOOGLE_PLAY_PACKAGE_NAME")?.trim() : undefined) ||
  "net.dailyok.android";

const TOKEN_URI = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const API_HOST = "https://androidpublisher.googleapis.com";

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri: string;
}

/** The service account from env text: raw JSON or base64 of it. Null when unusable. */
export function parseServiceAccount(raw: string | null | undefined): ServiceAccount | null {
  if (!raw || !raw.trim()) return null;
  let text = raw.trim();
  if (!text.startsWith("{")) {
    try {
      text = atob(text);
    } catch {
      return null;
    }
  }
  try {
    const parsed = JSON.parse(text) as Record<string, unknown>;
    const email = typeof parsed.client_email === "string" ? parsed.client_email : "";
    const key = typeof parsed.private_key === "string" ? parsed.private_key.replace(/\\n/g, "\n") : "";
    if (!email || !key.includes("PRIVATE KEY")) return null;
    const tokenUri = typeof parsed.token_uri === "string" && parsed.token_uri.startsWith("https://")
      ? parsed.token_uri
      : TOKEN_URI;
    return { client_email: email, private_key: key, token_uri: tokenUri };
  } catch {
    return null;
  }
}

function serviceAccount(): ServiceAccount | null {
  if (typeof Deno === "undefined") return null;
  return parseServiceAccount(Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"));
}

export function googlePlayConfigured(): boolean {
  return serviceAccount() !== null;
}

/** OAuth 2.0 JWT-bearer claims for the service account (RFC 7523). */
export function jwtClaims(sa: ServiceAccount, nowSec: number): Record<string, unknown> {
  return {
    iss: sa.client_email,
    scope: SCOPE,
    aud: sa.token_uri,
    iat: nowSec,
    exp: nowSec + 3600,
  };
}

export function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(b64);
  const der = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) der[i] = bin.charCodeAt(i);
  return der.buffer as ArrayBuffer;
}

let cachedKey: { pem: string; key: CryptoKey } | null = null;

async function signingKey(pem: string): Promise<CryptoKey> {
  if (cachedKey?.pem === pem) return cachedKey.key;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(pem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  cachedKey = { pem, key };
  return key;
}

/** A signed RS256 assertion for the token exchange. */
export async function signedAssertion(sa: ServiceAccount, nowSec: number): Promise<string> {
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = b64url(JSON.stringify(jwtClaims(sa, nowSec)));
  const input = new TextEncoder().encode(`${header}.${payload}`);
  const sig = new Uint8Array(
    await crypto.subtle.sign({ name: "RSASSA-PKCS1-v1_5" }, await signingKey(sa.private_key), input.buffer as ArrayBuffer),
  );
  return `${header}.${payload}.${b64url(sig)}`;
}

let cachedToken: { email: string; token: string; expiresAt: number } | null = null;

async function withTimeout(url: string, init: RequestInit, ms = 8000): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedToken.email === sa.client_email && cachedToken.expiresAt - 60_000 > now) {
    return cachedToken.token;
  }
  const assertion = await signedAssertion(sa, Math.floor(now / 1000));
  const res = await withTimeout(sa.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }).toString(),
  });
  if (!res.ok) {
    await res.body?.cancel();
    throw new Error(`token_http_${res.status}`);
  }
  const body = await res.json() as { access_token?: string; expires_in?: number };
  if (!body.access_token) throw new Error("token_empty");
  cachedToken = {
    email: sa.client_email,
    token: body.access_token,
    expiresAt: now + (body.expires_in ?? 3600) * 1000,
  };
  return body.access_token;
}

/** The parts of a SubscriptionPurchaseV2 the backend uses. */
export interface SubscriptionPurchaseV2 {
  subscriptionState?: string;
  latestOrderId?: string;
  linkedPurchaseToken?: string;
  testPurchase?: Record<string, unknown>;
  externalAccountIdentifiers?: { obfuscatedExternalAccountId?: string };
  lineItems?: { productId?: string; expiryTime?: string }[];
}

export type PlayLookup =
  | { status: "ok"; purchase: SubscriptionPurchaseV2 }
  | { status: "not_found" }
  | { status: "unavailable"; reason: string };

/** Ask Google about one subscription purchase token. */
export async function lookUpSubscription(purchaseToken: string): Promise<PlayLookup> {
  const sa = serviceAccount();
  if (!sa) return { status: "unavailable", reason: "not_configured" };
  if (!isPlausibleToken(purchaseToken)) return { status: "not_found" };
  try {
    const token = await accessToken(sa);
    const url = `${API_HOST}/androidpublisher/v3/applications/${encodeURIComponent(GOOGLE_PLAY_PACKAGE)}` +
      `/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
    const res = await withTimeout(url, { headers: { Authorization: `Bearer ${token}` } });
    // 404 / 410: no such purchase for this app. 400: malformed token.
    if (res.status === 404 || res.status === 410 || res.status === 400) {
      await res.body?.cancel();
      return { status: "not_found" };
    }
    if (!res.ok) {
      await res.body?.cancel();
      if (res.status === 401) cachedToken = null;
      return { status: "unavailable", reason: `http_${res.status}` };
    }
    return { status: "ok", purchase: await res.json() as SubscriptionPurchaseV2 };
  } catch (err) {
    return { status: "unavailable", reason: err instanceof Error ? err.message.slice(0, 40) : "error" };
  }
}

/** Purchase tokens are long opaque strings of URL-safe characters. */
export function isPlausibleToken(token: string | null | undefined): token is string {
  return typeof token === "string" && token.length >= 10 && token.length <= 4096 && /^[A-Za-z0-9._\-:]+$/.test(token);
}

/** Google says the subscriber is covered right now (auto-renewing, cancelled-but-paid, or in grace). */
const ENTITLED_STATES = new Set([
  "SUBSCRIPTION_STATE_ACTIVE",
  "SUBSCRIPTION_STATE_CANCELED",
  "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
]);

export interface PlayVerdict {
  productId: string | null;
  expiresAt: Date | null;
  state: string;
  entitled: boolean;
  orderId: string | null;
  linkedPurchaseToken: string | null;
  accountId: string | null;
  isTest: boolean;
}

/**
 * What a SubscriptionPurchaseV2 means. The line item for [claimedProductId]
 * wins when present (a purchase can carry several); otherwise the one that
 * runs longest. Entitled only in a covered state AND with an expiry still
 * in the future.
 */
export function interpretSubscription(
  purchase: SubscriptionPurchaseV2,
  now: Date,
  claimedProductId?: string | null,
): PlayVerdict {
  const items = (purchase.lineItems ?? []).filter((i) => typeof i.productId === "string" && i.productId);
  const expiry = (i: { expiryTime?: string }) => {
    const t = i.expiryTime ? Date.parse(i.expiryTime) : NaN;
    return Number.isNaN(t) ? -Infinity : t;
  };
  const chosen = items.find((i) => i.productId === claimedProductId) ??
    [...items].sort((a, b) => expiry(b) - expiry(a))[0];
  const expiresMs = chosen ? expiry(chosen) : -Infinity;
  const expiresAt = Number.isFinite(expiresMs) ? new Date(expiresMs) : null;
  const state = purchase.subscriptionState ?? "SUBSCRIPTION_STATE_UNSPECIFIED";
  return {
    productId: chosen?.productId ?? null,
    expiresAt,
    state,
    entitled: ENTITLED_STATES.has(state) && !!expiresAt && expiresAt.getTime() > now.getTime(),
    orderId: purchase.latestOrderId ?? null,
    linkedPurchaseToken: purchase.linkedPurchaseToken ?? null,
    accountId: purchase.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
    isTest: purchase.testPurchase !== undefined,
  };
}

/**
 * The id a Play subscription is stored under (families.billing_original_
 * transaction_id, subscription_receipts.original_transaction_id): a hash of
 * the purchase token, never the token itself — every family member can read
 * the families row, and a token is a credential for the purchase.
 */
export async function playSubscriptionKey(purchaseToken: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(purchaseToken)));
  return "gplay:" + Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

export type GoogleClaim =
  | { kind: "verified"; verdict: PlayVerdict; key: string; linkedKey: string | null }
  | { kind: "invalid"; reason: string }
  | { kind: "unavailable"; reason: string }
  | { kind: "not_configured" }
  | { kind: "unsigned" };

/** Establish what Google actually sold for the request's purchase_token. */
export async function verifyGoogleClaim(
  body: { purchase_token?: string; product_id?: string },
  now = new Date(),
): Promise<GoogleClaim> {
  if (!googlePlayConfigured()) return { kind: "not_configured" };
  if (typeof body.purchase_token !== "string" || body.purchase_token.length === 0) return { kind: "unsigned" };
  const lookup = await lookUpSubscription(body.purchase_token);
  if (lookup.status === "not_found") return { kind: "invalid", reason: "purchase_not_found" };
  if (lookup.status === "unavailable") return { kind: "unavailable", reason: lookup.reason };
  const verdict = interpretSubscription(lookup.purchase, now, body.product_id);
  if (!verdict.productId) return { kind: "invalid", reason: "no_line_items" };
  return {
    kind: "verified",
    verdict,
    key: await playSubscriptionKey(body.purchase_token),
    linkedKey: verdict.linkedPurchaseToken ? await playSubscriptionKey(verdict.linkedPurchaseToken) : null,
  };
}

// --- Real-time developer notifications (Pub/Sub push) ----------------------

export interface PlayNotification {
  packageName: string | null;
  purchaseToken: string | null;
  /** subscriptionNotification.notificationType, or -1 for a voided purchase. */
  notificationType: number | null;
  voided: boolean;
  test: boolean;
}

/** Decode a Pub/Sub push body ({ message: { data: base64(json) } }). Null when it isn't one. */
export function decodePubSubPush(body: unknown): PlayNotification | null {
  const data = (body as { message?: { data?: unknown } } | null)?.message?.data;
  if (typeof data !== "string") return null;
  let payload: Record<string, unknown>;
  try {
    const bin = atob(data.replace(/-/g, "+").replace(/_/g, "/"));
    const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
    payload = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
  const sub = payload.subscriptionNotification as { purchaseToken?: unknown; notificationType?: unknown } | undefined;
  const voided = payload.voidedPurchaseNotification as { purchaseToken?: unknown; productType?: unknown } | undefined;
  const packageName = typeof payload.packageName === "string" ? payload.packageName : null;
  if (sub && typeof sub.purchaseToken === "string") {
    return {
      packageName,
      purchaseToken: sub.purchaseToken,
      notificationType: typeof sub.notificationType === "number" ? sub.notificationType : null,
      voided: false,
      test: false,
    };
  }
  // productType 1 = subscription (2 = one-time product).
  if (voided && typeof voided.purchaseToken === "string" && voided.productType === 1) {
    return { packageName, purchaseToken: voided.purchaseToken, notificationType: -1, voided: true, test: false };
  }
  return { packageName, purchaseToken: null, notificationType: null, voided: false, test: payload.testNotification !== undefined };
}

export type PlayAction = "apply" | "payment_issue" | "lapse" | "revoke" | "ignore";

/**
 * What a notification means for the family, from Google's CURRENT state of
 * the purchase (fetched, never taken from the push) plus whether the push
 * reported a revocation. Nothing stops check-ins at once: lapse and revoke
 * start the same seven-day grace period a missed App Store renewal does.
 */
export function playAction(verdict: PlayVerdict | null, notificationType: number | null, voided: boolean): PlayAction {
  // SUBSCRIPTION_REVOKED (12) or a voided purchase: refunded / charged back.
  // The push body is not trusted: only act when Google itself no longer
  // reports the purchase as covered (gone, or not entitled). A refund that
  // Google did not revoke keeps access until it lapses, as Google intends.
  if (voided || notificationType === 12) return !verdict || !verdict.entitled ? "revoke" : "apply";
  if (!verdict) return "ignore";
  switch (verdict.state) {
    case "SUBSCRIPTION_STATE_ACTIVE":
    case "SUBSCRIPTION_STATE_CANCELED":
      return verdict.entitled ? "apply" : "lapse";
    case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
      return "payment_issue";
    case "SUBSCRIPTION_STATE_ON_HOLD":
    case "SUBSCRIPTION_STATE_PAUSED":
    case "SUBSCRIPTION_STATE_EXPIRED":
      return "lapse";
    default:
      // PENDING, PENDING_PURCHASE_CANCELED, UNSPECIFIED: nothing was paid.
      return "ignore";
  }
}
