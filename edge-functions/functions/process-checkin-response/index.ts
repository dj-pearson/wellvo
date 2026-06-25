import { supabaseAdmin } from "../../shared/supabase.ts";
import { sendPushNotification } from "../../shared/apns.ts";
import { sendFCMNotification, buildFCMAlertPayload } from "../../shared/fcm.ts";
import type { AuthResult } from "../../shared/auth.ts";
import { isValidUUID, validateLocationFields, sanitizeDisplayName, truncateString, coerceNumericFields } from "../../shared/validation.ts";

/**
 * Returns UTC ISO timestamps for the start and end of "today" in the given
 * IANA timezone. The apps compute `todayCheckInStatus` using the device's
 * local calendar day (`Calendar.current.startOfDay`), so the server-side
 * dedup must use the same local day — otherwise a late-evening check-in
 * (e.g. 23:51 local = 03:51 next-day UTC) gets treated as "today" by the
 * server but "yesterday" by the dashboard, producing a permanent Pending.
 */
function localDayBoundsUTC(tz: string): { startUTC: string; endUTC: string } {
  const now = new Date();
  const ymd = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric", month: "2-digit", day: "2-digit",
  }).format(now);
  const hms = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false,
  }).format(now);
  const localAsUTC = Date.parse(`${ymd}T${hms}Z`);
  const offsetMs = now.getTime() - localAsUTC;
  const localMidnightUTC = Date.parse(`${ymd}T00:00:00Z`) + offsetMs;
  return {
    startUTC: new Date(localMidnightUTC).toISOString(),
    endUTC: new Date(localMidnightUTC + 86_400_000).toISOString(),
  };
}

