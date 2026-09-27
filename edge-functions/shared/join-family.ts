import { supabaseAdmin } from "./supabase.ts";
import { logError } from "./logger.ts";
import { sendNotificationToUser } from "./send-notification.ts";

/** How someone joined: invite link, phone-number match, or 6-digit code. */
export type JoinVia = "link" | "phone" | "code";

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
  via?: JoinVia,
): Promise<JoinResult> {
  const { data, error } = await supabaseAdmin.rpc("redeem_invite", {
    p_invite_id: inviteId,
    p_user_id: userId,
    p_timezone: timezone ?? null,
  });
  let result: JoinResult;
  if (error && isMissingFunction(error)) {
    // The edge deploy is not gated on the migration run, so this can be live
    // before 00054 creates redeem_invite. Joining must keep working in that
    // window, so fall back to the pre-00054 step-by-step join.
    result = await legacyRedeemInvite(inviteId, userId, timezone);
  } else if (error || !data) {
    logError("redeem_invite failed", error, { userId });
    return { status: "error" };
  } else {
    result = data as JoinResult;
  }
  if (via) await notifyOwnerOfJoin(inviteId, result, via);
  return result;
}

/**
 * Tell the family owner when someone joins, or tried to join a full family.
 *
 * Joining never asked the owner, and a 6-digit code can be guessed, so the
 * owner is the one who can spot a stranger ("Not them? Remove them from the
 * Family tab."). A join refused for lack of a free slot used to reach only the
 * invitee, who can't fix it. Best effort: a failed push never fails the join.
 */
/**
 * A refused join is retried by the invitee's app (auto-join runs every time a
 * signed-in user with no family opens it), so the owner is told about a given
 * invite at most once per window rather than on every launch. In-memory, like
 * the rate limiter: fine for the single-container deploy.
 */
const BLOCKED_NOTICE_WINDOW_MS = 6 * 60 * 60 * 1000;
const lastBlockedNotice = new Map<string, number>();

function shouldSendBlockedNotice(inviteId: string, now = Date.now()): boolean {
  const last = lastBlockedNotice.get(inviteId);
  if (last !== undefined && now - last < BLOCKED_NOTICE_WINDOW_MS) return false;
  lastBlockedNotice.set(inviteId, now);
  if (lastBlockedNotice.size > 5000) {
    for (const [id, at] of lastBlockedNotice) {
      if (now - at >= BLOCKED_NOTICE_WINDOW_MS) lastBlockedNotice.delete(id);
    }
  }
  return true;
}

