import type { AuthResult } from "../../shared/auth.ts";
import { logInfo, logWarn } from "../../shared/logger.ts";
import { supabaseAdmin } from "../../shared/supabase.ts";
import {
  type AppStoreNotification,
  type AppStoreTransaction,
  verifyAppStoreJWS,
} from "../../shared/app-store-jws.ts";
import { APPLE_BUNDLE_ID } from "../../shared/app-store-server-api.ts";
import { notificationAction, tierForProduct, UUID_REGEX } from "../../shared/subscription-policy.ts";
import {
  applyEntitlement,
  type BillingFamily,
  bindReceipt,
  findBillingFamily,
  findFamilyByOriginalTransaction,
  receiptOwner,
  startGracePeriod,
} from "../../shared/subscription-billing.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/**
 * App Store Server Notifications v2 (US-EDGE005 follow-through).
 *
 * Until now the backend heard about renewals only when the owner opened the
 * app (Transaction.updates / launch reconcile). An owner who didn't open Daily
 * OK for about a week after a renewal had their family marked expired and
 * their parent's check-ins switched off while Apple kept charging them.
 * Refunds were never seen at all.
 *
 * Set the Production and Sandbox Server Notification URL in App Store Connect
 * to https://functions.dailyok.net/app-store-notifications (Version 2).
 *
 * Apple can't send a bearer token, so this route is unauthenticated at the
 * router and trusts nothing but the signature: the body must be a JWS that
 * chains to Apple Root CA - G3 (shared/app-store-jws.ts), for our bundle id.
 *
 * Responses: 200 once handled or deliberately ignored (Apple stops retrying);
 * 400 for anything that fails verification; 500 on a database error so Apple
 * retries later.
 */
export async function handleAppStoreNotification(req: Request, _auth: AuthResult): Promise<Response> {
  let body: { signedPayload?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body" }, 400);
  }
  if (typeof body.signedPayload !== "string") return json({ error: "signedPayload required" }, 400);

  let notification: AppStoreNotification;
  let tx: AppStoreTransaction | null = null;
  try {
    notification = await verifyAppStoreJWS<AppStoreNotification>(body.signedPayload);
    if (notification.data?.bundleId && notification.data.bundleId !== APPLE_BUNDLE_ID) {
      return json({ error: "bundle mismatch" }, 400);
    }
    if (notification.data?.signedTransactionInfo) {
      tx = await verifyAppStoreJWS<AppStoreTransaction>(notification.data.signedTransactionInfo);
      if (tx.bundleId !== APPLE_BUNDLE_ID) return json({ error: "bundle mismatch" }, 400);
    }
  } catch (err) {
    logWarn("Rejected App Store notification", {
      path: "/app-store-notifications",
      error: err instanceof Error ? err.message : "verify_error",
    });
    return json({ error: "verification_failed" }, 400);
  }

  const action = notificationAction(notification.notificationType, notification.subtype);
  logInfo("App Store notification", {
    path: "/app-store-notifications",
    type: notification.notificationType,
    subtype: notification.subtype,
    action,
    environment: notification.data?.environment,
  });

  if (action === "ignore" || !tx?.originalTransactionId) return json({ ok: true, handled: false });

  try {
    // Who is this subscription for, and which family does it pay for?
    let payer: string | null = await receiptOwner(tx.originalTransactionId);
    const token = tx.appAccountToken?.toLowerCase();
    if (!payer && token && UUID_REGEX.test(token)) {
      // Only a live account: a deleted one would fail the billing_user_id FK
      // and make Apple retry this notification for days.
      const { data } = await supabaseAdmin.from("users").select("id").eq("id", token).limit(1);
      if ((data?.length ?? 0) > 0) payer = token;
    }

    let family: BillingFamily | null = await findFamilyByOriginalTransaction(tx.originalTransactionId, payer);
    if (!family && payer) family = await findBillingFamily(payer);
    if (!family) return json({ ok: true, handled: false, reason: "no_family" });

    // Only the subscription the family is billed to may lapse or revoke it.
    // A second, older subscription running out must not end a plan someone
    // else is paying for.
    const billedToThis = family.billing_original_transaction_id
      ? family.billing_original_transaction_id === tx.originalTransactionId
      : true;

    switch (action) {
      case "apply": {
        const tierInfo = tierForProduct(tx.productId);
        if (!tierInfo) return json({ ok: true, handled: false, reason: "unknown_product" });
        if (tx.revocationDate) return json({ ok: true, handled: false, reason: "revoked" });
        const payerId = payer ?? family.billing_user_id ?? family.owner_id;
        const bound = await bindReceipt({ tx, userId: payerId, familyId: family.id });
        if (bound === "bound_to_other_user") return json({ ok: true, handled: false, reason: "bound_to_other_user" });
        const result = await applyEntitlement({
          family,
          tierInfo,
          expiresAt: tx.expiresDate ? new Date(tx.expiresDate) : null,
          originalTransactionId: tx.originalTransactionId,
          payerUserId: payerId,
          platform: "ios",
          verified: true,
        });
        return json({ ok: true, handled: result.applied });
      }
      case "payment_issue": {
        if (!billedToThis || family.subscription_status !== "active") return json({ ok: true, handled: false });
        // Apple is retrying the card. Check-ins keep running in grace_period;
        // the app shows "Payment issue". A later DID_RENEW restores 'active'.
        const { error } = await supabaseAdmin
          .from("families")
          .update({ subscription_status: "grace_period" })
          .eq("id", family.id);
        if (error) throw error;
        return json({ ok: true, handled: true });
      }
      case "lapse": {
        if (!billedToThis) return json({ ok: true, handled: false });
        await startGracePeriod(family, tx.expiresDate ? new Date(tx.expiresDate) : new Date());
        return json({ ok: true, handled: true });
      }
      case "revoke": {
        if (!billedToThis) return json({ ok: true, handled: false });
        await startGracePeriod(family, tx.revocationDate ? new Date(tx.revocationDate) : new Date());
        return json({ ok: true, handled: true });
      }
    }
  } catch (err) {
    logWarn("App Store notification not processed", {
      path: "/app-store-notifications",
      error: err instanceof Error ? err.message : String(err),
    });
    return json({ error: "processing_failed" }, 500);
  }
  return json({ ok: true, handled: false });
}
