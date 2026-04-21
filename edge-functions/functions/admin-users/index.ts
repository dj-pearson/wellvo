import { supabaseAdmin } from "../../shared/supabase.ts";
import { requireSystemAdmin, logAdminAction } from "../../shared/admin-auth.ts";
import type { AuthResult } from "../../shared/auth.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface Body {
  action: "list" | "get" | "set_admin";
  user_id?: string;
  search?: string;
  limit?: number;
  offset?: number;
  is_system_admin?: boolean;
}

export async function handleAdminUsers(req: Request, auth: AuthResult): Promise<Response> {
  const admin = await requireSystemAdmin(auth);
  if (!admin.ok) return admin.response;

  const body: Body = await req.json().catch(() => ({ action: "list" }));
  const action = body.action || "list";

  switch (action) {
    case "list":
      return listUsers(body);
    case "get":
      return getUser(body);
    case "set_admin":
      return setAdmin(body, admin.userId, req);
    default:
      return json({ error: "Unknown action" }, 400);
  }
}

async function listUsers(body: Body): Promise<Response> {
  const limit = Math.max(1, Math.min(200, body.limit ?? 50));
  const offset = Math.max(0, body.offset ?? 0);
  const search = (body.search || "").trim();

  let query = supabaseAdmin
    .from("users")
    .select("id, email, phone, display_name, role, is_system_admin, timezone, created_at, updated_at", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);

  if (search) {
    const like = `%${search.replace(/[%_]/g, "")}%`;
    query = query.or(`email.ilike.${like},display_name.ilike.${like},phone.ilike.${like}`);
  }

  const { data, error, count } = await query;
  if (error) return json({ error: error.message }, 500);

  return json({ users: data ?? [], total: count ?? 0, limit, offset });
}

async function getUser(body: Body): Promise<Response> {
  if (!body.user_id) return json({ error: "user_id required" }, 400);

  const [userRes, familiesRes, membersRes, checkinsRes, requestsRes] = await Promise.all([
    supabaseAdmin.from("users").select("*").eq("id", body.user_id).maybeSingle(),
    supabaseAdmin.from("families").select("*").eq("owner_id", body.user_id),
    supabaseAdmin
      .from("family_members")
      .select("*, families(id, name, owner_id, subscription_tier)")
      .eq("user_id", body.user_id),
    supabaseAdmin
      .from("checkins")
      .select("id, checked_in_at, mood, source, family_id")
      .eq("receiver_id", body.user_id)
      .order("checked_in_at", { ascending: false })
      .limit(25),
    supabaseAdmin
      .from("checkin_requests")
      .select("id, status, created_at, type, family_id")
      .eq("receiver_id", body.user_id)
      .order("created_at", { ascending: false })
      .limit(25),
  ]);

  if (userRes.error) return json({ error: userRes.error.message }, 500);
  if (!userRes.data) return json({ error: "User not found" }, 404);

  return json({
    user: userRes.data,
    families_owned: familiesRes.data ?? [],
    memberships: membersRes.data ?? [],
    recent_checkins: checkinsRes.data ?? [],
    recent_requests: requestsRes.data ?? [],
  });
}

async function setAdmin(body: Body, adminId: string, req: Request): Promise<Response> {
  if (!body.user_id) return json({ error: "user_id required" }, 400);
  if (typeof body.is_system_admin !== "boolean") {
    return json({ error: "is_system_admin (boolean) required" }, 400);
  }

  // Safety: prevent removing admin from yourself if you're the only admin
  if (!body.is_system_admin && body.user_id === adminId) {
    const { count } = await supabaseAdmin
      .from("users")
      .select("*", { count: "exact", head: true })
      .eq("is_system_admin", true);
    if ((count ?? 0) <= 1) {
      return json({ error: "Cannot demote the last remaining system admin" }, 400);
    }
  }

  const { error } = await supabaseAdmin
    .from("users")
    .update({ is_system_admin: body.is_system_admin })
    .eq("id", body.user_id);

  if (error) return json({ error: error.message }, 500);

  await logAdminAction(adminId, body.is_system_admin ? "user.promote_admin" : "user.demote_admin", {
    resourceType: "user",
    resourceId: body.user_id,
    req,
  });

  return json({ success: true });
}