async function notifyOwnerOfJoin(inviteId: string, result: JoinResult, via: JoinVia): Promise<void> {
  if (result.status !== "joined" && result.status !== "limit_reached") return;
  if (result.status === "limit_reached" && !shouldSendBlockedNotice(inviteId)) return;
  try {
    const { data: invite } = await supabaseAdmin
      .from("invite_tokens")
      .select("name, role, family_id")
      .eq("id", inviteId)
      .maybeSingle();
    if (!invite) return;
    const { data: family } = await supabaseAdmin
      .from("families")
      .select("id, owner_id")
      .eq("id", invite.family_id)
      .maybeSingle();
    if (!family?.owner_id) return;

    const who = (invite.name ?? "").trim() || "Someone you invited";
    const isViewer = invite.role === "viewer";
    let title: string;
    let body: string;
    if (result.status === "joined") {
      title = `${who} joined your family`;
      body = isViewer
        ? `${who} will now be told if a check-in is missed.`
        : `${who} is set up for daily check-ins.`;
      if (via === "code") {
        body += " They used the setup code. Not them? Remove them from the Family tab.";
      }
    } else {
      title = `${who} couldn't join`;
      body = isViewer
        ? "Your plan has no free co-caregiver seats. Upgrade or remove someone in the Family tab, then ask them to try again."
        : "Your plan has no free slots for someone to check on. Upgrade or remove someone in the Family tab, then ask them to try again.";
    }

    const type = result.status === "joined" ? "member_joined" : "member_join_blocked";
    await sendNotificationToUser(
      family.owner_id,
      {
        aps: {
          alert: { title, body },
          sound: "default",
          "thread-id": `family-${family.id}`,
        },
        type,
        family_id: family.id,
      },
      { title, body, data: { type, family_id: family.id } },
      // Repeats of the same notice replace each other instead of stacking.
      { collapseId: `${type}-${inviteId}`.slice(0, 64) },
    );
  } catch (e) {
    logError("join notification failed", e, { inviteId });
  }
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

/**
 * What joining this invite would mean, WITHOUT joining (the optional
 * `preview: true` request field on invite-receiver accept, redeem-code and
 * auto-join; older clients never send it and still join at once).
 *
 * Joining used to happen before the joiner saw anything: a link redeemed as
 * the screen appeared, a phone match redeemed during launch, and a code
 * redeemed on its sixth digit. Someone who mistyped a code, or whose number
 * was on a stranger's invite, became a member watched every day without being
 * told by whom. New builds show this first and only redeem on "Join".
 */
export interface JoinPreview {
  preview: true;
  family_id: string;
  family_name: string | null;
  role: string;
  /** The inviting owner's display name ("User" when they never set one). */
  owner_name: string | null;
  /** What the owner called the invitee ("Mom"). */
  invite_name: string | null;
  checkin_time: string | null;
  /** Everyone who will see this person's check-ins: the owner, then active co-caregivers. */
  watchers: string[];
  /** The caller is already an active member of this family. */
  already_member: boolean;
}

export async function describeInvite(inviteId: string, userId: string): Promise<JoinPreview | null> {
  const { data: invite } = await supabaseAdmin
    .from("invite_tokens")
    .select("id, family_id, role, name, checkin_time")
    .eq("id", inviteId)
    .maybeSingle();
  if (!invite) return null;

  const { data: family } = await supabaseAdmin
    .from("families")
    .select("id, name, owner_id")
    .eq("id", invite.family_id)
    .maybeSingle();
  if (!family) return null;

  const { data: members } = await supabaseAdmin
    .from("family_members")
    .select("user_id, role, status")
    .eq("family_id", family.id)
    .eq("status", "active");
  const active = (members ?? []) as { user_id: string; role: string }[];
  const viewerIds = active.filter((m) => m.role === "viewer" && m.user_id !== userId).map((m) => m.user_id);

  const ids = [family.owner_id, ...viewerIds].filter(Boolean) as string[];
  const names = new Map<string, string>();
  if (ids.length > 0) {
    const { data: users } = await supabaseAdmin
      .from("users")
      .select("id, display_name")
      .in("id", ids);
    for (const u of (users ?? []) as { id: string; display_name: string | null }[]) {
      const name = (u.display_name ?? "").trim();
      if (name) names.set(u.id, name);
    }
  }

  const ownerName = names.get(family.owner_id) ?? null;
  const watchers: string[] = [];
  if (ownerName && ownerName !== "User") watchers.push(ownerName);
  for (const id of viewerIds) {
    const n = names.get(id);
    if (n && n !== "User") watchers.push(n);
  }

  // Already in: report the role they actually hold (an owner typing their
  // own family's code is not about to become a receiver).
  const mine = active.find((m) => m.user_id === userId);

  return {
    preview: true,
    family_id: family.id,
    family_name: family.name ?? null,
    role: mine?.role ?? invite.role ?? "receiver",
    owner_name: ownerName,
    invite_name: invite.name ?? null,
    checkin_time: invite.role === "viewer" ? null : (invite.checkin_time ?? null),
    watchers: watchers.slice(0, 10),
    already_member: mine !== undefined,
  };
}

export const LIMIT_REACHED_MESSAGE =
  "This family's plan has no free places. Ask the person who invited you to upgrade their plan or remove someone first.";
