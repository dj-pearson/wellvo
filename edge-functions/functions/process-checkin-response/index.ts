import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";

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
}

export async function handleProcessCheckinResponse(req: Request, auth: AuthResult): Promise<Response> {
  const body: ProcessCheckinRequest = await req.json();

  let requestId = body.checkin_request_id;
  let receiverId = body.receiver_id;
  let familyId = body.family_id;
  const source = body.source || "app";
  const responseType = body.response_type || "ok";

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

  // AUTHORIZATION: Verify the authenticated user IS the receiver
  // Service role calls (from notification actions) are trusted
  if (!auth.isServiceRole) {
    if (!auth.userId || auth.userId !== receiverId) {
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

  // Check for existing check-in today (duplicate prevention)
  const today = new Date().toISOString().split("T")[0];
  const { data: existingCheckIn } = await supabaseAdmin
    .from("checkins")
    .select()
    .eq("receiver_id", receiverId)
    .eq("family_id", familyId)
    .gte("checked_in_at", `${today}T00:00:00Z`)
    .lt("checked_in_at", `${today}T23:59:59Z`)
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

  // Handle urgent response types — create alerts and notify owner immediately
  if (responseType === "need_help" || responseType === "call_me") {
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

    const alertTitle = responseType === "need_help" ? "Help Requested" : "Call Requested";
    const alertMessage = responseType === "need_help"
      ? `${receiver?.display_name || "A family member"} checked in but indicated they need help.`
      : `${receiver?.display_name || "A family member"} checked in and is asking you to call them.`;

    // Create urgent alert
    await supabaseAdmin.from("alerts").insert({
      family_id: familyId,
      receiver_id: receiverId,
      type: responseType,
      title: alertTitle,
      message: alertMessage,
      data: {
        checkin_id: checkIn.id,
        latitude: body.latitude,
        longitude: body.longitude,
        distance_from_home_meters: distanceFromHome != null ? Math.round(distanceFromHome) : null,
      },
    });

    // Send urgent push to owner
    if (family?.owner_id) {
      const { sendPushNotification } = await import("../../shared/apns.ts");
      const { data: ownerTokens } = await supabaseAdmin
        .from("push_tokens")
        .select("token")
        .eq("user_id", family.owner_id)
        .eq("is_active", true);

      if (ownerTokens?.length) {
        const urgentPayload = {
          aps: {
            alert: {
              title: alertTitle,
              body: alertMessage,
            },
            sound: "urgent.caf",
            "interruption-level": "critical" as const,
            "thread-id": `urgent-${familyId}`,
          },
          checkin_id: checkIn.id,
          type: responseType,
        };

        await Promise.all(
          ownerTokens.map((t: { token: string }) =>
            sendPushNotification(t.token, urgentPayload, { priority: 10 })
          )
        );
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
