import { supabaseAdmin } from "../../shared/supabase.ts";
import { sendSMS } from "../../shared/sms.ts";
import type { AuthResult } from "../../shared/auth.ts";
import { isValidUUID, isValidTime24H, isValidTimezone, truncateString, sanitizeDisplayName } from "../../shared/validation.ts";

interface InviteRequest {
  action?: "create" | "accept";
  // Create invite
  family_id?: string;
  name?: string;
  phone?: string;
  checkin_time?: string;
  timezone?: string;
  // Accept invite
  token?: string;
}

export async function handleInviteReceiver(req: Request, auth: AuthResult): Promise<Response> {
  const body: InviteRequest = await req.json();
  const action = body.action || "create";

  if (action === "accept") {
    return acceptInvite(body, auth);
  }

  return createInvite(body, auth);
}

async function createInvite(body: InviteRequest, auth: AuthResult): Promise<Response> {
  const { family_id, name, phone, checkin_time } = body;

  if (!family_id || !name || !phone) {
    return new Response(
      JSON.stringify({ error: "family_id, name, and phone are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Validate UUID format
  if (!isValidUUID(family_id)) {
    return new Response(
      JSON.stringify({ error: "Invalid family_id format" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Validate name length
  if (name.trim().length === 0 || name.length > 255) {
    return new Response(
      JSON.stringify({ error: "Name must be between 1 and 255 characters" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Validate checkin_time format if provided
  if (checkin_time && !isValidTime24H(checkin_time)) {
    return new Response(
      JSON.stringify({ error: "Invalid checkin_time format. Use HH:MM (24-hour)" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Validate timezone if provided
  const timezone = body.timezone;
  if (timezone && !isValidTimezone(timezone)) {
    return new Response(
      JSON.stringify({ error: "Invalid timezone. Must be a valid IANA timezone" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Validate phone number format (E.164 international or US)
  if (phone.length > 20 || !isValidPhone(phone)) {
    return new Response(
      JSON.stringify({ error: "Invalid phone number. Please use E.164 format (e.g., +15551234567) or a valid US number." }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Verify the requesting user is the family owner
  if (!auth.userId) {
    return new Response(
      JSON.stringify({ error: "Authentication required" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  const { data: family } = await supabaseAdmin
    .from("families")
    .select("owner_id, max_receivers")
    .eq("id", family_id)
    .single();

  if (!family || family.owner_id !== auth.userId) {
    return new Response(
      JSON.stringify({ error: "Only the family owner can send invites" }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  // Check receiver limit
  const { count: currentReceivers } = await supabaseAdmin
    .from("family_members")
    .select("*", { count: "exact", head: true })
    .eq("family_id", family_id)
    .eq("role", "receiver")
    .in("status", ["active", "invited"]);

  if (currentReceivers !== null && currentReceivers >= family.max_receivers) {
    return new Response(
      JSON.stringify({ error: "Receiver limit reached for your subscription tier" }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  // Generate cryptographically secure invite token
  const tokenBytes = new Uint8Array(32);
  crypto.getRandomValues(tokenBytes);
  const inviteToken = Array.from(tokenBytes, (b) => b.toString(16).padStart(2, "0")).join("");

  // Generate a short 6-digit pairing code for iPad / alternate-device setup
  const pairingCode = generatePairingCode();

  // Store invite
  const { error: inviteError } = await supabaseAdmin.from("invite_tokens").insert({
    family_id,
    role: "receiver",
    phone,
    name,
    checkin_time: checkin_time || "08:00",
    token: inviteToken,
    pairing_code: pairingCode,
  });

  if (inviteError) {
    return new Response(
      JSON.stringify({ error: "Failed to create invite" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // Generate deep link (kept as fallback for QR/link sharing)
  const inviteLink = `https://wellvo.net/invite?token=${inviteToken}`;

  // Send SMS invite to receiver
  // The receiver just needs to download the app and sign in with this phone number —
  // auto-join will match them to this invite automatically.
  // The pairing code is included so they can set up on an iPad or other device.
  const safeName = sanitizeDisplayName(name);
  const smsBody =
    `${safeName}, your family wants to check in with you daily using Wellvo. ` +
    `Download the app and sign in with this phone number to get started: ` +
    `https://apps.apple.com/app/alive-daily-checkin/id6742044109\n\n` +
    `Setting up on an iPad? Use this code: ${pairingCode}`;
  const smsResult = await sendSMS(phone, smsBody);

  return new Response(
    JSON.stringify({
      success: true,
      invite_token: inviteToken,
      invite_link: inviteLink,
      pairing_code: pairingCode,
      sms_sent: smsResult.success,
    }),
    { headers: { "Content-Type": "application/json" } }
  );
}

async function acceptInvite(body: InviteRequest, auth: AuthResult): Promise<Response> {
  const { token } = body;

  if (!token) {
    return new Response(
      JSON.stringify({ error: "Invite token is required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Validate token format (hex string, expected 64 chars from 32 bytes)
  if (token.length > 500 || !/^[0-9a-f]+$/i.test(token)) {
    return new Response(
      JSON.stringify({ error: "Invalid invite token format" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // User must be authenticated via JWT — get their ID from the verified token
  if (!auth.userId) {
    return new Response(
      JSON.stringify({ error: "You must be signed in to accept an invite" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  const acceptingUserId = auth.userId;

  // Look up invite — use constant-time-safe lookup (the DB query itself is safe)
  const { data: invite, error: inviteError } = await supabaseAdmin
    .from("invite_tokens")
    .select("*")
    .eq("token", token)
    .is("used_by", null)
    .gt("expires_at", new Date().toISOString())
    .single();

  // Return same error for invalid, expired, or used tokens (prevents enumeration)
  if (inviteError || !invite) {
    return new Response(
      JSON.stringify({ error: "This invite link is invalid or has expired" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Check the user isn't already a member of this family
  const { data: existingMember } = await supabaseAdmin
    .from("family_members")
    .select("id, status")
    .eq("family_id", invite.family_id)
    .eq("user_id", acceptingUserId)
    .single();

  if (existingMember && existingMember.status === "active") {
    return new Response(
      JSON.stringify({ error: "You are already a member of this family" }),
      { status: 409, headers: { "Content-Type": "application/json" } }
    );
  }

  // Create or reactivate family member
  let memberId: string;

  if (existingMember) {
    // Reactivate deactivated member
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
        user_id: acceptingUserId,
        role: invite.role,
        status: "active",
        joined_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (memberError) {
      return new Response(
        JSON.stringify({ error: "Failed to join family" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
    memberId = member.id;
  }

  // Create receiver settings if receiver role
  if (invite.role === "receiver" && memberId) {
    await supabaseAdmin.from("receiver_settings").upsert({
      family_member_id: memberId,
      checkin_time: invite.checkin_time || "08:00",
      timezone: body.timezone || "America/New_York",
    });
  }

  // Update user role
  await supabaseAdmin
    .from("users")
    .update({ role: invite.role })
    .eq("id", acceptingUserId);

  // Mark invite as used
  await supabaseAdmin
    .from("invite_tokens")
    .update({ used_by: acceptingUserId })
    .eq("id", invite.id);

  return new Response(
    JSON.stringify({ success: true, family_id: invite.family_id, role: invite.role }),
    { headers: { "Content-Type": "application/json" } }
  );
}

/**
 * Generate a cryptographically random 6-digit pairing code (100000–999999).
 * Used for iPad / alternate-device setup where phone auto-join isn't possible.
 */
function generatePairingCode(): string {
  const bytes = new Uint8Array(4);
  crypto.getRandomValues(bytes);
  const num = ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) >>> 0;
  // Map to 100000–999999 range
  const code = 100000 + (num % 900000);
  return String(code);
}

/**
 * Validate phone number: E.164 international format or US formats.
 * E.164: +[1-9][0-9]{1,14}
 * US: (xxx) xxx-xxxx, xxx-xxx-xxxx, +1xxxxxxxxxx, xxxxxxxxxx
 */
function isValidPhone(phone: string): boolean {
  const stripped = phone.replace(/[\s\-().]/g, "");
  // E.164 international format
  if (/^\+[1-9]\d{1,14}$/.test(stripped)) return true;
  // US number without country code (10 digits starting with 2-9)
  if (/^[2-9]\d{9}$/.test(stripped)) return true;
  // US number with leading 1 (11 digits)
  if (/^1[2-9]\d{9}$/.test(stripped)) return true;
  return false;
}
