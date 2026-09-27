import type { AuthResult } from "../../shared/auth.ts";
import { logInfo, logWarn } from "../../shared/logger.ts";
import { tierForProduct } from "../../shared/subscription-policy.ts";
import {
  applyEntitlement,
  type BillingFamily,
  bindPlayReceipt,
  findBillingFamily,
  findFamilyByOriginalTransaction,
  receiptOwner,
  startGracePeriod,
} from "../../shared/subscription-billing.ts";
import {
  decodePubSubPush,
  GOOGLE_PLAY_PACKAGE,
  googlePlayConfigured,
  interpretSubscription,
  lookUpSubscription,
  playAction,
  playSubscriptionKey,
  type PlayVerdict,
} from "../../shared/google-play.ts";
import { supabaseAdmin } from "../../shared/supabase.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/**
 * Google Play real-time developer notifications (Pub/Sub push), the Android
 * counterpart of /app-store-notifications: renewals, holds, expiries and
 * refunds reach the family without the owner opening the app, so an Android
 * plan can lapse and a renewed one doesn't.
 *
 * Setup: Play Console → Monetization setup → Real-time developer
 * notifications → a Pub/Sub topic with a push subscription to
 * https://functions.dailyok.net/google-play-notifications?token=<GOOGLE_PLAY_RTDN_TOKEN>
 * (the token is optional but recommended).
 *
 * Nothing in the push is trusted beyond the purchase token: the purchase's
 * state, product and expiry are re-read from the Play Developer API. A forged
 * push can at most make the server refresh a real purchase.
 *
 * Responses: 200 once handled or deliberately ignored (Pub/Sub stops
 * retrying); 503 when Google couldn't be asked; 500 on a database error.
 */
export async function handleGooglePlayNotification(req: Request, _auth: AuthResult): Promise<Response> {
  const expected = Deno.env.get("GOOGLE_PLAY_RTDN_TOKEN")?.trim();
  if (expected) {
    const given = new URL(req.url).searchParams.get("token") ?? "";
    if (!timingSafeEqual(given, expected)) return json({ error: "unauthorized" }, 401);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body" }, 400);
  }
  const note = decodePubSubPush(body);
  if (!note) return json({ error: "not a Pub/Sub push" }, 400);
  if (note.packageName && note.packageName !== GOOGLE_PLAY_PACKAGE) {
    return json({ ok: true, handled: false, reason: "other_package" });
  }
  if (!note.purchaseToken) return json({ ok: true, handled: false, reason: note.test ? "test" : "no_token" });
  if (!googlePlayConfigured()) {
    logWarn("Play notification received but no service account is configured", { path: "/google-play-notifications" });
    return json({ ok: true, handled: false, reason: "not_configured" });
  }

  let verdict: PlayVerdict | null = null;
  const lookup = await lookUpSubscription(note.purchaseToken);
  if (lookup.status === "ok") {
    verdict = interpretSubscription(lookup.purchase, new Date());
  } else if (lookup.status === "unavailable") {
    return json({ error: "verification_unavailable", reason: lookup.reason }, 503);
  }
  const action = playAction(verdict, note.notificationType, note.voided);
  logInfo("Play notification", {
    path: "/google-play-notifications",
    type: note.notificationType,
    state: verdict?.state,
    action,
  });
  if (action === "ignore") return json({ ok: true, handled: false });

  try {
    const key = await playSubscriptionKey(note.purchaseToken);
    const linkedKey = verdict?.linkedPurchaseToken ? await playSubscriptionKey(verdict.linkedPurchaseToken) : null;

    // Who is this subscription for, and which family does it pay for?
    const payer = await receiptOwner(key) ?? (linkedKey ? await receiptOwner(linkedKey) : null);
    let family: BillingFamily | null = await findFamilyByOriginalTransaction(key, payer);
    if (!family && linkedKey) family = await findFamilyByOriginalTransaction(linkedKey, payer);
    if (!family && payer) family = await findBillingFamily(payer);
    // Nobody has presented this purchase through the app yet: the app's own
    // webhook call binds it; nothing to do here.
    if (!family) return json({ ok: true, handled: false, reason: "no_family" });

    const billedToThis = family.billing_original_transaction_id
      ? family.billing_original_transaction_id === key || family.billing_original_transaction_id === linkedKey
      : true;

    switch (action) {
      case "apply": {
        if (!verdict?.productId) return json({ ok: true, handled: false, reason: "no_product" });
        const tierInfo = tierForProduct(verdict.productId);
        if (!tierInfo) return json({ ok: true, handled: false, reason: "unknown_product" });
        const payerId = payer ?? family.billing_user_id ?? family.owner_id;
        const bound = await bindPlayReceipt({ key, linkedKey, userId: payerId, familyId: family.id, verdict });
        if (bound === "bound_to_other_user") return json({ ok: true, handled: false, reason: "bound_to_other_user" });
        const result = await applyEntitlement({
          family,
          tierInfo,
          expiresAt: verdict.expiresAt,
          originalTransactionId: key,
          replacesTransactionId: linkedKey,
          payerUserId: payerId,
          platform: "android",
          verified: true,
        });
        return json({ ok: true, handled: result.applied });
      }
      case "payment_issue": {
        if (!billedToThis || family.subscription_status !== "active") return json({ ok: true, handled: false });
        // Google is retrying the payment (grace period). Check-ins keep
        // running; a later renewal restores 'active'.
        const { error } = await supabaseAdmin
          .from("families")
          .update({ subscription_status: "grace_period" })
          .eq("id", family.id);
        if (error) throw error;
        return json({ ok: true, handled: true });
      }
      case "lapse": {
        if (!billedToThis) return json({ ok: true, handled: false });
        await startGracePeriod(family, verdict?.expiresAt ?? new Date());
        return json({ ok: true, handled: true });
      }
      case "revoke": {
        if (!billedToThis) return json({ ok: true, handled: false });
        await startGracePeriod(family, new Date());
        return json({ ok: true, handled: true });
      }
    }
  } catch (err) {
    logWarn("Play notification not processed", {
      path: "/google-play-notifications",
      error: err instanceof Error ? err.message : String(err),
    });
    return json({ error: "processing_failed" }, 500);
  }
  return json({ ok: true, handled: false });
}

function timingSafeEqual(a: string, b: string): boolean {
  const ab = new TextEncoder().encode(a);
  const bb = new TextEncoder().encode(b);
  let diff = ab.length ^ bb.length;
  for (let i = 0; i < Math.max(ab.length, bb.length); i++) diff |= (ab[i] ?? 0) ^ (bb[i] ?? 0);
  return diff === 0;
}
