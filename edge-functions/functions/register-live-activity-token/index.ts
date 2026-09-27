import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";
import { isValidUUID } from "../../shared/validation.ts";

/**
 * Register (or deactivate) an ActivityKit push token for an escalation Live
 * Activity (US-IOS127) — the owner's, or a co-caregiver's.
 *
 * The app calls this when an activity vends/refreshes a push token, and again
 * with `active: false` when the activity ends locally. The token is stored in
 * `live_activity_push_tokens` so the escalation-resolve paths
 * (process-checkin-response, cancel-escalation) can end the activity via an APNs
 * liveactivity push when the owner's app is closed.
 *
 * Token kinds (CLAUDE.md §D — does NOT touch the push_tokens platform contract):
 *   * token_type 'update' — per-activity token, scoped to a receiver+family.
 *   * token_type 'start'  — owner-scoped push-to-start token (stored for a
 *                           future server-initiated start; not consumed yet).
 */
interface RegisterRequest {
  push_token?: string;
  receiver_id?: string;
  family_id?: string;
  token_type?: "update" | "start";
  active?: boolean;
}

// ActivityKit push tokens are hex strings; bound the length defensively.
function isValidPushToken(token: string): boolean {
  return /^[0-9a-fA-F]+$/.test(token) && token.length >= 32 && token.length <= 400;
}

export async function handleRegisterLiveActivityToken(
  req: Request,
  auth: AuthResult
): Promise<Response> {
  if (!auth.userId) {
    return new Response(
      JSON.stringify({ error: "Authentication required" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }
  const ownerId = auth.userId.toLowerCase();

  const body: RegisterRequest = await req.json();
  const pushToken = body.push_token?.trim();
  const tokenType = body.token_type === "start" ? "start" : "update";
  const active = body.active !== false; // default true

  if (!pushToken || !isValidPushToken(pushToken)) {
    return new Response(
      JSON.stringify({ error: "Valid push_token is required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Deactivation only needs the token; scope it to the caller so one owner
  // cannot deactivate another's registration.
  if (!active) {
    const { error } = await supabaseAdmin
      .from("live_activity_push_tokens")
      .update({ is_active: false })
      .eq("push_token", pushToken)
      .eq("owner_id", ownerId);

    if (error) {
      return new Response(
        JSON.stringify({ error: "Failed to deactivate token" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
    return new Response(
      JSON.stringify({ success: true }),
      { headers: { "Content-Type": "application/json" } }
    );
  }

  let receiverId: string | null = null;
  let familyId: string | null = null;

  if (tokenType === "update") {
    receiverId = body.receiver_id?.toLowerCase() ?? null;
    familyId = body.family_id?.toLowerCase() ?? null;
    if (!receiverId || !isValidUUID(receiverId) || !familyId || !isValidUUID(familyId)) {
      return new Response(
        JSON.stringify({ error: "receiver_id and family_id are required for update tokens" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // AUTHORIZATION: the family owner, or an active co-caregiver of this
    // family. Co-caregivers get the escalation Live Activity too; refusing
    // their token (as this did) meant a resolved escalation left their Lock
    // Screen counting "Overdue" until they next opened the app. The token is
    // stored under the caller's own id and is only ever used to END an
    // activity, so this widens nothing else (CLAUDE.md §B: looser auth,
    // intentional).
    const { data: family } = await supabaseAdmin
      .from("families")
      .select("owner_id")
      .eq("id", familyId)
      .single();

    let allowed = !!family && family.owner_id.toLowerCase() === ownerId;
    if (family && !allowed) {
      const { data: membership } = await supabaseAdmin
        .from("family_members")
        .select("id")
        .eq("family_id", familyId)
        .eq("user_id", ownerId)
        .eq("role", "viewer")
        .eq("status", "active")
        .limit(1);
      allowed = (membership?.length ?? 0) > 0;
    }

    if (!allowed) {
      return new Response(
        JSON.stringify({ error: "Only the family owner or a co-caregiver can register an activity token" }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // Upsert on the globally-unique push_token. Re-registration re-homes the token
  // to the current owner/receiver/family and reactivates it.
  const { error } = await supabaseAdmin
    .from("live_activity_push_tokens")
    .upsert(
      {
        owner_id: ownerId,
        receiver_id: receiverId,
        family_id: familyId,
        push_token: pushToken,
        token_type: tokenType,
        is_active: true,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "push_token" }
    );

  if (error) {
    return new Response(
      JSON.stringify({ error: "Failed to register token" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ success: true }),
    { headers: { "Content-Type": "application/json" } }
  );
}
