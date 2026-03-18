import { supabaseAdmin } from "../../shared/supabase.ts";

interface InviteRequest {
  action?: "create" | "accept";
  // Create invite
  family_id?: string;
  name?: string;
  phone?: string;
  checkin_time?: string;
  // Accept invite
  token?: string;
}

export async function handleInviteReceiver(req: Request): Promise<Response> {
  const body: InviteRequest = await req.json();
  const action = body.action || "create";

  if (action === "accept") {
    return acceptInvite(body);
  }

  return createInvite(req, body);
}

async function createInvite(req: Request, body: InviteRequest): Promise<Response> {
  const { family_id, name, phone, checkin_time } = body;

  if (!family_id || !name || !phone) {
    return new Response(
      JSON.stringify({ error: "family_id, name, and phone are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Check receiver limit
  const { data: family } = await supabaseAdmin
    .from("families")
    .select("max_receivers")
    .eq("id", family_id)
    .single();

  const { count: currentReceivers } = await supabaseAdmin
    .from("family_members")
    .select("*", { count: "exact", head: true })
    .eq("family_id", family_id)
    .eq("role", "receiver")
    .in("status", ["active", "invited"]);

  if (family && currentReceivers !== null && currentReceivers >= family.max_receivers) {
    return new Response(
      JSON.stringify({ error: "Receiver limit reached for your subscription tier" }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  // Generate invite token
  const inviteToken = crypto.randomUUID().replace(/-/g, "");

  // Store invite
  const { error: inviteError } = await supabaseAdmin.from("invite_tokens").insert({
    family_id,
    role: "receiver",
    phone,
    name,
    checkin_time: checkin_time || "08:00",
    token: inviteToken,
  });

  if (inviteError) {
    return new Response(
      JSON.stringify({ error: "Failed to create invite", details: inviteError }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // Generate deep link
  const inviteLink = `https://wellvo.net/invite?token=${inviteToken}`;

  // In production, send SMS via Twilio/SNS here
  // For MVP, return the link for the owner to share manually
  console.log(`Invite link for ${name} (${phone}): ${inviteLink}`);

  return new Response(
    JSON.stringify({
      success: true,
      invite_token: inviteToken,
      invite_link: inviteLink,
    }),
    { headers: { "Content-Type": "application/json" } }
  );
}

async function acceptInvite(body: InviteRequest): Promise<Response> {
  const { token } = body;

  if (!token) {
    return new Response(
      JSON.stringify({ error: "Invite token is required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // Look up invite
  const { data: invite, error: inviteError } = await supabaseAdmin
    .from("invite_tokens")
    .select("*")
    .eq("token", token)
    .is("used_by", null)
    .gt("expires_at", new Date().toISOString())
    .single();

  if (inviteError || !invite) {
    return new Response(
      JSON.stringify({ error: "Invalid or expired invite token" }),
      { status: 404, headers: { "Content-Type": "application/json" } }
    );
  }

  // The accepting user's ID should come from the auth context
  // For now, we get it from the request auth header
  const authHeader = body as Record<string, string>;
  // In production, extract from JWT
  const acceptingUserId = authHeader.user_id;

  if (!acceptingUserId) {
    return new Response(
      JSON.stringify({ error: "User must be authenticated to accept invite" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  // Create family member
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
      JSON.stringify({ error: "Failed to join family", details: memberError }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // Create receiver settings
  if (invite.role === "receiver" && member) {
    await supabaseAdmin.from("receiver_settings").insert({
      family_member_id: member.id,
      checkin_time: invite.checkin_time || "08:00",
      timezone: "America/New_York", // Will be updated by the app
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
