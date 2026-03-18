import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";

interface ProcessCheckinRequest {
  checkin_request_id?: string;
  receiver_id?: string;
  family_id?: string;
  source?: string;
}

export async function handleProcessCheckinResponse(req: Request, auth: AuthResult): Promise<Response> {
  const body: ProcessCheckinRequest = await req.json();

  let requestId = body.checkin_request_id;
  let receiverId = body.receiver_id;
  let familyId = body.family_id;
  const source = body.source || "app";

  // If responding by request ID, look it up
  if (requestId && !receiverId) {
    const { data: request } = await supabaseAdmin
      .from("checkin_requests")
      .select("receiver_id, family_id")
      .eq("id", requestId)
      .single();

    if (!request) {
      return new Response(
        JSON.stringify({ error: "Check-in request not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    receiverId = request.receiver_id;
    familyId = request.family_id;
  }

  if (!receiverId || !familyId) {
    return new Response(
      JSON.stringify({ error: "receiver_id and family_id are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // AUTHORIZATION: Verify the authenticated user IS the receiver
  // Service role calls (from notification actions) are trusted
  if (!auth.isServiceRole) {
    if (!auth.userId || auth.userId !== receiverId) {
      return new Response(
        JSON.stringify({ error: "You can only check in for yourself" }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // Verify the receiver is actually a member of this family
  const { data: membership } = await supabaseAdmin
    .from("family_members")
    .select("id, role, status")
    .eq("family_id", familyId)
    .eq("user_id", receiverId)
    .eq("status", "active")
    .single();

  if (!membership || membership.role !== "receiver") {
    return new Response(
      JSON.stringify({ error: "Invalid receiver or family" }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  // Check for existing check-in today (duplicate prevention)
  const today = new Date().toISOString().split("T")[0];
  const { data: existingCheckIn } = await supabaseAdmin
    .from("checkins")
    .select()
    .eq("receiver_id", receiverId)
    .eq("family_id", familyId)
    .gte("checked_in_at", `${today}T00:00:00Z`)
    .lt("checked_in_at", `${today}T23:59:59Z`)
    .maybeSingle();

  if (existingCheckIn) {
    // Already checked in today — return existing check-in (not an error)
    // Still mark pending requests as checked_in below
    return markRequestsAndRespond(receiverId, familyId, existingCheckIn);
  }

  // Record the check-in
  const { data: checkIn, error: checkInError } = await supabaseAdmin
    .from("checkins")
    .insert({
      receiver_id: receiverId,
      family_id: familyId,
      source,
    })
    .select()
    .single();

  if (checkInError) {
    return new Response(
      JSON.stringify({ error: "Failed to record check-in" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  return markRequestsAndRespond(receiverId, familyId, checkIn);
}

async function markRequestsAndRespond(
  receiverId: string,
  familyId: string,
  checkIn: Record<string, unknown>,
): Promise<Response> {
  // Mark all pending requests for this receiver+family as checked_in
  await supabaseAdmin
    .from("checkin_requests")
    .update({
      status: "checked_in",
      responded_at: new Date().toISOString(),
    })
    .eq("receiver_id", receiverId)
    .eq("family_id", familyId)
    .eq("status", "pending");

  return new Response(
    JSON.stringify({ success: true, checkin: checkIn }),
    { headers: { "Content-Type": "application/json" } }
  );
}
