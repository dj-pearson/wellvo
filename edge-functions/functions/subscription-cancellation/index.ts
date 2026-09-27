import type { AuthResult } from "../../shared/auth.ts";
import { resolveAuthorizedUserId } from "../subscription-webhook/index.ts";
import { findBillingFamily, startGracePeriod } from "../../shared/subscription-billing.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

/**
 * Records that a family's subscription has been cancelled.
 *
 * No shipped app calls this route, and Apple's server notifications now go to
 * /app-store-notifications (signed). What remains is kept for server-to-server
 * use and for an app acting on its OWN account.
 *
 * Two fixes (2026-09-27):
 *  - Authorization. `app_account_token` came from the request body and was
 *    trusted as-is, so any signed-in user — a receiver, a removed co-caregiver —
 *    could name an owner's id and stop that family's check-ins. A client may
 *    now only name itself (the same rule as /subscription-webhook, US-EDGE004).
 *  - Cancelled-but-paid families kept getting nothing. This wrote
 *    subscription_status = 'cancelled', which every check-in dispatcher
 *    excludes and the nightly job never moved on, so check-ins stopped the day
 *    of cancellation and never came back. A family with paid time left now
 *    stays 'active' until its expiry, when the nightly job starts the normal
 *    seven-day grace period.
 */
export async function handleSubscriptionCancellation(req: Request, auth: AuthResult): Promise<Response> {
  let body: { app_account_token?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body" }, 400);
  }

  const resolved = resolveAuthorizedUserId(body, auth, "/subscription-cancellation");
  if ("response" in resolved) return resolved.response;

  const family = await findBillingFamily(resolved.userId).catch(() => null);
  if (!family) return json({ error: "No family found for this user" }, 404);

  const expiresAt = family.subscription_expires_at ? new Date(family.subscription_expires_at) : null;
  const now = new Date();

  // A (grandfathered) Free family has no subscription to cancel; putting it in
  // grace would stop its check-ins a week later.
  if (family.subscription_tier === "free") {
    return json({ success: true, status: "cancellation_processed" });
  }

  if (expiresAt && expiresAt > now) {
    // Paid time remains: nothing changes until it runs out.
    return json({ success: true, status: "cancellation_processed", ends_at: expiresAt.toISOString() });
  }

  try {
    await startGracePeriod(family, now);
  } catch {
    return json({ error: "Failed to record cancellation" }, 500);
  }
  return json({ success: true, status: "cancellation_processed" });
}
