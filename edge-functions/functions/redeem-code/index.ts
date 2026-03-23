import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";

interface RedeemRequest {
  code: string;
}

/**
 * Redeem a 6-digit pairing code to join a family.
 *
 * This enables the "iPad setup" flow: a receiver gets an SMS on their phone,
 * then opens the app on their iPad, signs in (Apple / email), and enters the
 * pairing code to bind their account to the family.
 */
export async function handleRedeemCode(
  req: Request,
  auth: AuthResult,
): Promise<Response> {
  if (!auth.userId) {
    return new Response(
      JSON.stringify({ error: "Authentication required" }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  const body: RedeemRequest = await req.json();
  const code = (body.code || "").trim();

  if (!/^\d{6}$/.test(code)) {
    return new Response(
      JSON.stringify({ error: "Please enter a valid 6-digit code" }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  // Look up a matching, unused, non-expired invite by pairing code
  const { data: invite, error: inviteError } = await supabaseAdmin
    .from("invite_tokens")
    .select("*")
    .eq("pairing_code", code)
    .is("used_by", null)
    .gt("expires_at", new Date().toISOString())
    .single();

  if (inviteError || !invite) {
    return new Response(
      JSON.stringify({ error: "Invalid or expired code. Please check and try again." }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  // Check if user is already a member of this family
  const { data: existingMember } = await supabaseAdmin
    .from("family_members")
    .select("id, status")
    .eq("family_id", invite.family_id)
    .eq("user_id", auth.userId)
    .single();

  if (existingMember && existingMember.status === "active") {
    return new Response(
      JSON.stringify({
        success: true,
        already_member: true,
        family_id: invite.family_id,
        role: invite.role,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  // Create or reactivate family member
  let memberId: string;

  if (existingMember) {
    const { data: updated } = await supabaseAdmin
      .from("family_members")
      .update({
        role: invite.role,
        status: "active",
        joined_at: new Date().toISOString(),
      })
      .eq("id", existingMember.id)
      .select()
      .single();
    memberId = updated?.id;
  } else {
    const { data: member, error: memberError } = await supabaseAdmin
      .from("family_members")
      .insert({
        family_id: invite.family_id,
        user_id: auth.userId,
        role: invite.role,
        status: "active",
        joined_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (memberError) {
      return new Response(
        JSON.stringify({ error: "Failed to join family" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }
    memberId = member.id;
  }

  // Create receiver settings if receiver role
  if (invite.role === "receiver" && memberId) {
    await supabaseAdmin.from("receiver_settings").upsert({
      family_member_id: memberId,
      checkin_time: invite.checkin_time || "08:00",
      timezone: "America/New_York",
    });
  }

  // Update user role and display name
  const updates: Record<string, string> = { role: invite.role };
  if (invite.name) {
    updates.display_name = invite.name;
  }
  await supabaseAdmin.from("users").update(updates).eq("id", auth.userId);

  // Mark invite as used
  await supabaseAdmin
    .from("invite_tokens")
    .update({ used_by: auth.userId })
    .eq("id", invite.id);

  return new Response(
    JSON.stringify({
      success: true,
      family_id: invite.family_id,
      role: invite.role,
      checkin_time: invite.checkin_time,
      name: invite.name,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
}
