import { supabaseAdmin } from "../../shared/supabase.ts";
import { logInfo, logWarn } from "../../shared/logger.ts";
import type { AuthResult } from "../../shared/auth.ts";
import {
  ADDON_IDS,
  capUnverifiedExpiry,
  tierForProduct,
  UUID_REGEX,
} from "../../shared/subscription-policy.ts";
import type { AppStoreTransaction } from "../../shared/app-store-jws.ts";
import {
  applyEntitlement,
  bindReceipt,
  findBillingFamily,
  unverifiedOriginalIdIsSafe,
  verifyAppleClaim,
} from "../../shared/subscription-billing.ts";

interface SubscriptionUpdate {
  product_id: string;
  transaction_id: string;
  original_id: string;
  expiration_date?: string;
  app_account_token?: string; // UUID linking to Supabase user
  /**
   * Optional (US-EDGE005): StoreKit 2 `VerificationResult.jwsRepresentation`.
   * When present, everything about the purchase is taken from Apple's signed
   * payload and the plain fields above are ignored.
   */
  signed_transaction?: string;
  /** Android sends "android" plus purchase_token / order_id. */
  platform?: string;
  purchase_token?: string;
}

/**
 * How strictly unverifiable iOS purchases are treated (US-EDGE005):
 *   "log"     (default) — accept, cap the claimed expiry, record as unverified.
 *                         Needed while shipped builds that send no signature
 *                         are in use and the App Store Server API key is not
 *                         configured.
 *   "enforce"           — refuse (403 verification_required), or 503 when
 *                         Apple could not be reached so the app retries.
 * Switch to "enforce" once APPSTORE_* is configured, or once
 * MIN_SUPPORTED_IOS_APP_VERSION includes the build that sends
 * signed_transaction (CLAUDE.md §B).
 */
const VERIFY_MODE = (Deno.env.get("SUBSCRIPTION_VERIFY_MODE") ?? "log").trim().toLowerCase();

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/**
 * Who this request is allowed to provision for.
 *
 * Returns the user id, or a Response to send back instead. A caller may only
 * act on their OWN account: app_account_token arrives in the request body, and
 * this route is not service-role-only (the iOS app calls it directly after a
 * purchase), so without this check any authenticated user could name someone
 * else's UUID and rewrite that family's tier, status, expiry and seat limits —
 * or, pointed the other way, set a paying customer's expiry into the past
 * (US-EDGE004).
 *
 * Service role stays trusted: server-to-server calls legitimately act for
 * another user. Same shape as the authorization check in
 * process-checkin-response.
 */
export function resolveAuthorizedUserId(
  body: { app_account_token?: string },
  auth: AuthResult,
  path = "/subscription-webhook",
): { userId: string } | { response: Response } {
  const claimed = body.app_account_token;

  if (claimed && !UUID_REGEX.test(claimed)) {
    logWarn("Invalid app_account_token format", { path });
    return { response: json({ error: "Invalid app_account_token: must be a valid UUID" }, 400) };
  }

  if (!auth.isServiceRole && claimed && auth.userId && claimed.toLowerCase() !== auth.userId.toLowerCase()) {
    logWarn("Rejected cross-user subscription request", { path, userId: auth.userId });
    return { response: json({ error: "You can only update your own subscription" }, 403) };
  }

  const userId = claimed || auth.userId;
  if (!userId) {
    return { response: json({ error: "Could not identify user. Ensure app_account_token is set." }, 400) };
  }

  return { userId: userId.toLowerCase() };
}

async function userExists(id: string): Promise<boolean> {
  const { data } = await supabaseAdmin.from("users").select("id").eq("id", id).limit(1);
  return (data?.length ?? 0) > 0;
}

