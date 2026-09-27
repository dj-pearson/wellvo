import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";
import { isValidTimezone } from "../../shared/validation.ts";
import { describeInvite, LIMIT_REACHED_MESSAGE, redeemInvite } from "../../shared/join-family.ts";
import { verifiedPhoneMatchesInvite } from "../../shared/phone-match.ts";

/**
 * Auto-join: matches an authenticated user's phone number to a pending invite.
 *
 * When a receiver signs in, the app calls this endpoint. We take the phone
 * number Supabase Auth verified by SMS code, find a matching unused
 * invite_token, and join the family through redeem_invite — no link or code
 * needed. Accounts without a verified phone (Apple / email sign-in) get
 * `no_phone` and join with the invite link or pairing code instead.
 */
export async function handleAutoJoin(
  req: Request,
  auth: AuthResult,
): Promise<Response> {
  if (!auth.userId) {
    return new Response(
      JSON.stringify({ error: "Authentication required" }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  // Optional device timezone (additive field; shipped builds send no body).
  // Optional `preview: true` (additive): describe the matched family without
  // joining, so the app can ask "Join Sarah's family?" first. Builds that
  // don't send it join at once, as before.
  // Optional `family_id` (additive): join only an invite from the family the
  // app just showed in its preview, so "Join" can never land somewhere else
  // (e.g. a second family invited the same number in between).
  let timezone: string | null = null;
  let preview = false;
  let familyId: string | null = null;
  try {
    const body = await req.json();
    if (typeof body?.timezone === "string" && isValidTimezone(body.timezone)) {
      timezone = body.timezone;
    }
    preview = body?.preview === true;
    if (typeof body?.family_id === "string" && body.family_id.length <= 64) {
      familyId = body.family_id;
    }
  } catch {
    // No or non-JSON body — fine.
  }

  // Get the user's phone from Supabase Auth
  const { data: authUser, error: authError } =
    await supabaseAdmin.auth.admin.getUserById(auth.userId);

  if (authError || !authUser?.user) {
    return new Response(
      JSON.stringify({ error: "Could not retrieve user info" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  // Only a number Supabase Auth has verified by SMS code may claim an invite.
  // The users.phone column is NOT a fallback: it was client-writable, so
  // trusting it let anyone type a victim's number and take their invite.
  const userPhone = authUser.user.phone_confirmed_at ? authUser.user.phone : null;
  if (!userPhone) {
    return new Response(
      JSON.stringify({ matched: false, reason: "no_phone" }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  return tryMatchPhone(userPhone, auth.userId, timezone, preview, familyId);
}

async function tryMatchPhone(
  phone: string,
  userId: string,
  timezone: string | null,
  preview: boolean,
  familyId: string | null,
): Promise<Response> {
  // Find a matching unused, non-expired invite
  // invite_tokens.phone is stored in various formats, so we normalize in the query
  const { data: invites, error: inviteError } = await supabaseAdmin
    .from("invite_tokens")
    .select("*")
    .is("used_by", null)
    .gt("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false });

  if (inviteError || !invites || invites.length === 0) {
    return new Response(
      JSON.stringify({ matched: false, reason: "no_pending_invites" }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  // Match by E.164 digits
  const invite = invites.find((inv: { phone: string | null; family_id: string }) =>
    verifiedPhoneMatchesInvite(phone, inv.phone) && (familyId === null || inv.family_id === familyId)
  );

  if (!invite) {
    return new Response(
      JSON.stringify({ matched: false, reason: "no_matching_invite" }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  if (preview) {
    const described = await describeInvite(invite.id, userId);
    if (!described) {
      return json({ matched: false, reason: "no_matching_invite" });
    }
    return json({ matched: true, ...described });
  }

  const result = await redeemInvite(invite.id, userId, timezone, "phone");

  switch (result.status) {
    case "joined":
      return json({
        matched: true,
        family_id: result.family_id,
        role: result.role,
        checkin_time: result.checkin_time,
        owner_name: result.owner_name,
      });
    case "already_member":
      return json({
        matched: true,
        already_member: true,
        family_id: result.family_id,
        role: result.role,
      });
    case "limit_reached":
      return json({ matched: false, reason: "limit_reached", message: LIMIT_REACHED_MESSAGE });
    case "invalid":
      // Redeemed or expired between the lookup and the join.
      return json({ matched: false, reason: "no_matching_invite" });
    default:
      return json({ error: "Failed to join family" }, 500);
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
