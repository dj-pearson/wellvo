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
  // fall back to authenticated user ID from JWT
  let userId: string | null = null;

  if (app_account_token) {
    // Validate UUID format before querying
    if (!UUID_REGEX.test(app_account_token)) {
      logWarn("Invalid app_account_token format", { path: "/subscription-webhook" });
      return new Response(
        JSON.stringify({ error: "Invalid app_account_token: must be a valid UUID" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // The appAccountToken is the Supabase user UUID set during purchase
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

  if (!userId && auth.userId) {
    userId = auth.userId;
  }

  if (!userId) {
    return new Response(
      JSON.stringify({ error: "Could not identify user. Ensure app_account_token is set." }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
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
  const userId = body.app_account_token || auth.userId;
  if (!userId) {
    return new Response(
      JSON.stringify({ error: "User identification required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

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
  const userId = body.app_account_token || auth.userId;
  if (!userId) {
    return new Response(
      JSON.stringify({ error: "User identification required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

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
