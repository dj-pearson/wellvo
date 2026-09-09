import { supabaseAdmin } from "../../shared/supabase.ts";
import { logWarn } from "../../shared/logger.ts";
import type { AuthResult } from "../../shared/auth.ts";

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface SubscriptionUpdate {
  product_id: string;
  transaction_id: string;
  original_id: string;
  expiration_date?: string;
  app_account_token?: string; // UUID linking to Supabase user
}

// Product ID → tier + seat limits.
//
// Two product-ID namespaces are recognized:
//   - `net.wellvo.*`  — the iOS App Store Connect source of truth (bundle id
//     com.wellvo.ios). iOS `SubscriptionService.ProductIDs` sends these.
//   - `net.dailyok.*` — the original namespace still registered for Android
//     Google Play (`SubscriptionService.PRODUCT_IDS`) and any historical/
//     sandbox iOS purchase.
//
// Per CLAUDE.md §E we never stop recognizing a product ID a subscriber may
// still hold, so BOTH namespaces map to the same tiers. iOS purchases were
// 400ing ("Unknown product_id") because only the dailyok namespace was known.
// FOLLOW-UP: unify on a single namespace once Google Play products are
// re-registered under net.wellvo.* (requires Play Console work).
const CAREGIVER = { tier: "caregiver", maxReceivers: 1, maxViewers: 3 };
const FAMILY = { tier: "family", maxReceivers: 3, maxViewers: 5 };
const FAMILY_PLUS = { tier: "family_plus", maxReceivers: 6, maxViewers: 10 };

const TIER_MAP: Record<string, { tier: string; maxReceivers: number; maxViewers: number }> = {
  // iOS / App Store Connect (source of truth)
  "net.wellvo.caregiver.monthly": CAREGIVER,
  "net.wellvo.caregiver.yearly": CAREGIVER,
  "net.wellvo.family.monthly": FAMILY,
  "net.wellvo.family.yearly": FAMILY,
  "net.wellvo.familyplus.monthly": FAMILY_PLUS,
  "net.wellvo.familyplus.yearly": FAMILY_PLUS,
  // Android / Google Play + historical iOS sandbox
  "net.dailyok.caregiver.monthly": CAREGIVER,
  "net.dailyok.caregiver.yearly": CAREGIVER,
  "net.dailyok.family.monthly": FAMILY,
  "net.dailyok.family.yearly": FAMILY,
  "net.dailyok.familyplus.monthly": FAMILY_PLUS,
  "net.dailyok.familyplus.yearly": FAMILY_PLUS,
};

// Add-on product IDs, both namespaces.
const ADDON_RECEIVER_IDS = new Set(["net.wellvo.addon.receiver", "net.dailyok.addon.receiver"]);
const ADDON_VIEWER_IDS = new Set(["net.wellvo.addon.viewer", "net.dailyok.addon.viewer"]);

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
 * Service role stays trusted: real App Store Server Notifications arrive
 * server-to-server and legitimately act for another user. Same shape as the
 * authorization check in process-checkin-response.
 */
