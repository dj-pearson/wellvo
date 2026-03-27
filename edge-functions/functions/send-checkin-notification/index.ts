import { supabaseAdmin } from "../../shared/supabase.ts";
import { sendPushNotification, buildCheckinPayload } from "../../shared/apns.ts";
import { sendFCMNotification, buildFCMCheckinPayload } from "../../shared/fcm.ts";
import type { AuthResult } from "../../shared/auth.ts";

interface SendCheckinRequest {
  receiver_id: string;
  family_id: string;
  type: "scheduled" | "on_demand";
  is_retry?: boolean;
  notification_log_id?: string;
}

export async function handleSendCheckinNotification(req: Request, _auth: AuthResult): Promise<Response> {
  // This function is service-role-only (enforced by server.ts route config)
  const body: SendCheckinRequest = await req.json();
  const { receiver_id, family_id, type, is_retry, notification_log_id } = body;

  // Get the receiver's push tokens with platform info
  const { data: tokens, error: tokenError } = await supabaseAdmin
    .from("push_tokens")
    .select("token, platform")
    .eq("user_id", receiver_id)
    .eq("is_active", true);

  if (tokenError || !tokens?.length) {
    return new Response(
      JSON.stringify({ error: "No active push tokens for receiver" }),
      { status: 404, headers: { "Content-Type": "application/json" } }
    );
  }

  // Get the receiver's display name
  const { data: user } = await supabaseAdmin
    .from("users")
    .select("display_name")
    .eq("id", receiver_id)
    .single();

  // Fetch receiver_mode from receiver_settings via family_members
  let receiverMode: string | undefined;
  const { data: memberRow } = await supabaseAdmin
    .from("family_members")
    .select("id")
    .eq("user_id", receiver_id)
    .eq("family_id", family_id)
    .eq("status", "active")
    .single();

  if (memberRow) {
    const { data: settings } = await supabaseAdmin
      .from("receiver_settings")
      .select("receiver_mode")
      .eq("family_member_id", memberRow.id)
      .single();

    if (settings?.receiver_mode) {
      receiverMode = settings.receiver_mode;
    }
  }

  // Find or create a pending check-in request
  const { data: existingRequest } = await supabaseAdmin
    .from("checkin_requests")
    .select("id")
    .eq("receiver_id", receiver_id)
    .eq("family_id", family_id)
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .limit(1)
    .single();

  const requestId = existingRequest?.id || crypto.randomUUID();
  const displayName = user?.display_name || "Your family";

  // Build payloads for each platform
  const apnsPayload = buildCheckinPayload(displayName, requestId, type, undefined, receiverMode);
  const fcmPayload = buildFCMCheckinPayload(displayName, requestId, receiver_id, type, undefined, receiverMode);

  // Send to all active tokens, routing by platform
  const results = await Promise.all(
    tokens.map((t: { token: string; platform: string }) => {
      if (t.platform === "android") {
        return sendFCMNotification(t.token, fcmPayload);
      } else {
        // Default to APNs (ios or unknown platform)
        return sendPushNotification(t.token, apnsPayload, {
          collapseId: `checkin-${family_id}`,
        });
      }
    })
  );

  // Log notifications with retry tracking
  for (const result of results) {
    if (is_retry && notification_log_id) {
      await supabaseAdmin
        .from("notification_log")
        .update({
          status: result.success ? "sent" : "failed",
          retry_count: supabaseAdmin.rpc ? undefined : undefined,
        })
        .eq("id", notification_log_id);
    } else {
      await supabaseAdmin.from("notification_log").insert({
        user_id: receiver_id,
        checkin_request_id: requestId,
        type: "checkin_reminder",
        status: result.success ? "sent" : "failed",
        next_retry_at: result.success
          ? new Date(Date.now() + 2 * 60 * 1000).toISOString()
          : null,
        max_retries: 3,
      });
    }
  }

  // Deactivate tokens that returned errors indicating invalid/expired tokens
  for (let i = 0; i < results.length; i++) {
    const isInvalidToken =
      results[i].statusCode === 410 || // APNs expired
      results[i].reason === "NOT_FOUND" || // FCM unregistered
      results[i].reason === "UNREGISTERED"; // FCM unregistered

    if (isInvalidToken) {
      await supabaseAdmin
        .from("push_tokens")
        .update({ is_active: false })
        .eq("token", tokens[i].token);

      console.log(`Deactivated invalid ${tokens[i].platform} token for user ${receiver_id}`);
    }
  }

  const successCount = results.filter((r) => r.success).length;

  console.log(
    `Notification sent: receiver=${receiver_id}, type=${type}, ` +
    `total=${results.length}, success=${successCount}, failed=${results.length - successCount}`
  );

  return new Response(
    JSON.stringify({
      success: successCount > 0,
      sent: successCount,
      failed: results.length - successCount,
    }),
    { headers: { "Content-Type": "application/json" } }
  );
}
