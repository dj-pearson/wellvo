import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";

/**
 * Auto-join: matches an authenticated user's phone number to a pending invite.
 *
 * When a receiver signs in (via phone OTP or any method), the iOS app calls
 * this endpoint. We look up the user's phone from Supabase Auth, check for
 * a matching unused invite_token, and auto-accept it — no token/link needed.
 */
export async function handleAutoJoin(
  _req: Request,
  auth: AuthResult,
): Promise<Response> {
  if (!auth.userId) {
    return new Response(
      JSON.stringify({ error: "Authentication required" }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
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

  const userPhone = authUser.user.phone;
  if (!userPhone) {
    // No phone on the auth record — also check the users table
    const { data: profile } = await supabaseAdmin
      .from("users")
      .select("phone")
      .eq("id", auth.userId)
      .single();

    if (!profile?.phone) {
      return new Response(
        JSON.stringify({ matched: false, reason: "no_phone" }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    return tryMatchPhone(profile.phone, auth.userId);
  }

  return tryMatchPhone(userPhone, auth.userId);
}

async function tryMatchPhone(
  phone: string,
  userId: string,
): Promise<Response> {
  // Normalize to digits-only for comparison
  const normalized = phone.replace(/[^\d]/g, "");
  // Try both with and without leading 1
  const variants = [normalized];
  if (normalized.startsWith("1") && normalized.length === 11) {
    variants.push(normalized.slice(1));
  } else if (normalized.length === 10) {
    variants.push("1" + normalized);
  }

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

  // Match by normalized phone
  const invite = invites.find((inv) => {
    const invPhone = inv.phone.replace(/[^\d]/g, "");
    return variants.some(
      (v) => v === invPhone || v === invPhone.replace(/^1/, ""),
    );
  });

  if (!invite) {
    return new Response(
      JSON.stringify({ matched: false, reason: "no_matching_invite" }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  // Check if user is already a member
  const { data: existingMember } = await supabaseAdmin
    .from("family_members")
    .select("id, status")
    .eq("family_id", invite.family_id)
    .eq("user_id", userId)
    .single();

  if (existingMember && existingMember.status === "active") {
    return new Response(
      JSON.stringify({
        matched: true,
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
        user_id: userId,
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

  // Create receiver settings
  if (invite.role === "receiver" && memberId) {
    await supabaseAdmin.from("receiver_settings").upsert({
      family_member_id: memberId,
      checkin_time: invite.checkin_time || "08:00",
      timezone: "America/New_York", // Default; updated by the app after joining
    });
  }

  // Update user role and display name from invite
  const updates: Record<string, string> = { role: invite.role };
  if (invite.name) {
    updates.display_name = invite.name;
  }
  await supabaseAdmin.from("users").update(updates).eq("id", userId);

  // Mark invite as used
  await supabaseAdmin
    .from("invite_tokens")
    .update({ used_by: userId })
    .eq("id", invite.id);

  return new Response(
    JSON.stringify({
      matched: true,
      family_id: invite.family_id,
      role: invite.role,
      checkin_time: invite.checkin_time,
      owner_name: null, // Could be fetched if needed
    }),
    { headers: { "Content-Type": "application/json" } },
  );
}
