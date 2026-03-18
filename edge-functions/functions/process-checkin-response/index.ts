import { supabaseAdmin } from "../../shared/supabase.ts";

interface ProcessCheckinRequest {
  checkin_request_id?: string;
  receiver_id?: string;
  family_id?: string;
  source?: string;
}

export async function handleProcessCheckinResponse(req: Request): Promise<Response> {
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
      JSON.stringify({ error: "Failed to record check-in", details: checkInError }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // Mark all pending requests for this receiver+family as checked_in
  const { error: updateError } = await supabaseAdmin
    .from("checkin_requests")
    .update({
      status: "checked_in",
      responded_at: new Date().toISOString(),
    })
    .eq("receiver_id", receiverId)
    .eq("family_id", familyId)
    .eq("status", "pending");

  if (updateError) {
    console.error("Failed to update check-in requests:", updateError);
  }

  return new Response(
    JSON.stringify({ success: true, checkin: checkIn }),
    { headers: { "Content-Type": "application/json" } }
  );
}
