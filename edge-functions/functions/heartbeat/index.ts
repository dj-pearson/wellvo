import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";

interface HeartbeatRequest {
  battery_level?: number;
  app_version?: string;
}

/**
 * Lightweight endpoint called periodically by the iOS app to report
 * that the app/device is active. Updates last_seen_at and optionally
 * battery level and app version.
 */
export async function handleHeartbeat(req: Request, auth: AuthResult): Promise<Response> {
  if (!auth.userId) {
    return new Response(
      JSON.stringify({ error: "Authentication required" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  const body: HeartbeatRequest = await req.json();

  const updates: Record<string, unknown> = {
    last_seen_at: new Date().toISOString(),
  };

  if (body.battery_level != null) {
    updates.last_battery_level = body.battery_level;
  }

  if (body.app_version) {
    updates.last_app_version = body.app_version;
  }

  const { error } = await supabaseAdmin
    .from("users")
    .update(updates)
    .eq("id", auth.userId);

  if (error) {
    return new Response(
      JSON.stringify({ error: "Failed to update heartbeat" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ success: true }),
    { headers: { "Content-Type": "application/json" } }
  );
}
