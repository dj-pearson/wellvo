import { assertEquals } from "std/assert/mod.ts";
import {
  b64url,
  decodePubSubPush,
  interpretSubscription,
  isPlausibleToken,
  jwtClaims,
  parseServiceAccount,
  playAction,
  playSubscriptionKey,
  signedAssertion,
} from "./google-play.ts";
import { decideApply } from "./subscription-policy.ts";

const now = new Date("2026-09-27T12:00:00Z");
const inDays = (d: number) => new Date(now.getTime() + d * 86_400_000).toISOString();

Deno.test("service account: raw or base64 JSON, escaped newlines, junk refused", () => {
  const raw = JSON.stringify({
    client_email: "play@x.iam.gserviceaccount.com",
    private_key: "-----BEGIN PRIVATE KEY-----\\nAAAA\\n-----END PRIVATE KEY-----\\n",
  });
  const sa = parseServiceAccount(raw);
  assertEquals(sa?.client_email, "play@x.iam.gserviceaccount.com");
  assertEquals(sa?.private_key.includes("\n"), true);
  assertEquals(sa?.token_uri, "https://oauth2.googleapis.com/token");
  assertEquals(parseServiceAccount(btoa(raw))?.client_email, "play@x.iam.gserviceaccount.com");
  assertEquals(parseServiceAccount(""), null);
  assertEquals(parseServiceAccount("{\"client_email\":\"a\"}"), null);
  assertEquals(parseServiceAccount("not json at all"), null);
});

Deno.test("JWT claims ask for the androidpublisher scope for an hour", () => {
  const claims = jwtClaims({ client_email: "e", private_key: "k", token_uri: "https://oauth2.googleapis.com/token" }, 1000);
  assertEquals(claims, {
    iss: "e",
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    iat: 1000,
    exp: 4600,
  });
});

