import { supabaseAdmin } from "../../shared/supabase.ts";
import { sendPushNotification, buildCheckinPayload } from "../../shared/apns.ts";
import type { APNsPayload } from "../../shared/apns.ts";
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
  // APNsPayload, not Record<string, unknown>: the wider type let a payload with
  // a bad `aps` shape through this helper and only failed at the sendPushNotification
  // call inside it (US-EDGE002). Typing the parameter means a malformed alert is
  // caught at the caller that built it.
  apnsPayload: APNsPayload,
  fcmTitle: string,
  fcmBody: string,
  fcmData: Record<string, string>,
  apnsOptions?: { priority?: number; collapseId?: string },
): Promise<{ success: boolean; statusCode: number; reason?: string }[]> {
  // `return await` rather than dropping async — see shared/ai.ts for why.
  return await Promise.all(
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
            // LOCATION_ALERT has been registered by the app all along, with a
            // "View Details" action, and nothing ever sent it.
            category: "LOCATION_ALERT",
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
            category: "LOCATION_ALERT",
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
      // Carry the window this reminder is chasing, so a receiver who answers it
      // while offline queues against the right slot instead of day-level
      // (US-IOS138). A failed lookup is not worth failing the reminder over —
      // null just means day-level, which is what happened before this existed.
      let slotKey: string | null = null;
      if (request_id) {
        const { data: requestRow } = await supabaseAdmin
          .from("checkin_requests")
          .select("slot_key")
          .eq("id", request_id)
          .single();
        slotKey = (requestRow?.slot_key as string | null | undefined) ?? null;
      }

      // A check-in reminder is only actionable if it carries the request it is
      // about: the app keys its notification actions off checkin_request_id and
      // silently ignores a payload without one. Sending it anyway produces a
      // notification whose buttons do nothing, which is worse than not sending —
      // the receiver believes they answered. So skip and say why.
      if (!request_id) {
        logWarn("Skipping step-1 reminder with no request_id", {
          path: "/escalation-tick",
          userId: receiver_id,
        });
      } else {
        const apnsPayload = buildCheckinPayload("", request_id, "escalation", escalation_step, undefined, slotKey);
        const fcmPayload = buildFCMCheckinPayload("", request_id, receiver_id, "escalation", escalation_step, undefined, slotKey);
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

    // Declared here, not inside the push block below. The SMS fallback further
    // down is a SIBLING block, not a nested one, so a const declared in the push
    // block is out of scope there — `deno run` strips types without checking, so
    // this reached production as a ReferenceError that killed the escalation SMS
    // the moment an owner had SMS enabled and a phone on file (US-EDGE001).
    const safeReceiverName = sanitizeDisplayName(receiver?.display_name || "Your family member");

    if (ownerTokens?.length) {
      const alertTitle = "Missed Check-In";
      const alertBody = `${safeReceiverName} hasn't checked in yet. They've been reminded twice.`;
      const payload = {
        aps: {
          alert: { title: alertTitle, body: alertBody },
          sound: "urgent.caf",
          "interruption-level": "time-sensitive" as const,
          "thread-id": `alert-${request_id}`,
          // Without a category iOS renders this with NO action buttons, so the
          // one notification the owner most needs to act on — their relative
          // has missed a check-in — offered nothing but "open the app and go
          // find them". URGENT_ALERT is registered by the app and carries
          // "Call Now".
          category: "URGENT_ALERT",
        },
        checkin_request_id: request_id,
        // "Call Now" looks the number up by receiver_id. The FCM data below has
        // always carried it; the APNs payload did not, so the action would have
        // been dead on iOS even once the category was attached.
        receiver_id,
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
  } else if (escalation_step != null && escalation_step >= 3) {
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

    // Same scoping bug as the owner path above, and worse: the viewer SMS branch
    // has no sms_escalation_enabled gate, so it fired for ANY viewer with a phone
    // number on file (US-EDGE001).
    const safeViewerReceiverName = sanitizeDisplayName(receiver?.display_name || "A family member");

    if (viewers?.length) {
      for (const viewer of viewers) {
        const { data: viewerTokens } = await supabaseAdmin
          .from("push_tokens")
          .select("token, platform")
          .eq("user_id", viewer.user_id)
          .eq("is_active", true);

        if (viewerTokens?.length) {
          const alertTitle = "Family Alert";
          const alertBody = `${safeViewerReceiverName} has missed their check-in today.`;
          const payload = {
            aps: {
              alert: { title: alertTitle, body: alertBody },
              sound: "default",
              "interruption-level": "active" as const,
              // A viewer cannot stand an escalation down, so this gets the
              // read-only category rather than URGENT_ALERT's "Call Now".
              category: "LOCATION_ALERT",
              "thread-id": `alert-${request_id}`,
            },
            checkin_request_id: request_id,
            receiver_id,
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
