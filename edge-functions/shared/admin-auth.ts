/**
 * System admin authorization helper.
 *
 * Usage in a function handler:
 *   const admin = await requireSystemAdmin(auth);
 *   if (!admin.ok) return admin.response;
 *   // admin.userId is guaranteed to be a system admin
 */

import { supabaseAdmin } from "./supabase.ts";
import type { AuthResult } from "./auth.ts";

export interface AdminAuthOk {
  ok: true;
  userId: string;
}

export interface AdminAuthErr {
  ok: false;
  response: Response;
}

export type AdminAuthResult = AdminAuthOk | AdminAuthErr;

function forbidden(message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status: 403,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * Require a JWT-authenticated request from a user with is_system_admin = TRUE.
 * Service role calls are rejected — admin endpoints are user-initiated.
 */
export async function requireSystemAdmin(auth: AuthResult): Promise<AdminAuthResult> {
  if (!auth.authenticated || !auth.userId || auth.isServiceRole) {
    return { ok: false, response: forbidden("admin access required") };
  }

  const { data, error } = await supabaseAdmin
    .from("users")
    .select("is_system_admin")
    .eq("id", auth.userId)
    .maybeSingle();

  if (error || !data || !data.is_system_admin) {
    return { ok: false, response: forbidden("admin access required") };
  }

  return { ok: true, userId: auth.userId };
}

/**
 * Log an admin action to admin_activity_log. Fire-and-forget; errors are swallowed.
 */
export async function logAdminAction(
  adminId: string,
  action: string,
  opts: {
    resourceType?: string;
    resourceId?: string;
    metadata?: Record<string, unknown>;
    req?: Request;
  } = {},
): Promise<void> {
  try {
    const ip = opts.req?.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null;
    const userAgent = opts.req?.headers.get("user-agent") ?? null;

    await supabaseAdmin.from("admin_activity_log").insert({
      admin_id: adminId,
      action,
      resource_type: opts.resourceType ?? null,
      resource_id: opts.resourceId ?? null,
      metadata: opts.metadata ?? null,
      ip_address: ip,
      user_agent: userAgent,
    });
  } catch {
    // Audit logging is best-effort.
  }
}
