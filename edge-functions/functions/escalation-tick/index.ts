import { supabaseAdmin } from "../../shared/supabase.ts";
import { sendPushNotification, buildCheckinPayload } from "../../shared/apns.ts";
import { sendSMS, buildEscalationSMS } from "../../shared/sms.ts";
import type { AuthResult } from "../../shared/auth.ts";

interface EscalationRequest {
  request_id: string;
  receiver_id: string;
  family_id: string;
  escalation_step: number;
  owner_id: string;
}

export async function handleEscalationTick(req: Request, _auth: AuthResult): Promise<Response> {
  // This function is service-role-only (enforced by server.ts route config)
  const body: EscalationRequest = await req.json();
  const { request_id, receiver_id, family_id, escalation_step, owner_id } = body;

  if (escalation_step <= 1) {
    // Step 1: Second reminder to receiver
    const { data: receiverTokens } = await supabaseAdmin
      .from("push_tokens")
      .select("token")
      .eq("user_id", receiver_id)
      .eq("is_active", true);

    if (receiverTokens?.length) {
      const payload = buildCheckinPayload("", request_id, "escalation", escalation_step);
      await Promise.all(
        receiverTokens.map((t: { token: string }) =>
          sendPushNotification(t.token, payload, { priority: 10 })
        )
      );
    }

    await supabaseAdmin.from("notification_log").insert({
      user_id: receiver_id,
      checkin_request_id: request_id,
      type: "escalation",
      status: "sent",
    });
  } else if (escalation_step === 2) {
    // Step 2: Alert to Owner
    const { data: ownerTokens } = await supabaseAdmin
      .from("push_tokens")
      .select("token")
      .eq("user_id", owner_id)
      .eq("is_active", true);

    const { data: receiver } = await supabaseAdmin
      .from("users")
      .select("display_name")
      .eq("id", receiver_id)
      .single();

    if (ownerTokens?.length) {
      const payload = {
        aps: {
          alert: {
            title: "Missed Check-In",
            body: `${receiver?.display_name || "Your family member"} hasn't checked in yet. They've been reminded twice.`,
          },
          sound: "urgent.caf",
          "interruption-level": "time-sensitive" as const,
          "thread-id": `alert-${request_id}`,
        },
        checkin_request_id: request_id,
        type: "owner_alert",
      };

      await Promise.all(
        ownerTokens.map((t: { token: string }) =>
          sendPushNotification(t.token, payload, { priority: 10 })
        )
      );
    }

    // SMS fallback for owner — send if push tokens are missing or as supplement
    const { data: ownerUser } = await supabaseAdmin
      .from("users")
      .select("phone")
      .eq("id", owner_id)
      .single();

    // Check if SMS escalation is enabled for this receiver's settings
    const { data: receiverMember } = await supabaseAdmin
      .from("family_members")
      .select("id")
      .eq("user_id", receiver_id)
      .eq("family_id", family_id)
      .single();

    let smsEnabled = false;
    if (receiverMember) {
      const { data: settings } = await supabaseAdmin
        .from("receiver_settings")
        .select("sms_escalation_enabled")
        .eq("family_member_id", receiverMember.id)
        .single();
      smsEnabled = settings?.sms_escalation_enabled ?? false;
    }

    if (smsEnabled && ownerUser?.phone) {
      const smsBody = buildEscalationSMS(
        receiver?.display_name || "A family member",
        "owner_alert"
      );
      await sendSMS(ownerUser.phone, smsBody);
    }

    await supabaseAdmin.from("notification_log").insert({
      user_id: owner_id,
      checkin_request_id: request_id,
      type: "owner_alert",
      status: "sent",
    });
  } else if (escalation_step >= 3) {
    // Step 3: Alert to all Viewers
    const { data: viewers } = await supabaseAdmin
      .from("family_members")
      .select("user_id")
      .eq("family_id", family_id)
      .eq("role", "viewer")
      .eq("status", "active");

    const { data: receiver } = await supabaseAdmin
      .from("users")
      .select("display_name")
      .eq("id", receiver_id)
      .single();

    if (viewers?.length) {
      for (const viewer of viewers) {
        const { data: viewerTokens } = await supabaseAdmin
          .from("push_tokens")
          .select("token")
          .eq("user_id", viewer.user_id)
          .eq("is_active", true);

        if (viewerTokens?.length) {
          const payload = {
            aps: {
              alert: {
                title: "Family Alert",
                body: `${receiver?.display_name || "A family member"} has missed their check-in today.`,
              },
              sound: "default",
              "interruption-level": "active" as const,
            },
            checkin_request_id: request_id,
            type: "viewer_alert",
          };

          await Promise.all(
            viewerTokens.map((t: { token: string }) =>
              sendPushNotification(t.token, payload)
            )
          );
        }

        // SMS fallback for viewers with phone numbers
        const { data: viewerUser } = await supabaseAdmin
          .from("users")
          .select("phone")
          .eq("id", viewer.user_id)
          .single();

        if (viewerUser?.phone) {
          const smsBody = buildEscalationSMS(
            receiver?.display_name || "A family member",
            "viewer_alert"
          );
          await sendSMS(viewerUser.phone, smsBody);
        }

        await supabaseAdmin.from("notification_log").insert({
          user_id: viewer.user_id,
          checkin_request_id: request_id,
          type: "viewer_alert",
          status: "sent",
        });
      }
    }
  }

  return new Response(
    JSON.stringify({ success: true, escalation_step }),
    { headers: { "Content-Type": "application/json" } }
  );
}
