import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";
import { isValidTimezone } from "../../shared/validation.ts";
import { logError } from "../../shared/logger.ts";
import { LIMIT_REACHED_MESSAGE, redeemInvite } from "../../shared/join-family.ts";

interface RedeemRequest {
  code: string;
  timezone?: string;
}

// Failed attempts allowed per user in the lockout window. Mirrors
// pairing_code_retry_after() (00054); only used to tell the user how many
// tries they have left.
const MAX_FAILED_ATTEMPTS = 10;

/**
 * Redeem a 6-digit pairing code to join a family.
 *
 * This enables the "iPad setup" flow: a receiver gets an SMS on their phone,
 * then opens the app on their iPad, signs in (Apple / email), and enters the
 * pairing code to bind their account to the family.
 *
 * Brute-force protection is durable (pairing_code_attempts, 00054): limits per
 * user, per IP and platform-wide survive restarts and a second account. It
 * used to be an in-memory map keyed per user, reset by every deploy.
 */
export async function handleRedeemCode(
  req: Request,
  auth: AuthResult,
): Promise<Response> {
  if (!auth.userId) {
    return json({ error: "Authentication required" }, 401);
  }
  const userId = auth.userId;
  const ip = clientIp(req);

  const retryAfterSeconds = await retryAfter(userId, ip);
  if (retryAfterSeconds > 0) {
    return new Response(
      JSON.stringify({
        error: "Too many failed attempts. Please try again later.",
        locked: true,
        retryAfterSeconds,
      }),
      {
        status: 429,
        headers: { "Content-Type": "application/json", "Retry-After": String(retryAfterSeconds) },
      },
    );
  }

  const body: RedeemRequest = await req.json();
  const code = (body.code || "").trim();

  if (!/^\d{6}$/.test(code)) {
    return json({ error: "Please enter a valid 6-digit code" }, 400);
  }

  // Validate timezone if provided
  if (body.timezone && !isValidTimezone(body.timezone)) {
    return json({ error: "Invalid timezone. Must be a valid IANA timezone" }, 400);
  }

  // Look up a matching, unused, non-expired invite by pairing code
  const { data: invite, error: inviteError } = await supabaseAdmin
    .from("invite_tokens")
    .select("id")
    .eq("pairing_code", code)
    .is("used_by", null)
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();

  if (inviteError || !invite) {
    const failures = await recordAttempt(userId, ip, false);
    return json({
      error: "Invalid or expired code. Please check and try again.",
      attemptsRemaining: Math.max(0, MAX_FAILED_ATTEMPTS - failures),
    }, 400);
  }

  await recordAttempt(userId, ip, true);

  const result = await redeemInvite(invite.id, userId, body.timezone);

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
      return json({
        success: true,
        already_member: true,
        family_id: result.family_id,
        role: result.role,
      });
    case "limit_reached":
      return json({ error: LIMIT_REACHED_MESSAGE, reason: "limit_reached" }, 403);
    case "invalid":
      // Redeemed or expired between the lookup and the join.
      return json({ error: "Invalid or expired code. Please check and try again." }, 400);
    default:
      return json({ error: "Failed to join family" }, 500);
  }
}

/** Seconds until this caller may try again; 0 when allowed. Fails open. */
async function retryAfter(userId: string, ip: string | null): Promise<number> {
  const { data, error } = await supabaseAdmin.rpc("pairing_code_retry_after", {
    p_user_id: userId,
    p_ip: ip,
  });
  if (error) {
    // A lockout outage must not block every legitimate receiver from joining.
    logError("pairing_code_retry_after failed", error, { userId, path: "/redeem-code" });
    return 0;
  }
  return typeof data === "number" ? data : 0;
}

/**
 * Record an attempt. Returns this user's failures in the lockout window
 * (including this one) so the response can say how many tries are left.
 */
async function recordAttempt(userId: string, ip: string | null, succeeded: boolean): Promise<number> {
  const { error } = await supabaseAdmin
    .from("pairing_code_attempts")
    .insert({ user_id: userId, ip, succeeded });
  if (error) {
    logError("Failed to record pairing-code attempt", error, { userId, path: "/redeem-code" });
  }
  if (succeeded) return 0;

  const since = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const { count } = await supabaseAdmin
    .from("pairing_code_attempts")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("succeeded", false)
    .gte("created_at", since);
  return count ?? 1;
}

/** The caller's IP as reported by the edge proxy (Cloudflare, then Traefik). */
function clientIp(req: Request): string | null {
  const cf = req.headers.get("CF-Connecting-IP");
  if (cf) return cf.trim();
  const real = req.headers.get("X-Real-IP");
  if (real) return real.trim();
  const fwd = req.headers.get("X-Forwarded-For");
  if (fwd) return fwd.split(",")[0].trim();
  return null;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