function haversineDistance(
  lat1: number, lon1: number,
  lat2: number, lon2: number
): number {
  const R = 6371000;
  const toRad = (deg: number) => deg * (Math.PI / 180);
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

interface ProcessCheckinRequest {
  checkin_request_id?: string;
  receiver_id?: string;
  family_id?: string;
  source?: string;
  response_type?: "ok" | "need_help" | "call_me";
  latitude?: number;
  longitude?: number;
  location_accuracy_meters?: number;
  battery_level?: number;
  location_label?: string;
  kid_response_type?: string;
  slot_key?: string;
}

export async function handleProcessCheckinResponse(req: Request, auth: AuthResult): Promise<Response> {
  const body: ProcessCheckinRequest = await req.json();
  // Defensive: accept numeric fields whether sent as numbers (current clients)
  // or quoted strings (pre-US-IOS078 builds still in the wild).
  coerceNumericFields(body as Record<string, unknown>,
    ["latitude", "longitude", "location_accuracy_meters", "battery_level"]);

  let requestId = body.checkin_request_id;
  let receiverId = body.receiver_id;
  let familyId = body.family_id;
  const source = body.source || "app";
  const responseType = body.response_type || "ok";

  // Validate UUID formats
  if (requestId && !isValidUUID(requestId)) {
    return new Response(
      JSON.stringify({ error: "Invalid checkin_request_id format" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }
  if (receiverId && !isValidUUID(receiverId)) {
    return new Response(
      JSON.stringify({ error: "Invalid receiver_id format" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }
  if (familyId && !isValidUUID(familyId)) {
    return new Response(
      JSON.stringify({ error: "Invalid family_id format" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Validate location and battery fields
  const locationError = validateLocationFields(body);
  if (locationError) {
    return new Response(
      JSON.stringify({ error: locationError }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Truncate string fields
  if (body.location_label) body.location_label = truncateString(body.location_label, 500);
  // slot_key identifies which scheduled window this check-in satisfies so a
  // receiver with multiple windows/day (US-IOS048) doesn't collapse to one row.
  // Keep it short and stable (e.g. "08:00"); absent = legacy day-level check-in.
  const slotKey = body.slot_key ? truncateString(body.slot_key, 20) : null;

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

  // Normalize UUIDs to lowercase — clients (e.g. Swift's UUID.uuidString) may send uppercase
  receiverId = receiverId?.toLowerCase();
  familyId = familyId?.toLowerCase();

  // AUTHORIZATION: Verify the authenticated user IS the receiver
  // Service role calls (from notification actions) are trusted
  if (!auth.isServiceRole) {
    if (!auth.userId || auth.userId.toLowerCase() !== receiverId) {
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

  // Check for existing check-in today in the receiver's local calendar day.
  // Must match the client-side window (`Calendar.current.startOfDay`) so a
  // late-evening-local check-in isn't deduped against the dashboard's
  // next-local-day query.
  const { data: receiverUser } = await supabaseAdmin
    .from("users")
    .select("timezone")
    .eq("id", receiverId)
    .single();
  const receiverTz = receiverUser?.timezone || "UTC";
  const { startUTC, endUTC } = localDayBoundsUTC(receiverTz);
  // Dedup within the receiver's local day. When a slot_key is supplied, dedup
  // per slot so multiple windows/day stay distinct; otherwise fall back to the
  // legacy day-level dedup. `order + limit(1)` (instead of maybeSingle over the
  // whole day) is required now that a day can legitimately hold multiple rows.
  let existingQuery = supabaseAdmin
    .from("checkins")
    .select()
    .eq("receiver_id", receiverId)
    .eq("family_id", familyId)
    .gte("checked_in_at", startUTC)
    .lt("checked_in_at", endUTC);
  if (slotKey !== null) {
    existingQuery = existingQuery.eq("slot_key", slotKey);
  }
  const { data: existingCheckIn } = await existingQuery
    .order("checked_in_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existingCheckIn) {
    // Already checked in today — return existing check-in (not an error)
    // Still mark pending requests as checked_in below
    return markRequestsAndRespond(receiverId, familyId, existingCheckIn);
  }

  // Calculate distance from home if location is provided
  let distanceFromHome: number | null = null;
  if (body.latitude != null && body.longitude != null) {
    const { data: settings } = await supabaseAdmin
      .from("receiver_settings")
      .select("home_latitude, home_longitude, location_tracking_enabled")
      .eq("family_member_id", membership.id)
      .single();

    if (settings?.location_tracking_enabled && settings.home_latitude != null && settings.home_longitude != null) {
      distanceFromHome = haversineDistance(
        body.latitude, body.longitude,
        settings.home_latitude, settings.home_longitude
      );
    }
  }

  // Record the check-in with location and response type
  const insertData: Record<string, unknown> = {
    receiver_id: receiverId,
    family_id: familyId,
    source,
    response_type: responseType,
  };

  if (body.latitude != null) insertData.latitude = body.latitude;
  if (body.longitude != null) insertData.longitude = body.longitude;
  if (body.location_accuracy_meters != null) insertData.location_accuracy_meters = body.location_accuracy_meters;
  if (distanceFromHome != null) insertData.distance_from_home_meters = Math.round(distanceFromHome);
  if (body.location_label != null) insertData.location_label = body.location_label;
  if (body.kid_response_type != null) insertData.kid_response_type = body.kid_response_type;
  if (slotKey !== null) insertData.slot_key = slotKey;

  const { data: checkIn, error: checkInError } = await supabaseAdmin
    .from("checkins")
    .insert(insertData)
    .select()
    .single();

  if (checkInError) {
    return new Response(
      JSON.stringify({ error: "Failed to record check-in" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // Update battery level on user profile if provided
  if (body.battery_level != null) {
    await supabaseAdmin
      .from("users")
      .update({ last_battery_level: body.battery_level, last_seen_at: new Date().toISOString() })
      .eq("id", receiverId);
  }

  // Treat kid SOS the same as need_help for escalation purposes
  const isUrgent = responseType === "need_help" || responseType === "call_me" || body.kid_response_type === "sos";
  const isKidInfoResponse = body.kid_response_type === "picking_me_up" || body.kid_response_type === "can_stay_longer";

  // Handle urgent response types — create alerts and notify owner immediately
  if (isUrgent || isKidInfoResponse) {
    const { data: family } = await supabaseAdmin
      .from("families")
      .select("owner_id")
      .eq("id", familyId)
      .single();

    const { data: receiver } = await supabaseAdmin
      .from("users")
      .select("display_name")
      .eq("id", receiverId)
      .single();

    const displayName = sanitizeDisplayName(receiver?.display_name || "A family member");

    if (isUrgent) {
      const effectiveType = body.kid_response_type === "sos" ? "need_help" : responseType;
      const alertTitle = effectiveType === "need_help" ? "Help Requested" : "Call Requested";
      const alertMessage = effectiveType === "need_help"
        ? `${displayName} checked in but indicated they need help.`
        : `${displayName} checked in and is asking you to call them.`;

      // Create urgent alert
      await supabaseAdmin.from("alerts").insert({
        family_id: familyId,
        receiver_id: receiverId,
        type: effectiveType,
        title: alertTitle,
        message: alertMessage,
        data: {
          checkin_id: checkIn.id,
          latitude: body.latitude,
          longitude: body.longitude,
          distance_from_home_meters: distanceFromHome != null ? Math.round(distanceFromHome) : null,
          kid_response_type: body.kid_response_type,
        },
      });

      // Send urgent push to owner
      if (family?.owner_id) {
        const { data: ownerTokens } = await supabaseAdmin
          .from("push_tokens")
          .select("token, platform")
          .eq("user_id", family.owner_id)
          .eq("is_active", true);

        if (ownerTokens?.length) {
          const urgentPayload = {
            aps: {
              alert: { title: alertTitle, body: alertMessage },
              sound: "urgent.caf",
              category: "URGENT_ALERT",
              "interruption-level": "critical" as const,
              "thread-id": `urgent-${familyId}`,
            },
            checkin_id: checkIn.id,
            receiver_id: receiverId,
            type: effectiveType,
          };

          const fcmData: Record<string, string> = {
            checkin_id: String(checkIn.id),
            receiver_id: receiverId!,
            type: effectiveType,
            notification_type: "urgent_alert",
          };

          const results = await Promise.all(
            ownerTokens.map((t: { token: string; platform: string }) => {
              if (t.platform === "android") {
                return sendFCMNotification(t.token, buildFCMAlertPayload(alertTitle, alertMessage, fcmData));
              }
              return sendPushNotification(t.token, urgentPayload, { priority: 10 });
            })
          );

          for (let i = 0; i < results.length; i++) {
            const isInvalid =
              results[i].statusCode === 410 ||
              results[i].reason === "NOT_FOUND" ||
              results[i].reason === "UNREGISTERED";
            if (isInvalid) {
              await supabaseAdmin
                .from("push_tokens")
                .update({ is_active: false })
                .eq("token", ownerTokens[i].token);
              console.log(`Deactivated invalid ${ownerTokens[i].platform} token for user ${family.owner_id}`);
            }
          }
        }
      }
    } else if (isKidInfoResponse) {
      // Non-urgent kid responses — notify owner so they see it in their dashboard
      const kidLabel = body.kid_response_type === "picking_me_up" ? "Pickup Requested" : "Wants to Stay Longer";
      const kidMessage = body.kid_response_type === "picking_me_up"
        ? `${displayName} is asking to be picked up.`
        : `${displayName} is asking if they can stay longer.`;

      // Create non-urgent alert for owner dashboard
      await supabaseAdmin.from("alerts").insert({
        family_id: familyId,
        receiver_id: receiverId,
        type: body.kid_response_type,
        title: kidLabel,
        message: kidMessage,
        data: {
          checkin_id: checkIn.id,
          latitude: body.latitude,
          longitude: body.longitude,
          location_label: body.location_label,
          kid_response_type: body.kid_response_type,
        },
      });

      // Send non-urgent push to owner
      if (family?.owner_id) {
        const { data: ownerTokens } = await supabaseAdmin
          .from("push_tokens")
          .select("token, platform")
          .eq("user_id", family.owner_id)
          .eq("is_active", true);

        if (ownerTokens?.length) {
          const infoPayload = {
            aps: {
              alert: { title: kidLabel, body: kidMessage },
              sound: "default",
              category: "KID_RESPONSE",
              "thread-id": `kid-${familyId}`,
              "interruption-level": "active" as const,
            },
            checkin_id: checkIn.id,
            receiver_id: receiverId,
            type: body.kid_response_type,
          };

          const fcmData: Record<string, string> = {
            checkin_id: String(checkIn.id),
            receiver_id: receiverId!,
            type: body.kid_response_type || "",
            notification_type: "kid_response",
          };

          const results = await Promise.all(
            ownerTokens.map((t: { token: string; platform: string }) => {
              if (t.platform === "android") {
                return sendFCMNotification(t.token, buildFCMAlertPayload(kidLabel, kidMessage, fcmData));
              }
              return sendPushNotification(t.token, infoPayload, { priority: 5 });
            })
          );

          for (let i = 0; i < results.length; i++) {
            const isInvalid =
              results[i].statusCode === 410 ||
              results[i].reason === "NOT_FOUND" ||
              results[i].reason === "UNREGISTERED";
            if (isInvalid) {
              await supabaseAdmin
                .from("push_tokens")
                .update({ is_active: false })
                .eq("token", ownerTokens[i].token);
              console.log(`Deactivated invalid ${ownerTokens[i].platform} token for user ${family.owner_id}`);
            }
          }
        }
      }
    }
  } else {
    // Routine "I'm OK" — send the owner a confirmation push so they get peace of
    // mind even when the app is closed (the realtime dashboard only updates a
    // foregrounded app). Opt-in via receiver_settings.notify_owner_on_checkin,
    // which defaults to TRUE.
    const { data: settings } = await supabaseAdmin
      .from("receiver_settings")
      .select("notify_owner_on_checkin")
      .eq("family_member_id", membership.id)
      .single();

    // Treat a missing setting/row as opted-in (default on) so existing families
    // start receiving confirmations without having to re-save their settings.
    if (settings?.notify_owner_on_checkin !== false) {
      const { data: family } = await supabaseAdmin
        .from("families")
        .select("owner_id")
        .eq("id", familyId)
        .single();

      if (family?.owner_id) {
        const { data: receiver } = await supabaseAdmin
          .from("users")
          .select("display_name")
          .eq("id", receiverId)
          .single();

        const displayName = sanitizeDisplayName(receiver?.display_name || "A family member");
        const checkedInLocal = new Intl.DateTimeFormat("en-US", {
          timeZone: receiverTz,
          hour: "numeric",
          minute: "2-digit",
        }).format(new Date(checkIn.checked_in_at as string));
        const okTitle = "Checked in ✓";
        const okMessage = `${displayName} checked in at ${checkedInLocal}.`;

        const { data: ownerTokens } = await supabaseAdmin
          .from("push_tokens")
          .select("token, platform")
          .eq("user_id", family.owner_id)
          .eq("is_active", true);

        if (ownerTokens?.length) {
          const okPayload = {
            aps: {
              alert: { title: okTitle, body: okMessage },
              sound: "default",
              category: "CHECKIN_CONFIRMED",
              "thread-id": `checkin-${familyId}`,
              "interruption-level": "active" as const,
            },
            checkin_id: checkIn.id,
            receiver_id: receiverId,
            type: "checkin_confirmed",
          };

          const fcmData: Record<string, string> = {
            checkin_id: String(checkIn.id),
            receiver_id: receiverId!,
            type: "checkin_confirmed",
            notification_type: "checkin_confirmed",
          };

          const results = await Promise.all(
            ownerTokens.map((t: { token: string; platform: string }) => {
              if (t.platform === "android") {
                return sendFCMNotification(t.token, buildFCMAlertPayload(okTitle, okMessage, fcmData));
              }
              return sendPushNotification(t.token, okPayload, { priority: 5 });
            })
          );

          for (let i = 0; i < results.length; i++) {
            const isInvalid =
              results[i].statusCode === 410 ||
              results[i].reason === "NOT_FOUND" ||
              results[i].reason === "UNREGISTERED";
            if (isInvalid) {
              await supabaseAdmin
                .from("push_tokens")
                .update({ is_active: false })
                .eq("token", ownerTokens[i].token);
              console.log(`Deactivated invalid ${ownerTokens[i].platform} token for user ${family.owner_id}`);
            }
          }
        }
      }
    }
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
