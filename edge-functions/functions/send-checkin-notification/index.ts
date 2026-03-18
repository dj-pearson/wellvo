import { supabaseAdmin } from "../../shared/supabase.ts";
import { sendPushNotification, buildCheckinPayload } from "../../shared/apns.ts";

interface SendCheckinRequest {
  receiver_id: string;
  family_id: string;
  type: "scheduled" | "on_demand";
}

export async function handleSendCheckinNotification(req: Request): Promise<Response> {
  const body: SendCheckinRequest = await req.json();
  const { receiver_id, family_id, type } = body;

  // Get the receiver's push tokens
  const { data: tokens, error: tokenError } = await supabaseAdmin
    .from("push_tokens")
    .select("token")
    .eq("user_id", receiver_id)
    .eq("is_active", true);

  if (tokenError || !tokens?.length) {
    return new Response(
      JSON.stringify({ error: "No active push tokens for receiver", details: tokenError }),
      { status: 404, headers: { "Content-Type": "application/json" } }
    );
  }

  // Get the receiver's display name
  const { data: user } = await supabaseAdmin
    .from("users")
    .select("display_name")
    .eq("id", receiver_id)
    .single();

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

  const payload = buildCheckinPayload(
    user?.display_name || "Your family",
    requestId,
    type
  );

  // Send to all active tokens
  const results = await Promise.all(
    tokens.map((t: { token: string }) =>
      sendPushNotification(t.token, payload, {
        collapseId: `checkin-${family_id}`,
      })
    )
  );

  // Log notifications
  for (const result of results) {
    await supabaseAdmin.from("notification_log").insert({
      user_id: receiver_id,
      checkin_request_id: requestId,
      type: "checkin_reminder",
      status: result.success ? "sent" : "failed",
    });
  }

  // Deactivate tokens that returned 410 (expired)
  for (let i = 0; i < results.length; i++) {
    if (results[i].statusCode === 410) {
      await supabaseAdmin
        .from("push_tokens")
        .update({ is_active: false })
        .eq("token", tokens[i].token);
    }
  }

  const successCount = results.filter((r) => r.success).length;

  return new Response(
    JSON.stringify({
      success: successCount > 0,
      sent: successCount,
      failed: results.length - successCount,
    }),
    { headers: { "Content-Type": "application/json" } }
  );
}
