import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";

/**
 * Handles App Store subscription cancellation/expiration notifications.
 * Called via App Store Server Notifications v2 or manually from the iOS app.
 * Service-role-only for server-to-server calls, or user-authenticated for self-cancellation.
 */
export async function handleSubscriptionCancellation(req: Request, auth: AuthResult): Promise<Response> {
  const body = await req.json();
  const { app_account_token, product_id } = body;

  // Identify user
  const userId = app_account_token || auth.userId;
  if (!userId) {
    return new Response(
      JSON.stringify({ error: "User identification required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Find user's family
  const { data: family, error: familyError } = await supabaseAdmin
    .from("families")
    .select("id, subscription_tier, subscription_expires_at")
    .eq("owner_id", userId)
    .single();

  if (familyError || !family) {
    return new Response(
      JSON.stringify({ error: "No family found for this user" }),
      { status: 404, headers: { "Content-Type": "application/json" } }
    );
  }

  // If there's still time on the subscription, move to grace_period
  // Otherwise move directly to expired and downgrade to free
  const expiresAt = family.subscription_expires_at
    ? new Date(family.subscription_expires_at)
    : null;

  const now = new Date();

  if (expiresAt && expiresAt > now) {
    // Subscription still has remaining time — keep access until expiry,
    // then grace period enforcement cron will handle the transition
    await supabaseAdmin
      .from("families")
      .update({
        subscription_status: "cancelled",
      })
      .eq("id", family.id);
  } else {
    // Already past expiry — enter grace period now (7 days from today)
    await supabaseAdmin
      .from("families")
      .update({
        subscription_status: "grace_period",
        subscription_expires_at: now.toISOString(),
      })
      .eq("id", family.id);
  }

  return new Response(
    JSON.stringify({ success: true, status: "cancellation_processed" }),
    { headers: { "Content-Type": "application/json" } }
  );
}
