import { supabaseAdmin } from "../../shared/supabase.ts";
import { sendPushNotification, buildCheckinPayload } from "../../shared/apns.ts";
import type { APNsPayload } from "../../shared/apns.ts";
import { sendFCMNotification, buildFCMCheckinPayload, buildFCMAlertPayload } from "../../shared/fcm.ts";
import { sendSMS, buildEscalationSMS } from "../../shared/sms.ts";
import { logInfo, logWarn, logError } from "../../shared/logger.ts";
import type { AuthResult } from "../../shared/auth.ts";
import { isValidTimezone, sanitizeDisplayName } from "../../shared/validation.ts";
import { formatOccurredAt } from "../../shared/checkin-time.ts";
import { escalationCollapseId, viewerMissedAlertCopy } from "../../shared/caregiver-alerts.ts";

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

  // Handle geofence alert — urgent push to the family owner AND every active
  // co-caregiver. It used to reach the owner only: when a child left the safe
  // zone or a parent with dementia wandered, the co-parent or sibling nearest
  // to them heard nothing (help requests already page every caregiver).
  if (body.type === "geofence_alert") {
    const { data: family } = await supabaseAdmin
      .from("families")
      .select("owner_id")
      .eq("id", family_id)
      .single();

    const recipients: string[] = [];
    if (family?.owner_id) recipients.push(family.owner_id as string);
    const { data: geoViewers } = await supabaseAdmin
      .from("family_members")
      .select("user_id")
      .eq("family_id", family_id)
      .eq("role", "viewer")
      .eq("status", "active");
    for (const v of geoViewers ?? []) {
      const id = v.user_id as string | null;
      if (id && id !== receiver_id && !recipients.includes(id)) recipients.push(id);
    }

    if (recipients.length) {
      const { data: tokens } = await supabaseAdmin
        .from("push_tokens")
        .select("token, platform")
        .in("user_id", recipients)
        .eq("is_active", true);

      if (tokens?.length) {
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
            // "Call Now" (looks the number up from receiver_id) is what a
            // caregiver needs when someone has wandered off; the body tap
            // opens the dashboard.
            category: "URGENT_ALERT",
          },
          type: "geofence_alert",
          receiver_id,
        };

        const results = await sendByPlatform(
          tokens, payload, alertTitle, alertBody,
          { type: "geofence_alert", receiver_id },
          { priority: 10 },
        );
        await deactivateInvalidTokens(tokens, results, family?.owner_id ?? family_id);
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

  // pg_cron advanced this step and POSTed here; the receiver may have checked
  // in during that gap. Alerting now would tell the owner someone missed a
  // check-in they had just made.
  if (request_id && escalation_step != null) {
    const { data: current } = await supabaseAdmin
      .from("checkin_requests")
      .select("status")
      .eq("id", request_id)
      .maybeSingle();
    if (current && current.status !== "pending") {
      return new Response(
        JSON.stringify({ success: true, skipped: "request_not_pending", escalation_step }),
        { headers: { "Content-Type": "application/json" } }
      );
    }
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

    let delivered = false;
    const failures: string[] = [];

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
      if (results.some((r) => r.success)) {
        delivered = true;
      } else {
        failures.push(`push failed on ${results.length} device(s)`);
      }
    } else {
      failures.push("no active push tokens");
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
      if (smsResult.success) {
        delivered = true;
      } else {
        logError("Owner escalation SMS failed", smsResult.error, { path: "/escalation-tick", userId: owner_id });
        failures.push(`SMS failed: ${smsResult.error || "unknown error"}`);
      }
    }

    // One row with the real outcome. It used to log "sent" unconditionally, so
    // an owner with no push token and SMS off — who was told nothing — looked
    // alerted in every report.
    if (!delivered) {
      logError("Owner missed-check-in alert reached no device", null, {
        path: "/escalation-tick",
        userId: owner_id,
      });
    }
    await supabaseAdmin.from("notification_log").insert({
      user_id: owner_id,
      checkin_request_id: request_id,
      type: "owner_alert",
      status: delivered ? "sent" : "failed",
      error_message: delivered ? null : failures.join("; ") || "no delivery channel",
    });
  } else if (escalation_step != null && escalation_step >= 3) {
    // Step 3: Alert to all Viewers (co-caregivers)
    const { data: viewers } = await supabaseAdmin
      .from("family_members")
      .select("user_id")
      .eq("family_id", family_id)
      .eq("role", "viewer")
      .eq("status", "active");

    const { data: receiver } = await supabaseAdmin
      .from("users")
      .select("display_name, timezone")
      .eq("id", receiver_id)
      .single();

    // Same scoping bug as the owner path above (US-EDGE001).
    const safeViewerReceiverName = sanitizeDisplayName(receiver?.display_name || "A family member");

    // Context for the page: since when, and that the owner already knows.
    let sinceLocal: string | null = null;
    let claimedByName: string | null = null;
    let claimedById: string | null = null;
    if (request_id) {
      // "*": claimed_by_name only exists from 00062, and naming it would fail
      // the whole read on an older schema.
      const { data: requestRow } = await supabaseAdmin
        .from("checkin_requests")
        .select("*")
        .eq("id", request_id)
        .maybeSingle();
      const tz = receiver?.timezone && isValidTimezone(receiver.timezone) ? receiver.timezone : "UTC";
      if (requestRow?.created_at) sinceLocal = formatOccurredAt(tz, requestRow.created_at as string, false);
      const claimer = requestRow?.claimed_by_name as string | null | undefined;
      if (claimer) claimedByName = sanitizeDisplayName(claimer) || null;
      claimedById = (requestRow?.claimed_by as string | null | undefined) ?? null;
    }
    let ownerName: string | null = null;
    if (owner_id) {
      const { data: ownerUser } = await supabaseAdmin
        .from("users")
        .select("display_name")
        .eq("id", owner_id)
        .maybeSingle();
      ownerName = ownerUser?.display_name ? sanitizeDisplayName(ownerUser.display_name) || null : null;
    }
    const copy = viewerMissedAlertCopy({ receiverName: safeViewerReceiverName, sinceLocal, ownerName, claimedByName });
    // The co-caregiver who said "I'm on it" isn't told that they are.
    const copyForClaimer = viewerMissedAlertCopy({ receiverName: safeViewerReceiverName, sinceLocal, ownerName, claimedByName: null });

    // Viewer SMS follows the same per-receiver opt-in as the owner's. It used to
    // text every viewer with a number on file, whatever the owner had chosen.
    let viewerSmsEnabled = false;
    if (viewers?.length) {
      const { data: receiverMember } = await supabaseAdmin
        .from("family_members")
        .select("id")
        .eq("user_id", receiver_id)
        .eq("family_id", family_id)
        .maybeSingle();
      if (receiverMember) {
        const { data: settings } = await supabaseAdmin
          .from("receiver_settings")
          .select("sms_escalation_enabled")
          .eq("family_member_id", receiverMember.id)
          .maybeSingle();
        viewerSmsEnabled = settings?.sms_escalation_enabled ?? false;
      }
    }

    if (viewers?.length) {
      for (const viewer of viewers) {
        let delivered = false;
        const failures: string[] = [];
        const viewerCopy = claimedById && claimedById === viewer.user_id ? copyForClaimer : copy;

        const { data: viewerTokens } = await supabaseAdmin
          .from("push_tokens")
          .select("token, platform")
          .eq("user_id", viewer.user_id)
          .eq("is_active", true);

        if (viewerTokens?.length) {
          // This is the LAST page — nobody has answered for over an hour — so
          // it is as urgent as the owner's step-2 alert: time-sensitive (gets
          // through Focus, which the app tells co-caregivers to allow for
          // exactly this), the urgent sound, and URGENT_ALERT, whose only
          // action is "Call Now" (receiver_id below) — not a stand-down. It
          // used to be "active" + LOCATION_ALERT ("View Details").
          const payload = {
            aps: {
              alert: { title: viewerCopy.title, body: viewerCopy.body },
              sound: "urgent.caf",
              "interruption-level": "time-sensitive" as const,
              category: "URGENT_ALERT",
              "thread-id": `alert-${request_id}`,
            },
            checkin_request_id: request_id,
            receiver_id,
            type: "viewer_alert",
          };

          const results = await sendByPlatform(
            viewerTokens, payload, viewerCopy.title, viewerCopy.body,
            { checkin_request_id: request_id || "", type: "viewer_alert", receiver_id },
            // Same collapse id as the all-clear (shared/caregiver-alerts.ts),
            // which then replaces this alarm on the Lock Screen.
            { priority: 10, ...(request_id ? { collapseId: escalationCollapseId(request_id) } : {}) },
          );
          await deactivateInvalidTokens(viewerTokens, results, viewer.user_id);
          if (results.some((r) => r.success)) {
            delivered = true;
          } else {
            failures.push(`push failed on ${results.length} device(s)`);
          }
        } else {
          failures.push("no active push tokens");
        }

        // SMS fallback for viewers with phone numbers
        const { data: viewerUser } = await supabaseAdmin
          .from("users")
          .select("phone")
          .eq("id", viewer.user_id)
          .single();

        if (viewerSmsEnabled && viewerUser?.phone) {
          const smsBody = buildEscalationSMS(
            safeViewerReceiverName,
            "viewer_alert"
          );
          logInfo("Sending viewer escalation SMS", { path: "/escalation-tick", userId: viewer.user_id });
          const smsResult = await sendSMS(viewerUser.phone, smsBody);
          if (smsResult.success) {
            delivered = true;
          } else {
            logError("Viewer escalation SMS failed", smsResult.error, { path: "/escalation-tick", userId: viewer.user_id });
            failures.push(`SMS failed: ${smsResult.error || "unknown error"}`);
          }
        }

        // One row per viewer with the real outcome, like the owner path. It
        // used to write "sent" unconditionally (and a second row after a
        // failed SMS), so a co-caregiver with no device looked alerted. The
        // all-clear goes to the co-caregivers logged here.
        await supabaseAdmin.from("notification_log").insert({
          user_id: viewer.user_id,
          checkin_request_id: request_id,
          type: "viewer_alert",
          status: delivered ? "sent" : "failed",
          error_message: delivered ? null : failures.join("; ") || "no delivery channel",
        });
      }
    }
  }

  return new Response(
    JSON.stringify({ success: true, escalation_step }),
    { headers: { "Content-Type": "application/json" } }
  );
}
