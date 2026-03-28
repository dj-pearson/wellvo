import { supabaseAdmin } from "../../shared/supabase.ts";
import { sendPushNotification, buildCheckinPayload } from "../../shared/apns.ts";
import { sendFCMNotification, buildFCMCheckinPayload, buildFCMAlertPayload } from "../../shared/fcm.ts";
import { sendSMS, buildEscalationSMS } from "../../shared/sms.ts";
import { logInfo, logWarn, logError } from "../../shared/logger.ts";
import type { AuthResult } from "../../shared/auth.ts";
import { sanitizeDisplayName } from "../../shared/validation.ts";

interface PushToken {
  token: string;
  platform: string;
}

async function sendByPlatform(
  tokens: PushToken[],
  apnsPayload: Record<string, unknown>,
  fcmTitle: string,
  fcmBody: string,
  fcmData: Record<string, string>,
  apnsOptions?: { priority?: number; collapseId?: string },
): Promise<{ success: boolean; statusCode: number; reason?: string }[]> {
  return Promise.all(
    tokens.map((t) => {
      if (t.platform === "android") {
        return sendFCMNotification(t.token, buildFCMAlertPayload(fcmTitle, fcmBody, fcmData));
      }
      return sendPushNotification(t.token, apnsPayload, apnsOptions);
    })
  );
}

async function deactivateInvalidTokens(
  tokens: PushToken[],
  results: { success: boolean; statusCode: number; reason?: string }[],
  userId: string,
): Promise<void> {
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
      console.log(`Deactivated invalid ${tokens[i].platform} token for user ${userId}`);
    }
  }
}

interface EscalationRequest {
  request_id?: string;
  receiver_id: string;
  family_id: string;
  escalation_step?: number;
  owner_id?: string;
  // Special alert fields
  type?: "geofence_alert" | "low_battery_alert";
  distance_meters?: number;
  display_name?: string;
  battery_level?: number;
}