Deno.test("the assertion is a valid RS256 JWT for the service account key", async () => {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  ) as CryptoKeyPair;
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer);
  let bin = "";
  for (const b of pkcs8) bin += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin).replace(/(.{64})/g, "$1\n")}\n-----END PRIVATE KEY-----\n`;
  const sa = { client_email: "svc@example.iam.gserviceaccount.com", private_key: pem, token_uri: "https://oauth2.googleapis.com/token" };

  const jwt = await signedAssertion(sa, 1_700_000_000);
  const [h, p, s] = jwt.split(".");
  const decode = (part: string) => JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/")));
  assertEquals(decode(h), { alg: "RS256", typ: "JWT" });
  assertEquals(decode(p).iss, "svc@example.iam.gserviceaccount.com");
  const sigBin = atob(s.replace(/-/g, "+").replace(/_/g, "/"));
  const sig = Uint8Array.from(sigBin, (c) => c.charCodeAt(0));
  const ok = await crypto.subtle.verify(
    { name: "RSASSA-PKCS1-v1_5" },
    pair.publicKey,
    sig,
    new TextEncoder().encode(`${h}.${p}`),
  );
  assertEquals(ok, true);
  assertEquals(b64url("??>"), "Pz8-");
});

Deno.test("an active subscription is entitled until Google's expiry", () => {
  const v = interpretSubscription({
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    latestOrderId: "GPA.1234-5678-9012-34567..3",
    lineItems: [{ productId: "net.dailyok.family.monthly", expiryTime: inDays(20) }],
  }, now, "net.dailyok.family.monthly");
  assertEquals(v.entitled, true);
  assertEquals(v.productId, "net.dailyok.family.monthly");
  assertEquals(v.expiresAt?.toISOString(), inDays(20));
  assertEquals(v.orderId, "GPA.1234-5678-9012-34567..3");
  assertEquals(v.isTest, false);
});

Deno.test("Google's product wins over the one the app claimed", () => {
  const v = interpretSubscription({
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    lineItems: [{ productId: "net.dailyok.caregiver.monthly", expiryTime: inDays(5) }],
    testPurchase: {},
  }, now, "net.dailyok.familyplus.yearly");
  assertEquals(v.productId, "net.dailyok.caregiver.monthly");
  assertEquals(v.isTest, true);
});

Deno.test("cancelled-but-paid and grace are covered; hold, expired and pending are not", () => {
  const covered = (state: string, expiry = inDays(3)) =>
    interpretSubscription({ subscriptionState: state, lineItems: [{ productId: "p", expiryTime: expiry }] }, now).entitled;
  assertEquals(covered("SUBSCRIPTION_STATE_CANCELED"), true);
  assertEquals(covered("SUBSCRIPTION_STATE_IN_GRACE_PERIOD"), true);
  assertEquals(covered("SUBSCRIPTION_STATE_CANCELED", inDays(-1)), false);
  assertEquals(covered("SUBSCRIPTION_STATE_ON_HOLD"), false);
  assertEquals(covered("SUBSCRIPTION_STATE_EXPIRED", inDays(-3)), false);
  assertEquals(covered("SUBSCRIPTION_STATE_PENDING"), false);
  assertEquals(interpretSubscription({ subscriptionState: "SUBSCRIPTION_STATE_ACTIVE" }, now).productId, null);
});

Deno.test("purchase tokens: plausible shapes only; stored as a hash, never the token", async () => {
  assertEquals(isPlausibleToken("abcdefghij.AO-J1Oz_x"), true);
  assertEquals(isPlausibleToken("short"), false);
  assertEquals(isPlausibleToken("has spaces in it here"), false);
  assertEquals(isPlausibleToken("../../etc/passwd/xx"), false);
  const key = await playSubscriptionKey("token-123456");
  assertEquals(key.startsWith("gplay:"), true);
  assertEquals(key.length, 6 + 64);
  assertEquals(key.includes("token-123456"), false);
  assertEquals(await playSubscriptionKey("token-123456"), key);
});

Deno.test("Pub/Sub push bodies decode to the purchase token", () => {
  const push = (payload: unknown) => ({ message: { data: btoa(JSON.stringify(payload)), messageId: "1" }, subscription: "s" });
  assertEquals(
    decodePubSubPush(push({
      version: "1.0",
      packageName: "net.dailyok.android",
      subscriptionNotification: { version: "1.0", notificationType: 2, purchaseToken: "tok-abcdefghij", subscriptionId: "x" },
    })),
    { packageName: "net.dailyok.android", purchaseToken: "tok-abcdefghij", notificationType: 2, voided: false, test: false },
  );
  assertEquals(
    decodePubSubPush(push({ packageName: "net.dailyok.android", voidedPurchaseNotification: { purchaseToken: "v-abcdefghij", productType: 1 } }))
      ?.voided,
    true,
  );
  assertEquals(decodePubSubPush(push({ packageName: "p", testNotification: { version: "1.0" } }))?.test, true);
  assertEquals(decodePubSubPush({ message: {} }), null);
  assertEquals(decodePubSubPush(null), null);
});

Deno.test("notification actions follow Google's current state", () => {
  const verdict = (state: string, entitled: boolean) => ({
    productId: "p", expiresAt: null, state, entitled, orderId: null, linkedPurchaseToken: null, accountId: null, isTest: false,
  });
  assertEquals(playAction(verdict("SUBSCRIPTION_STATE_ACTIVE", true), 2, false), "apply");
  assertEquals(playAction(verdict("SUBSCRIPTION_STATE_CANCELED", true), 3, false), "apply");
  assertEquals(playAction(verdict("SUBSCRIPTION_STATE_CANCELED", false), 13, false), "lapse");
  assertEquals(playAction(verdict("SUBSCRIPTION_STATE_IN_GRACE_PERIOD", true), 6, false), "payment_issue");
  assertEquals(playAction(verdict("SUBSCRIPTION_STATE_ON_HOLD", false), 5, false), "lapse");
  assertEquals(playAction(verdict("SUBSCRIPTION_STATE_PENDING", false), 4, false), "ignore");
  assertEquals(playAction(null, 12, false), "revoke");
  assertEquals(playAction(null, -1, true), "revoke");
  assertEquals(playAction(null, 2, false), "ignore");
});

Deno.test("a Play plan change (linked token) is the same subscription, not a lesser one", () => {
  const current = {
    subscription_tier: "family_plus",
    subscription_status: "active",
    subscription_expires_at: inDays(10),
    billing_original_transaction_id: "gplay:old",
  };
  // Downgrade to Family on a new token linked to the old one: applies.
  assertEquals(
    decideApply(current, { tier: "family", expiresAt: new Date(inDays(30)), originalTransactionId: "gplay:new", replacesTransactionId: "gplay:old" }, now),
    { apply: true },
  );
  // The same lower plan from an unrelated purchase does not replace it.
  assertEquals(
    decideApply(current, { tier: "family", expiresAt: new Date(inDays(30)), originalTransactionId: "gplay:other" }, now),
    { apply: false, reason: "higher_plan_active" },
  );
});
