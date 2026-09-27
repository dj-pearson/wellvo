import { supabaseAdmin } from "../../shared/supabase.ts";
import { sendPushNotification, buildCheckinPayload } from "../../shared/apns.ts";
import { sendFCMNotification, buildFCMCheckinPayload } from "../../shared/fcm.ts";
import type { AuthResult } from "../../shared/auth.ts";
import { isValidUUID } from "../../shared/validation.ts";

/**
 * A second "Check on" tap within this window re-sends the push for the request
 * that is already open instead of starting another, independent escalation
 * chain (each pending row escalates on its own: reminder, owner alert, viewer
 * alert + SMS).
 */
const REUSE_OPEN_REQUEST_MS = 5 * 60 * 1000;

interface OnDemandRequest {
  receiver_id: string;
  family_id: string;
}

export async function handleOnDemandCheckin(req: Request, auth: AuthResult): Promise<Response> {
  const body: OnDemandRequest = await req.json();
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

  // AUTHORIZATION: Verify the requesting user is the family owner
  if (!auth.isServiceRole) {
    if (!auth.userId || auth.userId !== family.owner_id) {
      return new Response(
        JSON.stringify({ error: "Only the family owner can send check-in requests" }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // Verify the receiver is an active member of this family
  const { data: receiverMember } = await supabaseAdmin
    .from("family_members")
    .select("id, role, status")
    .eq("family_id", family_id)
    .eq("user_id", receiver_id)
    .eq("status", "active")
    .single();

  if (!receiverMember || receiverMember.role !== "receiver") {
    return new Response(
      JSON.stringify({ error: "Receiver not found in this family" }),
      { status: 404, headers: { "Content-Type": "application/json" } }
    );
  }

  // Get the owner's name for the notification
  const { data: owner } = await supabaseAdmin
    .from("users")
    .select("display_name")
    .eq("id", family.owner_id)
    .single();

  // Get receiver settings for grace period
  let gracePeriod = 30;
  const { data: settings } = await supabaseAdmin
    .from("receiver_settings")
    .select("grace_period_minutes")
    .eq("family_member_id", receiverMember.id)
    .single();

  if (settings) gracePeriod = settings.grace_period_minutes;

  // Reuse a still-escalating on-demand request raised moments ago (repeated
  // taps) rather than stacking parallel escalation chains. A stood-down
  // request (next_escalation_at NULL) is never reused.
  const reuseSince = new Date(Date.now() - REUSE_OPEN_REQUEST_MS).toISOString();
  const { data: openRequests } = await supabaseAdmin
    .from("checkin_requests")
    .select("id")
    .eq("family_id", family_id)
    .eq("receiver_id", receiver_id)
    .eq("type", "on_demand")
    .eq("status", "pending")
    .not("next_escalation_at", "is", null)
    .gte("created_at", reuseSince)
    .order("created_at", { ascending: false })
    .limit(1);

  let request: { id: string } | null = openRequests?.[0] ?? null;
  const deduplicated = request != null;

  if (!request) {
    // Create check-in request
    const { data: created, error: requestError } = await supabaseAdmin
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

    if (requestError || !created) {
      return new Response(
        JSON.stringify({ error: "Failed to create check-in request" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
    request = created;
  }
  const requestId: string = request.id;

  // Send push notification
  const { data: tokens } = await supabaseAdmin
    .from("push_tokens")
    .select("token, platform")
    .eq("user_id", receiver_id)
    .eq("is_active", true);

  let deliveredDevices = 0;
  if (tokens?.length) {
    const displayName = owner?.display_name || "Your family";
    const apnsPayload = buildCheckinPayload(displayName, requestId, "on_demand");
    const fcmPayload = buildFCMCheckinPayload(displayName, requestId, receiver_id, "on_demand");

    const results = await Promise.all(
      tokens.map((t: { token: string; platform: string }) => {
        if (t.platform === "android") {
          return sendFCMNotification(t.token, fcmPayload);
        }
        return sendPushNotification(t.token, apnsPayload, {
          collapseId: `ondemand-${family_id}`,
        });
      })
    );

    deliveredDevices = results.filter((r) => r.success).length;

    // Deactivate expired/invalid tokens
    for (let i = 0; i < results.length; i++) {
      const isInvalid =
        results[i].statusCode === 410 ||
        results[i].reason === "NOT_FOUND" ||
        results[i].reason === "UNREGISTERED";
      if (isInvalid) {
        await supabaseAdmin
          .from("push_tokens")
          .update({ is_active: false })
          .eq("token", tokens[i].token);
        console.log(`Deactivated invalid ${tokens[i].platform} token for user ${receiver_id}`);
      }
    }
  }

  // Log notification
  await supabaseAdmin.from("notification_log").insert({
    user_id: receiver_id,
    checkin_request_id: requestId,
    type: "checkin_reminder",
    status: deliveredDevices > 0 ? "sent" : "failed",
  });

  return new Response(
    // `delivered_devices` and `deduplicated` are additive, optional fields: the
    // app tells the owner when nothing could be notified ("call instead?").
    JSON.stringify({
      success: true,
      request_id: requestId,
      delivered_devices: deliveredDevices,
      deduplicated,
    }),
    { headers: { "Content-Type": "application/json" } }
  );
}
