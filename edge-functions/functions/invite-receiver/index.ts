import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";
import { isValidUUID, isValidTime24H, isValidTimezone, sanitizeDisplayName } from "../../shared/validation.ts";
import { describeInvite, LIMIT_REACHED_MESSAGE, redeemInvite } from "../../shared/join-family.ts";
import { buildCaregiverInviteMessage, buildInviteLink, buildInviteMessage } from "../../shared/invite-message.ts";

interface InviteRequest {
  action?: "create" | "accept";
  // Create invite
  family_id?: string;
  name?: string;
  phone?: string;
  checkin_time?: string;
  timezone?: string;
  /**
   * Optional (additive): who is being invited. "receiver" (the default, and
   * all that older clients send) is someone to check on; "viewer" is a
   * co-caregiver who gets alerts but no check-ins.
   */
  role?: "receiver" | "viewer";
  // Accept invite
  token?: string;
  /**
   * Optional (additive, accept only): describe the family without joining it,
   * so the app can ask first. Older builds never send it and join at once.
   */
  preview?: boolean;
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
  const role: string = body.role ?? "receiver";

  if (role !== "receiver" && role !== "viewer") {
    return new Response(
      JSON.stringify({ error: "role must be \"receiver\" or \"viewer\"" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

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
    .select("owner_id, max_receivers, max_viewers")
    .eq("id", family_id)
    .single();

  if (!family || family.owner_id !== auth.userId) {
    return new Response(
      JSON.stringify({ error: "Only the family owner can send invites" }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  if (role === "receiver") {
    // Check receiver limit (unchanged for shipped clients: open invites are
    // not counted here, so the 403 contract is the same as before; the app
    // counts them itself, and redeem_invite enforces the limit at join).
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
  } else {
    // Co-caregiver seats: active viewers plus open viewer invites to other
    // numbers (a re-send to the same number replaces its invite, so it must
    // not count against itself). A new path, so counting open invites here
    // changes nothing for older clients.
    const { count: activeViewers } = await supabaseAdmin
      .from("family_members")
      .select("*", { count: "exact", head: true })
      .eq("family_id", family_id)
      .eq("role", "viewer")
      .eq("status", "active");

    const { data: openViewerInvites } = await supabaseAdmin
      .from("invite_tokens")
      .select("phone")
      .eq("family_id", family_id)
      .eq("role", "viewer")
      .is("used_by", null)
      .gt("expires_at", new Date().toISOString());

    const target = phoneDigits(phone);
    const waiting = new Set(
      (openViewerInvites ?? [])
        .map((inv: { phone: string | null }) => phoneDigits(inv.phone ?? ""))
        .filter((d: string) => d !== "" && d !== target),
    ).size;

    if ((activeViewers ?? 0) + waiting >= (family.max_viewers ?? 0)) {
      return new Response(
        JSON.stringify({
          error: "Co-caregiver limit reached for your subscription tier",
          reason: "viewer_limit_reached",
        }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // Generate cryptographically secure invite token
  const tokenBytes = new Uint8Array(32);
  crypto.getRandomValues(tokenBytes);
  const inviteToken = Array.from(tokenBytes, (b) => b.toString(16).padStart(2, "0")).join("");

  // Store invite. The 6-digit pairing code (for iPad / alternate-device setup)
  // is unique among unused invites, so retry the rare collision instead of
  // failing the owner's invite.
  let pairingCode = "";
  let inviteError: { code?: string } | null = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    pairingCode = generatePairingCode();
    ({ error: inviteError } = await supabaseAdmin.from("invite_tokens").insert({
      family_id,
      role,
      phone,
      name,
      // A co-caregiver has no check-in schedule.
      checkin_time: role === "viewer" ? null : checkin_time || "08:00",
      token: inviteToken,
      pairing_code: pairingCode,
    }));
    if (inviteError?.code !== "23505") break;
  }

  if (inviteError) {
    return new Response(
      JSON.stringify({ error: "Failed to create invite" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // A re-send replaces the earlier invite to this number rather than stacking
  // another live one beside it (which also kept a removed receiver able to
  // re-join through the stale invite). Done only once the new invite exists,
  // so a failed re-send never leaves the receiver with no working invite.
  await supersedeOpenInvites(family_id, phone, inviteToken);

  // One link for everyone. dailyok.net/invite/<token> opens the app directly
  // where Universal Links / App Links are set up, and otherwise lands on the
  // website's invite page, which offers the right store and an "Open in
  // Daily OK" button. The code rides along so that page can show it.
  // (The old `/invite?token=` form never matched the AASA `/invite/*` path and
  // the site had no page for it; apps still accept both forms.)
  const inviteLink = buildInviteLink(inviteToken, pairingCode);

  // Invitation delivery is a *native* send from the Owner's own device (the
  // Messages composer). We deliberately DO NOT send this invite through
  // Twilio: an invite goes to a person who has not opted into our A2P 10DLC
  // campaign, so it can't ride the approved sender. The Twilio campaign is
  // reserved for escalation alerts. P2P body — no STOP/HELP footer, since it
  // comes from the Owner's personal number.
  const inviteMessage = role === "viewer"
    ? buildCaregiverInviteMessage(sanitizeDisplayName(name), inviteLink, pairingCode)
    : buildInviteMessage(sanitizeDisplayName(name), inviteLink, pairingCode);

  return new Response(
    JSON.stringify({
      success: true,
      invite_token: inviteToken,
      invite_link: inviteLink,
      pairing_code: pairingCode,
      // The Owner's device delivers the invite natively; the server never sends
      // it. Kept for response-shape compatibility with older clients.
      sms_sent: false,
      // Pre-composed body for the native Messages composer (additive field).
      invite_message: inviteMessage,
      // Echoes the role actually stored (additive), so a client can tell an
      // older server that ignored `role` from one that honoured it.
      role,
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

  if (body.preview === true) {
    const preview = await describeInvite(invite.id, acceptingUserId);
    if (!preview) {
      return json({ error: "This invite link is invalid or has expired" }, 400);
    }
    return json(preview);
  }

  const result = await redeemInvite(invite.id, acceptingUserId, body.timezone, "link");

  switch (result.status) {
    case "joined":
      return json({
        success: true,
        family_id: result.family_id,
        role: result.role,
        checkin_time: result.checkin_time,
        name: result.name,
        owner_name: result.owner_name,
      });
    case "already_member":
      return json({ error: "You are already a member of this family" }, 409);
    case "limit_reached":
      return json({ error: LIMIT_REACHED_MESSAGE, reason: "limit_reached" }, 403);
    case "invalid":
      return json({ error: "This invite link is invalid or has expired" }, 400);
    default:
      return json({ error: "Failed to join family" }, 500);
  }
}

/**
 * Expire this family's other unused invites to the same number. Phones are
 * stored as typed, so compare digits (with or without the NANP leading 1).
 */
async function supersedeOpenInvites(familyId: string, phone: string, keepToken: string): Promise<void> {
  const { data: open } = await supabaseAdmin
    .from("invite_tokens")
    .select("id, phone")
    .eq("family_id", familyId)
    .neq("token", keepToken)
    .is("used_by", null)
    .gt("expires_at", new Date().toISOString());

  const target = phoneDigits(phone);
  const ids = (open ?? [])
    .filter((inv: { phone: string | null }) => phoneDigits(inv.phone ?? "") === target)
    .map((inv: { id: string }) => inv.id);
  if (ids.length === 0) return;

  await supabaseAdmin
    .from("invite_tokens")
    .update({ expires_at: new Date().toISOString() })
    .in("id", ids);
}

function phoneDigits(phone: string): string {
  const d = phone.replace(/\D/g, "");
  return d.length === 11 && d.startsWith("1") ? d.slice(1) : d;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
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
