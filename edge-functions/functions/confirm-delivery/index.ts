import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";

interface ConfirmDeliveryRequest {
  notification_log_id?: string;
  checkin_request_id?: string;
  apns_id?: string;
}

/**
 * Called by the iOS app when a push notification is received.
 * Confirms delivery so the retry system knows not to resend.
 */
export async function handleConfirmDelivery(req: Request, auth: AuthResult): Promise<Response> {
  const body: ConfirmDeliveryRequest = await req.json();

  if (!auth.userId && !auth.isServiceRole) {
    return new Response(
      JSON.stringify({ error: "Authentication required" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  const now = new Date().toISOString();

  // Confirm by notification_log_id (preferred)
  if (body.notification_log_id) {
    const { error } = await supabaseAdmin
      .from("notification_log")
      .update({
        status: "delivered",
        delivered_at: now,
        delivery_confirmed_at: now,
        next_retry_at: null,
      })
      .eq("id", body.notification_log_id);

    if (error) {
      return new Response(
        JSON.stringify({ error: "Failed to confirm delivery" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // Confirm by checkin_request_id (fallback — marks all unconfirmed for this request)
  if (body.checkin_request_id) {
    const query = supabaseAdmin
      .from("notification_log")
      .update({
        status: "delivered",
        delivered_at: now,
        delivery_confirmed_at: now,
        next_retry_at: null,
      })
      .eq("checkin_request_id", body.checkin_request_id)
      .is("delivery_confirmed_at", null);

    // Scope to the authenticated user if not service role
    if (!auth.isServiceRole && auth.userId) {
      query.eq("user_id", auth.userId);
    }

    await query;
  }

  return new Response(
    JSON.stringify({ success: true }),
    { headers: { "Content-Type": "application/json" } }
  );
}