export async function handleSubscriptionWebhook(req: Request, auth: AuthResult): Promise<Response> {
  let body: SubscriptionUpdate;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body" }, 400);
  }

  // Add-on seats: the increment RPCs can't run under the service role
  // (00018/00051: they require auth.uid() = owner), so this used to answer 500.
  // The app treats 5xx as transient, never finished the transaction, and
  // re-posted it on every launch and reconnect. Nothing is granted either way
  // until add-ons go through the verified, idempotent receipts table; a 409
  // lets the app finish the transaction instead of looping.
  if (ADDON_IDS.has(body.product_id)) {
    return json({ error: "addon_unavailable", message: "Extra places can't be added this way yet. Please contact support." }, 409);
  }

  // Identify the user — prefer appAccountToken (linked at purchase time),
  // fall back to the authenticated user ID from the JWT.
  const resolved = resolveAuthorizedUserId(body, auth);
  if ("response" in resolved) return resolved.response;
  let userId = resolved.userId;

  const platform: "ios" | "android" = body.platform === "android" ? "android" : "ios";
  const now = new Date();

  // --- What was actually bought (US-EDGE005) -------------------------------
  let productId = body.product_id;
  let expiresAt: Date | null;
  let originalTransactionId: string | null = null;
  let verifiedTx: AppStoreTransaction | null = null;

  if (platform === "ios") {
    const claim = await verifyAppleClaim(body);
    if (claim.kind === "invalid") {
      logWarn("Subscription verification failed", { path: "/subscription-webhook", userId, reason: claim.reason });
      // Only refuse in enforce mode. In log mode an unsigned request is
      // accepted anyway, so refusing a bad signature adds no protection (a
      // forger just leaves the signature out) — while a verifier problem, or
      // an Xcode StoreKit-configuration purchase signed by a local cert, would
      // make every purchase from new builds a permanent 400: the app finishes
      // the transaction and the family is never upgraded. Fall through to the
      // capped, unverified path below instead.
      if (VERIFY_MODE === "enforce") {
        return json({ error: "verification_failed", reason: claim.reason }, 400);
      }
    }
    if (claim.kind === "verified") {
      const tx = claim.tx;
      verifiedTx = tx;
      productId = tx.productId;
      originalTransactionId = tx.originalTransactionId;
      expiresAt = tx.expiresDate ? new Date(tx.expiresDate) : null;

      // The account the purchase was made for. Another live account's
      // purchase is refused; a purchase whose account was deleted may be
      // claimed by the account presenting it (re-registration).
      const token = tx.appAccountToken?.toLowerCase();
      if (token && token !== userId && !auth.isServiceRole) {
        if (await userExists(token)) {
          logWarn("Refused a purchase made for another account", { path: "/subscription-webhook", userId });
          return json({ error: "This purchase belongs to another Daily OK account" }, 403);
        }
      } else if (token && auth.isServiceRole) {
        userId = token;
      }

      if (tx.revocationDate) {
        return json({ success: true, applied: false, reason: "revoked", verified: true });
      }
      if (tx.isUpgraded) {
        return json({ success: true, applied: false, reason: "upgraded", verified: true });
      }
    } else {
      // Unsigned (shipped build, no API key) or Apple unreachable.
      if (VERIFY_MODE === "enforce") {
        return claim.kind === "unavailable"
          ? json({ error: "verification_unavailable" }, 503)
          : json({ error: "verification_required" }, 403);
      }
      logInfo("Accepting unverified iOS subscription (log mode)", {
        path: "/subscription-webhook",
        userId,
        reason: claim.kind === "unsigned" ? "unsigned" : `${claim.kind}:${claim.reason}`,
      });
      // Every shipped iOS build sends the expiry of an auto-renewing
      // subscription. A missing one only comes from a hand-made request, and
      // used to store NULL — which the grace job never lapses.
      expiresAt = capUnverifiedExpiry(body.expiration_date, now);
      if (!expiresAt) return json({ error: "expiration_date is required" }, 400);
      // A client-claimed subscription id is kept only if it can't belong to
      // someone else (see unverifiedOriginalIdIsSafe). Every family member
      // can read families.billing_original_transaction_id, so taking it as
      // given let a co-caregiver copy the family's id onto a family they own
      // and receive the payer's App Store renewals. The request still
      // succeeds without it, as before for requests that sent none.
      const claimedOriginal = typeof body.original_id === "string" && body.original_id.length > 0
        ? body.original_id
        : null;
      originalTransactionId = claimedOriginal && await unverifiedOriginalIdIsSafe(claimedOriginal, userId)
        ? claimedOriginal
        : null;
    }
  } else {
    // Android: purchase_token is not verified with the Play Developer API yet
    // (deferred), and shipped Android builds send no expiry, so NULL is kept
    // for them as before (a lapse arrives via the app's own restore flow).
    expiresAt = capUnverifiedExpiry(body.expiration_date, now);
  }

  const tierInfo = tierForProduct(productId);
  if (!tierInfo) return json({ error: "Unknown product_id" }, 400);
  if (platform === "ios" && !expiresAt) return json({ error: "expiration_date is required" }, 400);

  if (body.app_account_token && !(await userExists(userId))) {
    logWarn("app_account_token user not found", { path: "/subscription-webhook" });
    return json({ error: "No user found for the provided app_account_token" }, 400);
  }

  // --- Which family it pays for --------------------------------------------
  const family = await findBillingFamily(userId);
  if (!family) return json({ error: "No family found for this user" }, 404);

  const verified = verifiedTx !== null;
  if (verifiedTx) {
    const bound = await bindReceipt({
      tx: verifiedTx,
      userId,
      familyId: family.id,
    });
    if (bound === "bound_to_other_user") {
      return json({ error: "This purchase is already linked to another Daily OK account" }, 409);
    }
  }

  try {
    const result = await applyEntitlement({
      family,
      tierInfo,
      expiresAt,
      originalTransactionId,
      payerUserId: userId,
      platform,
      verified,
      now,
    });
    if (!result.applied) {
      // 200: the app should finish the transaction; nothing is wrong with it.
      return json({ success: true, applied: false, reason: result.reason, tier: family.subscription_tier, verified });
    }
  } catch (_err) {
    return json({ error: "Failed to update subscription" }, 500);
  }

  return json({ success: true, tier: tierInfo.tier, applied: true, verified });
}
