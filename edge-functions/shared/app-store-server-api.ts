/**
 * App Store Server API: look up a transaction by id (US-EDGE005).
 *
 * Shipped iOS builds send `transaction_id` but no signed transaction. When the
 * App Store Connect API key is configured, the webhook asks Apple for that
 * transaction and verifies Apple's signed answer, so those builds are checked
 * too without an app update.
 *
 * Configuration (all three required, otherwise lookups report "unavailable"
 * and the webhook falls back to SUBSCRIPTION_VERIFY_MODE):
 *   APPSTORE_ISSUER_ID    — App Store Connect → Users and Access → Integrations
 *   APPSTORE_KEY_ID       — the In-App Purchase key id
 *   APPSTORE_PRIVATE_KEY  — that key's .p8 contents (PKCS#8 PEM; "\n" escapes ok)
 *   APPLE_BUNDLE_ID       — defaults to com.wellvo.ios
 */

const PRODUCTION_HOST = "https://api.storekit.itunes.apple.com";
const SANDBOX_HOST = "https://api.storekit-sandbox.itunes.apple.com";

export const APPLE_BUNDLE_ID = Deno.env.get("APPLE_BUNDLE_ID")?.trim() || "com.wellvo.ios";

export type LookupResult =
  | { status: "ok"; signedTransactionInfo: string }
  | { status: "not_found" }
  | { status: "unavailable"; reason: string };

function config() {
  const issuer = Deno.env.get("APPSTORE_ISSUER_ID")?.trim();
  const keyId = Deno.env.get("APPSTORE_KEY_ID")?.trim();
  const pem = Deno.env.get("APPSTORE_PRIVATE_KEY")?.replace(/\\n/g, "\n").trim();
  if (!issuer || !keyId || !pem) return null;
  return { issuer, keyId, pem };
}

export function appStoreApiConfigured(): boolean {
  return config() !== null;
}

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let cachedKey: { pem: string; key: CryptoKey } | null = null;

async function signingKey(pem: string): Promise<CryptoKey> {
  if (cachedKey?.pem === pem) return cachedKey.key;
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(b64);
  const der = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) der[i] = bin.charCodeAt(i);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der.buffer as ArrayBuffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  cachedKey = { pem, key };
  return key;
}

async function bearerToken(cfg: { issuer: string; keyId: string; pem: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: cfg.keyId, typ: "JWT" }));
  const payload = b64url(JSON.stringify({
    iss: cfg.issuer,
    iat: now,
    exp: now + 300,
    aud: "appstoreconnect-v1",
    bid: APPLE_BUNDLE_ID,
  }));
  const input = new TextEncoder().encode(`${header}.${payload}`);
  // WebCrypto ECDSA signatures are already r||s (the JWS format).
  const sig = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    await signingKey(cfg.pem),
    input.buffer as ArrayBuffer,
  ));
  return `${header}.${payload}.${b64url(sig)}`;
}

async function getFrom(host: string, transactionId: string, token: string): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    return await fetch(`${host}/inApps/v1/transactions/${transactionId}`, {
      headers: { Authorization: `Bearer ${token}` },
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Ask Apple for one transaction. Production first, then sandbox (TestFlight
 * and Xcode purchases live there). The returned JWS is NOT yet verified —
 * pass it to verifyAppStoreJWS.
 */
export async function lookUpTransaction(transactionId: string): Promise<LookupResult> {
  const cfg = config();
  if (!cfg) return { status: "unavailable", reason: "not_configured" };
  if (!/^\d{1,20}$/.test(transactionId)) return { status: "not_found" };

  try {
    const token = await bearerToken(cfg);
    for (const host of [PRODUCTION_HOST, SANDBOX_HOST]) {
      const res = await getFrom(host, transactionId, token);
      if (res.status === 404) {
        await res.body?.cancel();
        continue;
      }
      if (!res.ok) {
        await res.body?.cancel();
        return { status: "unavailable", reason: `http_${res.status}` };
      }
      const json = await res.json() as { signedTransactionInfo?: string };
      if (!json.signedTransactionInfo) return { status: "unavailable", reason: "empty_response" };
      return { status: "ok", signedTransactionInfo: json.signedTransactionInfo };
    }
    return { status: "not_found" };
  } catch (err) {
    return { status: "unavailable", reason: err instanceof Error ? err.name : "error" };
  }
}
