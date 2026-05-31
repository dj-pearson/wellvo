import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";
import { isValidUUID } from "../../shared/validation.ts";

interface CancelEscalationRequest {
  receiver_id: string;
  family_id: string;
}

/**
 * Owner "stand down" — stops the escalation chain for a receiver's currently
 * pending check-in request(s) without falsely recording a check-in. Used when
 * the owner has reached the receiver another way (phone, in person) and wants
 * the reminders/alerts to stop.
 *
 * Mechanism: set next_escalation_at = NULL on the receiver's pending requests.
 * escalation_tick only selects rows where `next_escalation_at <= NOW()`, so a
 * NULL value removes them from the escalation sweep. The request stays
 * 'pending' until the receiver actually checks in or expire_old_requests
 * retires it after 24h — we deliberately do not fabricate a check-in.
 */
export async function handleCancelEscalation(req: Request, auth: AuthResult): Promise<Response> {
  const body: CancelEscalationRequest = await req.json();
  const { receiver_id, family_id } = body;

  if (!receiver_id || !isValidUUID(receiver_id) || !family_id || !isValidUUID(family_id)) {
    return new Response(
      JSON.stringify({ error: "Valid receiver_id and family_id are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Get the family and verify ownership
  const { data: family } = await supabaseAdmin
    .from("families")
    .select("owner_id")
    .eq("id", family_id)
    .single();

  if (!family) {
    return new Response(
      JSON.stringify({ error: "Family not found" }),
      { status: 404, headers: { "Content-Type": "application/json" } }
    );
  }

  // AUTHORIZATION: only the family owner may stand down an escalation
  if (!auth.isServiceRole) {
    if (!auth.userId || auth.userId !== family.owner_id) {
      return new Response(
        JSON.stringify({ error: "Only the family owner can stand down an escalation" }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // Stop escalation for any pending requests for this receiver in this family.
  const { data: updated, error } = await supabaseAdmin
    .from("checkin_requests")
    .update({ next_escalation_at: null })
    .eq("family_id", family_id)
    .eq("receiver_id", receiver_id)
    .eq("status", "pending")
    .select("id");

  if (error) {
    return new Response(
      JSON.stringify({ error: "Failed to stand down escalation" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ success: true, cancelled: updated?.length ?? 0 }),
    { headers: { "Content-Type": "application/json" } }
  );
}
