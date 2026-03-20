import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";

interface ReportLocationRequest {
  family_id: string;
  latitude: number;
  longitude: number;
  accuracy_meters?: number;
  battery_level?: number;
}

/**
 * Haversine distance between two points in meters.
 */
function haversineDistance(
  lat1: number, lon1: number,
  lat2: number, lon2: number
): number {
  const R = 6371000; // Earth's radius in meters
  const toRad = (deg: number) => deg * (Math.PI / 180);
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * Receiver reports their current location.
 * Calculates distance from home if home coordinates are configured.
 */
export async function handleReportLocation(req: Request, auth: AuthResult): Promise<Response> {
  if (!auth.userId && !auth.isServiceRole) {
    return new Response(
      JSON.stringify({ error: "Authentication required" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  const body: ReportLocationRequest = await req.json();
  const { family_id, latitude, longitude, accuracy_meters, battery_level } = body;

  const receiverId = auth.userId!;

  // Verify receiver is an active member of this family
  const { data: membership } = await supabaseAdmin
    .from("family_members")
    .select("id, role, status")
    .eq("family_id", family_id)
    .eq("user_id", receiverId)
    .eq("status", "active")
    .single();

  if (!membership || membership.role !== "receiver") {
    return new Response(
      JSON.stringify({ error: "Not a receiver in this family" }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  // Check if location tracking is enabled for this receiver
  const { data: settings } = await supabaseAdmin
    .from("receiver_settings")
    .select("location_tracking_enabled, home_latitude, home_longitude, geofence_radius_meters")
    .eq("family_member_id", membership.id)
    .single();

  if (!settings?.location_tracking_enabled) {
    return new Response(
      JSON.stringify({ error: "Location tracking is not enabled" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Calculate distance from home if home is set
  let distanceFromHome: number | null = null;
  if (settings.home_latitude != null && settings.home_longitude != null) {
    distanceFromHome = haversineDistance(
      latitude, longitude,
      settings.home_latitude, settings.home_longitude
    );
  }

  // Insert location update
  const { error: insertError } = await supabaseAdmin
    .from("location_updates")
    .insert({
      receiver_id: receiverId,
      family_id,
      latitude,
      longitude,
      accuracy_meters: accuracy_meters ?? null,
      distance_from_home_meters: distanceFromHome,
      battery_level: battery_level ?? null,
    });

  if (insertError) {
    return new Response(
      JSON.stringify({ error: "Failed to record location" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // Update user's last battery level if provided
  if (battery_level != null) {
    await supabaseAdmin
      .from("users")
      .update({ last_battery_level: battery_level })
      .eq("id", receiverId);
  }

  return new Response(
    JSON.stringify({
      success: true,
      distance_from_home_meters: distanceFromHome != null ? Math.round(distanceFromHome) : null,
      outside_geofence: distanceFromHome != null
        ? distanceFromHome > settings.geofence_radius_meters
        : null,
    }),
    { headers: { "Content-Type": "application/json" } }
  );
}