export async function handleEscalationTick(req: Request, _auth: AuthResult): Promise<Response> {
  // This function is service-role-only (enforced by server.ts route config)
  const body: EscalationRequest = await req.json();
  const { request_id, receiver_id, family_id, escalation_step, owner_id } = body;

  // Handle geofence alert — send urgent push to family owner
  if (body.type === "geofence_alert") {
    const { data: family } = await supabaseAdmin
      .from("families")
      .select("owner_id")
      .eq("id", family_id)
      .single();

    if (family?.owner_id) {
      const { data: ownerTokens } = await supabaseAdmin
        .from("push_tokens")
        .select("token, platform")
        .eq("user_id", family.owner_id)
        .eq("is_active", true);

      if (ownerTokens?.length) {
        const displayName = sanitizeDisplayName(body.display_name || "A family member");
        const distance = body.distance_meters ? Math.round(body.distance_meters) : "unknown";
        const alertTitle = "Location Alert";
        const alertBody = `${displayName} may have left their safe zone (${distance}m from home).`;
        const payload = {
          aps: {
            alert: { title: alertTitle, body: alertBody },
            sound: "urgent.caf",
            "interruption-level": "critical" as const,
            "thread-id": `geofence-${family_id}`,
          },
          type: "geofence_alert",
          receiver_id,
        };

        const results = await sendByPlatform(
          ownerTokens, payload, alertTitle, alertBody,
          { type: "geofence_alert", receiver_id },
          { priority: 10 },
        );
        await deactivateInvalidTokens(ownerTokens, results, family.owner_id);
      }
    }

    return new Response(
      JSON.stringify({ success: true, type: "geofence_alert" }),
      { headers: { "Content-Type": "application/json" } }
    );
  }

  // Handle low battery alert — notify owner their receiver's phone is dying
  if (body.type === "low_battery_alert") {
    const targetOwnerId = body.owner_id || owner_id;
    if (targetOwnerId) {
      const { data: ownerTokens } = await supabaseAdmin
        .from("push_tokens")
        .select("token, platform")
        .eq("user_id", targetOwnerId)
        .eq("is_active", true);

      if (ownerTokens?.length) {
        const displayName = sanitizeDisplayName(body.display_name || "A family member");
        const batteryPct = body.battery_level != null ? Math.round(body.battery_level * 100) : "low";
        const alertTitle = "Low Battery Warning";
        const alertBody = `${displayName}'s phone battery is at ${batteryPct}%. If they miss their check-in, their phone may be off.`;
        const payload = {
          aps: {
            alert: { title: alertTitle, body: alertBody },
            sound: "default",
            "interruption-level": "time-sensitive" as const,
            "thread-id": `battery-${family_id}`,
          },
          type: "low_battery_alert",
          receiver_id,
        };

        const results = await sendByPlatform(
          ownerTokens, payload, alertTitle, alertBody,
          { type: "low_battery_alert", receiver_id },
          { priority: 10 },
        );
        await deactivateInvalidTokens(ownerTokens, results, targetOwnerId);
      }
    }

    return new Response(
      JSON.stringify({ success: true, type: "low_battery_alert" }),
      { headers: { "Content-Type": "application/json" } }
    );
  }

  if (escalation_step != null && escalation_step <= 1) {
    // Step 1: Second reminder to receiver
    const { data: receiverTokens } = await supabaseAdmin
      .from("push_tokens")
      .select("token, platform")
      .eq("user_id", receiver_id)
      .eq("is_active", true);

    if (receiverTokens?.length) {
      const apnsPayload = buildCheckinPayload("", request_id, "escalation", escalation_step);
      const fcmPayload = buildFCMCheckinPayload("", request_id || "", receiver_id, "escalation", escalation_step);
      const results = await Promise.all(
        receiverTokens.map((t: PushToken) => {
          if (t.platform === "android") {
            return sendFCMNotification(t.token, fcmPayload);
          }
          return sendPushNotification(t.token, apnsPayload, { priority: 10 });
        })
      );
      await deactivateInvalidTokens(receiverTokens, results, receiver_id);
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
      .select("token, platform")
      .eq("user_id", owner_id)
      .eq("is_active", true);

    const { data: receiver } = await supabaseAdmin
      .from("users")
      .select("display_name")
      .eq("id", receiver_id)
      .single();

    if (ownerTokens?.length) {
      const alertTitle = "Missed Check-In";
      const safeReceiverName = sanitizeDisplayName(receiver?.display_name || "Your family member");
      const alertBody = `${safeReceiverName} hasn't checked in yet. They've been reminded twice.`;
      const payload = {
        aps: {
          alert: { title: alertTitle, body: alertBody },
          sound: "urgent.caf",
          "interruption-level": "time-sensitive" as const,
          "thread-id": `alert-${request_id}`,
        },
        checkin_request_id: request_id,
        type: "owner_alert",
      };

      const results = await sendByPlatform(
        ownerTokens, payload, alertTitle, alertBody,
        { checkin_request_id: request_id || "", type: "owner_alert", receiver_id },
        { priority: 10 },
      );
      await deactivateInvalidTokens(ownerTokens, results, owner_id!);
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
        safeReceiverName,
        "owner_alert"
      );
      logInfo("Sending owner escalation SMS", { path: "/escalation-tick", userId: owner_id });
      const smsResult = await sendSMS(ownerUser.phone, smsBody);
      if (!smsResult.success) {
        logError("Owner escalation SMS failed", smsResult.error, { path: "/escalation-tick", userId: owner_id });
        await supabaseAdmin.from("notification_log").insert({
          user_id: owner_id,
          checkin_request_id: request_id,
          type: "owner_alert",
          status: "failed",
          error_message: smsResult.error || "SMS send failed",
        });
      }
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
          .select("token, platform")
          .eq("user_id", viewer.user_id)
          .eq("is_active", true);

        if (viewerTokens?.length) {
          const alertTitle = "Family Alert";
          const safeViewerReceiverName = sanitizeDisplayName(receiver?.display_name || "A family member");
          const alertBody = `${safeViewerReceiverName} has missed their check-in today.`;
          const payload = {
            aps: {
              alert: { title: alertTitle, body: alertBody },
              sound: "default",
              "interruption-level": "active" as const,
            },
            checkin_request_id: request_id,
            type: "viewer_alert",
          };

          const results = await sendByPlatform(
            viewerTokens, payload, alertTitle, alertBody,
            { checkin_request_id: request_id || "", type: "viewer_alert", receiver_id },
          );
          await deactivateInvalidTokens(viewerTokens, results, viewer.user_id);
        }

        // SMS fallback for viewers with phone numbers
        const { data: viewerUser } = await supabaseAdmin
          .from("users")
          .select("phone")
          .eq("id", viewer.user_id)
          .single();

        if (viewerUser?.phone) {
          const smsBody = buildEscalationSMS(
            safeViewerReceiverName,
            "viewer_alert"
          );
          logInfo("Sending viewer escalation SMS", { path: "/escalation-tick", userId: viewer.user_id });
          const smsResult = await sendSMS(viewerUser.phone, smsBody);
          if (!smsResult.success) {
            logError("Viewer escalation SMS failed", smsResult.error, { path: "/escalation-tick", userId: viewer.user_id });
            await supabaseAdmin.from("notification_log").insert({
              user_id: viewer.user_id,
              checkin_request_id: request_id,
              type: "viewer_alert",
              status: "failed",
              error_message: smsResult.error || "SMS send failed",
            });
          }
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