function resolveAuthorizedUserId(
  body: SubscriptionUpdate,
  auth: AuthResult,
): { userId: string } | { response: Response } {
  const claimed = body.app_account_token;

  if (claimed && !UUID_REGEX.test(claimed)) {
    logWarn("Invalid app_account_token format", { path: "/subscription-webhook" });
    return {
      response: new Response(
        JSON.stringify({ error: "Invalid app_account_token: must be a valid UUID" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      ),
    };
  }

  if (!auth.isServiceRole && claimed && auth.userId && claimed.toLowerCase() !== auth.userId.toLowerCase()) {
    logWarn("Rejected cross-user subscription provisioning", { path: "/subscription-webhook", userId: auth.userId });
    return {
      response: new Response(
        JSON.stringify({ error: "You can only update your own subscription" }),
        { status: 403, headers: { "Content-Type": "application/json" } },
      ),
    };
  }

  const userId = claimed || auth.userId;
  if (!userId) {
    return {
      response: new Response(
        JSON.stringify({ error: "Could not identify user. Ensure app_account_token is set." }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      ),
    };
  }

  return { userId };
}

export async function handleSubscriptionWebhook(req: Request, auth: AuthResult): Promise<Response> {
  const body: SubscriptionUpdate = await req.json();
  const { product_id, expiration_date, app_account_token } = body;

  const tierInfo = TIER_MAP[product_id];
  if (!tierInfo) {
    if (ADDON_RECEIVER_IDS.has(product_id)) {
      return handleAddonReceiver(body, auth);
    }
    if (ADDON_VIEWER_IDS.has(product_id)) {
      return handleAddonViewer(body, auth);
    }

    return new Response(
      JSON.stringify({ error: "Unknown product_id" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Identify the user — prefer appAccountToken (linked at purchase time),
  // fall back to the authenticated user ID from the JWT. Authorization for
  // that choice lives in resolveAuthorizedUserId.
  const resolved = resolveAuthorizedUserId(body, auth);
  if ("response" in resolved) return resolved.response;
  let userId: string | null = resolved.userId;

  if (app_account_token) {
    // The appAccountToken is the Supabase user UUID set during purchase.
    const { data: user } = await supabaseAdmin
      .from("users")
      .select("id")
      .eq("id", app_account_token)
      .single();

    if (!user) {
      logWarn("app_account_token user not found", { path: "/subscription-webhook" });
      return new Response(
        JSON.stringify({ error: "No user found for the provided app_account_token" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    userId = user.id;
  }


  // Verify the user owns a family
  const { data: family } = await supabaseAdmin
    .from("families")
    .select("id")
    .eq("owner_id", userId)
    .single();

  if (!family) {
    return new Response(
      JSON.stringify({ error: "No family found for this user" }),
      { status: 404, headers: { "Content-Type": "application/json" } }
    );
  }

  // Update the family subscription
  const { error } = await supabaseAdmin
    .from("families")
    .update({
      subscription_tier: tierInfo.tier,
      subscription_status: "active",
      subscription_expires_at: expiration_date || null,
      max_receivers: tierInfo.maxReceivers,
      max_viewers: tierInfo.maxViewers,
    })
    .eq("id", family.id);

  if (error) {
    return new Response(
      JSON.stringify({ error: "Failed to update subscription" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ success: true, tier: tierInfo.tier }),
    { headers: { "Content-Type": "application/json" } }
  );
}

async function handleAddonReceiver(body: SubscriptionUpdate, auth: AuthResult): Promise<Response> {
  // Same rule as the tier path. This one was worse: it took
  // body.app_account_token with no UUID validation and no ownership check at
  // all, so any authenticated caller could add a paid seat to another owner's
  // family (US-EDGE004).
  const resolved = resolveAuthorizedUserId(body, auth);
  if ("response" in resolved) return resolved.response;
  const userId = resolved.userId;

  const { error } = await supabaseAdmin.rpc("increment_max_receivers", { p_owner_id: userId });

  if (error) {
    return new Response(
      JSON.stringify({ error: "Failed to add receiver slot" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ success: true, addon: "receiver" }),
    { headers: { "Content-Type": "application/json" } }
  );
}

async function handleAddonViewer(body: SubscriptionUpdate, auth: AuthResult): Promise<Response> {
  // Same rule as the tier path. This one was worse: it took
  // body.app_account_token with no UUID validation and no ownership check at
  // all, so any authenticated caller could add a paid seat to another owner's
  // family (US-EDGE004).
  const resolved = resolveAuthorizedUserId(body, auth);
  if ("response" in resolved) return resolved.response;
  const userId = resolved.userId;

  const { error } = await supabaseAdmin.rpc("increment_max_viewers", { p_owner_id: userId });

  if (error) {
    return new Response(
      JSON.stringify({ error: "Failed to add viewer slot" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ success: true, addon: "viewer" }),
    { headers: { "Content-Type": "application/json" } }
  );
}
