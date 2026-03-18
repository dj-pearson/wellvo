import { supabaseAdmin } from "../../shared/supabase.ts";
import { sendPushNotification, buildCheckinPayload } from "../../shared/apns.ts";

interface OnDemandRequest {
  receiver_id: string;
  family_id: string;
}

export async function handleOnDemandCheckin(req: Request): Promise<Response> {
  const body: OnDemandRequest = await req.json();
  const { receiver_id, family_id } = body;

  // Verify the requesting user is the family owner
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

  // Get the owner's name
  const { data: owner } = await supabaseAdmin
    .from("users")
    .select("display_name")
    .eq("id", family.owner_id)
    .single();

  // Get receiver settings for grace period
  const { data: memberRecord } = await supabaseAdmin
    .from("family_members")
    .select("id")
    .eq("family_id", family_id)
    .eq("user_id", receiver_id)
    .single();

  let gracePeriod = 30;
  if (memberRecord) {
    const { data: settings } = await supabaseAdmin
      .from("receiver_settings")
      .select("grace_period_minutes")
      .eq("family_member_id", memberRecord.id)
      .single();

    if (settings) gracePeriod = settings.grace_period_minutes;
  }

  // Create check-in request
  const { data: request, error: requestError } = await supabaseAdmin
    .from("checkin_requests")
    .insert({
      family_id,
      receiver_id,
      requested_by: family.owner_id,
      type: "on_demand",
      status: "pending",
      escalation_step: 0,
      next_escalation_at: new Date(Date.now() + gracePeriod * 60 * 1000).toISOString(),
    })
    .select()
    .single();

  if (requestError || !request) {
    return new Response(
      JSON.stringify({ error: "Failed to create check-in request", details: requestError }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // Send push notification
  const { data: tokens } = await supabaseAdmin
    .from("push_tokens")
    .select("token")
    .eq("user_id", receiver_id)
    .eq("is_active", true);

  if (tokens?.length) {
    const payload = buildCheckinPayload(
      owner?.display_name || "Your family",
      request.id,
      "on_demand"
    );

    await Promise.all(
      tokens.map((t: { token: string }) =>
        sendPushNotification(t.token, payload, {
          collapseId: `ondemand-${family_id}`,
        })
      )
    );
  }

  // Log
  await supabaseAdmin.from("notification_log").insert({
    user_id: receiver_id,
    checkin_request_id: request.id,
    type: "checkin_reminder",
    status: "sent",
  });

  return new Response(
    JSON.stringify({ success: true, request_id: request.id }),
    { headers: { "Content-Type": "application/json" } }
  );
}
