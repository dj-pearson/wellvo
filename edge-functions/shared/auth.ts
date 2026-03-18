/**
 * JWT verification for edge function requests.
 * Validates Supabase-issued JWTs or the service role key.
 */

import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "http://supabase-kong:8000";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const JWT_SECRET = Deno.env.get("JWT_SECRET") || "";

export interface AuthResult {
  authenticated: boolean;
  userId?: string;
  isServiceRole: boolean;
}

/**
 * Verify the Authorization header and extract user identity.
 * - Service role key: full admin access (from pg_cron, internal calls)
 * - User JWT: verified via Supabase auth, returns user ID
 */
export async function verifyRequest(req: Request): Promise<AuthResult> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return { authenticated: false, isServiceRole: false };
  }

  const token = authHeader.substring(7); // Remove "Bearer "

  // Check service role key (exact match for internal/pg_cron calls)
  if (token === SUPABASE_SERVICE_ROLE_KEY) {
    return { authenticated: true, isServiceRole: true };
  }

  // Verify user JWT via Supabase Auth
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data, error } = await supabase.auth.getUser(token);

    if (error || !data?.user) {
      return { authenticated: false, isServiceRole: false };
    }

    return {
      authenticated: true,
      userId: data.user.id,
      isServiceRole: false,
    };
  } catch {
    return { authenticated: false, isServiceRole: false };
  }
}

/**
 * Extract the authenticated user ID from a request.
 * Returns null if not authenticated or if using service role.
 */
export async function getAuthenticatedUserId(req: Request): Promise<string | null> {
  const result = await verifyRequest(req);
  return result.authenticated ? result.userId ?? null : null;
}
