import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";

interface SubscriptionUpdate {
  product_id: string;
  transaction_id: string;
  original_id: string;
  expiration_date?: string;
  app_account_token?: string; // UUID linking to Supabase user
}

const TIER_MAP: Record<string, { tier: string; maxReceivers: number; maxViewers: number }> = {
  "net.wellvo.family.monthly": { tier: "family", maxReceivers: 2, maxViewers: 2 },
  "net.wellvo.family.yearly": { tier: "family", maxReceivers: 2, maxViewers: 2 },
  "net.wellvo.familyplus.monthly": { tier: "family_plus", maxReceivers: 5, maxViewers: 5 },
  "net.wellvo.familyplus.yearly": { tier: "family_plus", maxReceivers: 5, maxViewers: 5 },
};

export async function handleSubscriptionWebhook(req: Request, auth: AuthResult): Promise<Response> {
  const body: SubscriptionUpdate = await req.json();
  const { product_id, expiration_date, app_account_token } = body;

  const tierInfo = TIER_MAP[product_id];
  if (!tierInfo) {
    if (product_id === "net.wellvo.addon.receiver") {
      return handleAddonReceiver(body, auth);
    }
    if (product_id === "net.wellvo.addon.viewer") {
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
    // The appAccountToken is the Supabase user UUID set during purchase
    // Verify this user actually exists
    const { data: user } = await supabaseAdmin
      .from("users")
      .select("id")
      .eq("id", app_account_token)
      .single();

    if (user) {
      userId = user.id;
    }
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
