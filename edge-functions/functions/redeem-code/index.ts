import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";
import { isValidTimezone } from "../../shared/validation.ts";
import { logError } from "../../shared/logger.ts";
import { describeInvite, LIMIT_REACHED_MESSAGE, redeemInvite } from "../../shared/join-family.ts";
import { clientIp } from "../../shared/client-ip.ts";

interface RedeemRequest {
  code: string;
  timezone?: string;
  /**
   * Optional (additive): describe the family this code joins without joining
   * it, so the app can ask "Join Sarah's family?" first. Counts toward the
   * same lockout as a redeem, so it is no better a guessing oracle. Older
   * builds never send it and join at once, as before.
   */
  preview?: boolean;
}

// Failed attempts allowed per user in the lockout window. Mirrors
// pairing_code_retry_after() (00054).
const MAX_FAILED_ATTEMPTS = 10;
const LOCKOUT_WINDOW_MS = 15 * 60 * 1000;

// Used only while the durable lockout is unavailable (this build deployed
// before 00054 ran, or the table is unreachable), so guessing is never
// unlimited. Per process and reset on restart — the pre-00054 behaviour.
const memoryFailures = new Map<string, number[]>();

function memoryRetryAfter(userId: string): number {
  const now = Date.now();
  const recent = (memoryFailures.get(userId) ?? []).filter((t) => now - t < LOCKOUT_WINDOW_MS);
  memoryFailures.set(userId, recent);
  if (recent.length < MAX_FAILED_ATTEMPTS) return 0;
  return Math.ceil((recent[0] + LOCKOUT_WINDOW_MS - now) / 1000);
}

function memoryRecordFailure(userId: string): number {
  const recent = memoryFailures.get(userId) ?? [];
  recent.push(Date.now());
  memoryFailures.set(userId, recent);
  return recent.length;
}

/**
 * Redeem a 6-digit pairing code to join a family.
 *
 * This enables the "iPad setup" flow: a receiver gets an SMS on their phone,
 * then opens the app on their iPad, signs in (Apple / email), and enters the
 * pairing code to bind their account to the family.
 *
 * Brute-force protection is durable (pairing_code_attempts, 00054): per-user
 * and per-IP limits survive restarts, and the IP limit also covers a second
 * account. It used to be only an in-memory map keyed per user, reset by every
 * deploy; that map remains as the fallback when the table is unavailable.
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
    await maybeAlarmOnFailureSpike();
    return json({
      error: "Invalid or expired code. Please check and try again.",
      attemptsRemaining: Math.max(0, MAX_FAILED_ATTEMPTS - failures),
    }, 400);
  }

  await recordAttempt(userId, ip, true);

  if (body.preview === true) {
    const preview = await describeInvite(invite.id, userId);
    if (!preview) {
      return json({ error: "Invalid or expired code. Please check and try again." }, 400);
    }
    return json(preview);
  }

  const result = await redeemInvite(invite.id, userId, body.timezone, "code");

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

/**
 * Seconds until this caller may try again; 0 when allowed. If the durable
 * lockout is unavailable, falls back to the in-memory one rather than to no
 * limit at all.
 */
async function retryAfter(userId: string, ip: string | null): Promise<number> {
  const { data, error } = await supabaseAdmin.rpc("pairing_code_retry_after", {
    p_user_id: userId,
    p_ip: ip,
  });
  if (error) {
    logError("pairing_code_retry_after failed; using in-memory lockout", error, {
      userId,
      path: "/redeem-code",
    });
    return memoryRetryAfter(userId);
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
  if (succeeded) {
    memoryFailures.delete(userId);
    return 0;
  }
  if (error) {
    logError("Failed to record pairing-code attempt", error, { userId, path: "/redeem-code" });
    return memoryRecordFailure(userId);
  }

  const since = new Date(Date.now() - LOCKOUT_WINDOW_MS).toISOString();
  const { count } = await supabaseAdmin
    .from("pairing_code_attempts")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("succeeded", false)
    .gte("created_at", since);
  return count ?? 1;
}

/**
 * Platform-wide alarm (never a block: anyone could trip a global block with
 * throwaway accounts and lock every real receiver out). Wrong codes across
 * ALL callers in the last hour past a threshold mean someone is guessing at
 * scale with many accounts and addresses; say so in Sentry, at most once an
 * hour per process.
 */
const FAILURE_ALARM_THRESHOLD = 200;
let lastAlarmAt = 0;
let lastAlarmCheckAt = 0;

async function maybeAlarmOnFailureSpike(): Promise<void> {
  const now = Date.now();
  // One count query per minute at most, and nothing after an alarm for an hour.
  if (now - lastAlarmAt < 60 * 60 * 1000 || now - lastAlarmCheckAt < 60 * 1000) return;
  lastAlarmCheckAt = now;
  try {
    const since = new Date(now - 60 * 60 * 1000).toISOString();
    const { count } = await supabaseAdmin
      .from("pairing_code_attempts")
      .select("id", { count: "exact", head: true })
      .eq("succeeded", false)
      .gte("created_at", since);
    if ((count ?? 0) >= FAILURE_ALARM_THRESHOLD) {
      lastAlarmAt = now;
      logError(
        "Pairing-code failures spiking platform-wide (possible distributed guessing)",
        new Error(`failed_codes_last_hour=${count}`),
        { path: "/redeem-code" },
      );
    }
  } catch {
    // Best effort.
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
