import { supabaseAdmin } from "../../shared/supabase.ts";

interface SubscriptionUpdate {
  product_id: string;
  transaction_id: string;
  original_id: string;
  expiration_date?: string;
}

const TIER_MAP: Record<string, { tier: string; maxReceivers: number; maxViewers: number }> = {
  "net.wellvo.family.monthly": { tier: "family", maxReceivers: 2, maxViewers: 2 },
  "net.wellvo.family.yearly": { tier: "family", maxReceivers: 2, maxViewers: 2 },
  "net.wellvo.familyplus.monthly": { tier: "family_plus", maxReceivers: 5, maxViewers: 5 },
  "net.wellvo.familyplus.yearly": { tier: "family_plus", maxReceivers: 5, maxViewers: 5 },
};

export async function handleSubscriptionWebhook(req: Request): Promise<Response> {
  const body: SubscriptionUpdate = await req.json();
  const { product_id, expiration_date } = body;

  const tierInfo = TIER_MAP[product_id];
  if (!tierInfo) {
    // Might be an add-on — handle separately
    if (product_id === "net.wellvo.addon.receiver") {
      return handleAddonReceiver(req, body);
    }
    if (product_id === "net.wellvo.addon.viewer") {
      return handleAddonViewer(req, body);
    }

    return new Response(
      JSON.stringify({ error: "Unknown product_id", product_id }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Find the user's family by matching the auth context
  // In production, you'd verify the App Store Server Notification JWT
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace("Bearer ", "");

  // For client-side syncs, look up the user from their session
  const { data: userData } = await supabaseAdmin.auth.getUser(token);
  const userId = userData?.user?.id;

  if (!userId) {
    // This might be a server-to-server notification — find by original_transaction_id
    // For MVP, we rely on client-side sync
    return new Response(
      JSON.stringify({ error: "Could not identify user" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Update the user's family subscription
  const { error } = await supabaseAdmin
    .from("families")
    .update({
      subscription_tier: tierInfo.tier,
      subscription_status: "active",
      subscription_expires_at: expiration_date || null,
      max_receivers: tierInfo.maxReceivers,
      max_viewers: tierInfo.maxViewers,
    })
    .eq("owner_id", userId);

  if (error) {
    return new Response(
      JSON.stringify({ error: "Failed to update subscription", details: error }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ success: true, tier: tierInfo.tier }),
    { headers: { "Content-Type": "application/json" } }
  );
}

async function handleAddonReceiver(_req: Request, body: SubscriptionUpdate): Promise<Response> {
  // Increment max_receivers for the family
  // Implementation depends on how add-ons are structured in App Store Connect
  console.log("Add-on receiver purchased:", body);
  return new Response(
    JSON.stringify({ success: true, addon: "receiver" }),
    { headers: { "Content-Type": "application/json" } }
  );
}

async function handleAddonViewer(_req: Request, body: SubscriptionUpdate): Promise<Response> {
  console.log("Add-on viewer purchased:", body);
  return new Response(
    JSON.stringify({ success: true, addon: "viewer" }),
    { headers: { "Content-Type": "application/json" } }
  );
}
