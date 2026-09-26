import { supabaseAdmin } from "./supabase.ts";
import { logError } from "./logger.ts";

/**
 * The outcome of redeeming an invite, from the `redeem_invite` RPC (00054).
 *
 * All three join paths — invite link (invite-receiver accept), phone match
 * (auto-join) and pairing code (redeem-code) — go through this one function so
 * the join is a single transaction: the invite cannot be redeemed twice, the
 * plan's receiver limit is enforced at the moment of joining, and an owner
 * who joins another family keeps their owner role.
 */
export type JoinResult =
  | {
    status: "joined";
    family_id: string;
    member_id: string;
    role: string;
    checkin_time: string | null;
    name: string | null;
    owner_name: string | null;
  }
  | { status: "already_member"; family_id: string; role: string; owner_name: string | null }
  | { status: "limit_reached"; family_id: string }
  | { status: "invalid" }
  | { status: "error" };

export async function redeemInvite(
  inviteId: string,
  userId: string,
  timezone?: string | null,
): Promise<JoinResult> {
  const { data, error } = await supabaseAdmin.rpc("redeem_invite", {
    p_invite_id: inviteId,
    p_user_id: userId,
    p_timezone: timezone ?? null,
  });
  if (error && isMissingFunction(error)) {
    // The edge deploy is not gated on the migration run, so this can be live
    // before 00054 creates redeem_invite. Joining must keep working in that
    // window, so fall back to the pre-00054 step-by-step join.
    return await legacyRedeemInvite(inviteId, userId, timezone);
  }
  if (error || !data) {
    logError("redeem_invite failed", error, { userId });
    return { status: "error" };
  }
  return data as JoinResult;
}

/** PostgREST "function not found" (PGRST202) or Postgres 42883. */
function isMissingFunction(error: { code?: string }): boolean {
  return error.code === "PGRST202" || error.code === "42883";
}

/**
 * The join as it worked before 00054, kept only for the deploy window above.
 * Not atomic and does not re-check the plan limit; remove once 00054 is live.
 */
async function legacyRedeemInvite(
  inviteId: string,
  userId: string,
  timezone?: string | null,
): Promise<JoinResult> {
  const { data: invite } = await supabaseAdmin
    .from("invite_tokens")
    .select("*")
    .eq("id", inviteId)
    .is("used_by", null)
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();
  if (!invite) return { status: "invalid" };

  const { data: existing } = await supabaseAdmin
    .from("family_members")
    .select("id, status, role")
    .eq("family_id", invite.family_id)
    .eq("user_id", userId)
    .maybeSingle();
  if (existing?.status === "active") {
    return { status: "already_member", family_id: invite.family_id, role: existing.role, owner_name: null };
  }

  const { data: member, error: memberError } = await supabaseAdmin
    .from("family_members")
    .upsert({
      family_id: invite.family_id,
      user_id: userId,
      role: invite.role,
      status: "active",
      joined_at: new Date().toISOString(),
    }, { onConflict: "family_id,user_id" })
    .select()
    .single();
  if (memberError || !member) {
    logError("legacy join: member upsert failed", memberError, { userId });
    return { status: "error" };
  }

  if (invite.role === "receiver") {
    await supabaseAdmin.from("receiver_settings").upsert({
      family_member_id: member.id,
      checkin_time: invite.checkin_time || "08:00",
      timezone: timezone || "America/New_York",
    }, { onConflict: "family_member_id" });
  }

  const updates: Record<string, string> = { role: invite.role };
  if (invite.name) updates.display_name = invite.name;
  await supabaseAdmin.from("users").update(updates).eq("id", userId);
  await supabaseAdmin.from("invite_tokens").update({ used_by: userId }).eq("id", invite.id);

  return {
    status: "joined",
    family_id: invite.family_id,
    member_id: member.id,
    role: invite.role,
    checkin_time: invite.checkin_time,
    name: invite.name,
    owner_name: null,
  };
}

export const LIMIT_REACHED_MESSAGE =
  "This family has no free receiver slots. Ask the person who invited you to upgrade their plan or remove someone first.";
