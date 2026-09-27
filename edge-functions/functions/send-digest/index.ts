import { supabaseAdmin } from "../../shared/supabase.ts";
import { sendNotificationToUser } from "../../shared/send-notification.ts";
import type { AuthResult } from "../../shared/auth.ts";

/**
 * US-IOS014 — Caregiver daily / weekly digest.
 *
 * Service-role only: invoked by the `dispatch_caregiver_digests` pg_cron job
 * (migration 00040; co-caregivers since 00062) once the caregiver's chosen
 * local delivery hour arrives. It
 * computes the same period metrics the dashboard already shows (consistency,
 * check-ins X of Y, misses, dominant mood) and sends one reassuring push.
 *
 * Backward-compatible: a brand-new endpoint sending an additive push. Owners
 * with `digest_frequency = 'off'` are never enqueued by the cron, and this
 * handler is defensive about it anyway.
 */
interface DigestRequest {
  /** Kept for the dispatcher before 00062, which only sent owners. */
  owner_id?: string;
  /** 00062+: the caregiver (owner or co-caregiver) to send to. */
  user_id?: string;
}

interface CheckinRow {
  receiver_id: string;
  checked_in_at: string;
  mood: string | null;
}

const MOOD_EMOJI: Record<string, string> = {
  happy: "😊",
  neutral: "😐",
  tired: "😴",
};

export async function handleSendDigest(req: Request, _auth: AuthResult): Promise<Response> {
  const body: DigestRequest = await req.json();
  const recipientId = body.user_id ?? body.owner_id;

  if (!recipientId) {
    return json({ error: "user_id is required" }, 400);
  }

  // The caregiver + their digest preference.
  const { data: recipient } = await supabaseAdmin
    .from("users")
    .select("display_name, digest_frequency")
    .eq("id", recipientId)
    .single();

  if (!recipient || recipient.digest_frequency === "off") {
    return json({ ok: true, skipped: "digest off or user missing", sent: 0 }, 200);
  }

  const isWeekly = recipient.digest_frequency === "weekly";
  const days = isWeekly ? 7 : 1;
  const periodLabel = isWeekly ? "This week" : "Today";

  // The family: the earliest one they own, as the apps pick it (`.single()`
  // returned nothing at all when stray duplicates existed). Otherwise the
  // family they're an active co-caregiver in (00062) — earliest join, as
  // FamilyService.getFamily resolves it.
  const { data: families } = await supabaseAdmin
    .from("families")
    .select("id, name, subscription_status, owner_id")
    .eq("owner_id", recipientId)
    .order("created_at", { ascending: true })
    .limit(1);
  let family = families?.[0];
  let isOwner = !!family;

  if (!family) {
    const { data: memberships } = await supabaseAdmin
      .from("family_members")
      .select("family_id")
      .eq("user_id", recipientId)
      .eq("role", "viewer")
      .eq("status", "active")
      .order("joined_at", { ascending: true })
      .limit(1);
    const familyId = memberships?.[0]?.family_id as string | undefined;
    if (familyId) {
      const { data: viewerFamily } = await supabaseAdmin
        .from("families")
        .select("id, name, subscription_status, owner_id")
        .eq("id", familyId)
        .maybeSingle();
      family = viewerFamily ?? undefined;
      isOwner = false;
    }
  }

  if (!family) {
    return json({ ok: true, skipped: "no family", sent: 0 }, 200);
  }

  // Active receivers in the family.
  const { data: members } = await supabaseAdmin
    .from("family_members")
    .select("id, user_id, users(display_name)")
    .eq("family_id", family.id)
    .eq("role", "receiver")
    .eq("status", "active");

  const receivers = members ?? [];
  if (receivers.length === 0) {
    return json({ ok: true, skipped: "no active receivers", sent: 0 }, 200);
  }

  // Whose check-ins are actually being sent. A receiver with no schedule row,
  // or one switched off (e.g. by the plan-expiry job), gets no requests — so
  // "no misses" would be reassurance about nothing.
  const memberIds: string[] = receivers.map((r: { id: string }) => r.id);
  const { data: settingsRows } = await supabaseAdmin
    .from("receiver_settings")
    .select("family_member_id, is_active")
    .in("family_member_id", memberIds);
  const activeScheduleIds = new Set(
    (settingsRows ?? [])
      .filter((r: { is_active: boolean | null }) => r.is_active !== false)
      .map((r: { family_member_id: string }) => r.family_member_id),
  );
  const pausedCount = memberIds.filter((id: string) => !activeScheduleIds.has(id)).length;
  const planEnded = family.subscription_status === "expired";

  const sinceISO = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();

  // Check-ins over the period — the active receivers' only. Rows from anyone
  // else in the family (a receiver who has left, or a row a member inserted
  // as themselves before 00062) must not count toward "X of Y — no misses".
  const receiverUserIds: string[] = receivers.map((r: { user_id: string }) => r.user_id);
  const { data: checkins } = await supabaseAdmin
    .from("checkins")
    .select("receiver_id, checked_in_at, mood")
    .eq("family_id", family.id)
    .in("receiver_id", receiverUserIds)
    .gte("checked_in_at", sinceISO);

  // Missed requests over the period.
  const { count: missedCount } = await supabaseAdmin
    .from("checkin_requests")
    .select("id", { count: "exact", head: true })
    .eq("family_id", family.id)
    .eq("status", "missed")
    .gte("created_at", sinceISO);

  const rows: CheckinRow[] = (checkins as CheckinRow[]) ?? [];

  // Per-receiver check-in counts (one expected per receiver per day).
  const perReceiver = new Map<string, number>();
  const moodCounts = new Map<string, number>();
  for (const row of rows) {
    perReceiver.set(row.receiver_id, (perReceiver.get(row.receiver_id) ?? 0) + 1);
    if (row.mood) moodCounts.set(row.mood, (moodCounts.get(row.mood) ?? 0) + 1);
  }

  const totalCheckins = rows.length;
  const expected = receivers.length * days;
  const consistency = expected > 0 ? Math.min(100, Math.round((totalCheckins / expected) * 100)) : 0;
  const misses = missedCount ?? 0;

  // Dominant mood for the period.
  let dominantMood: string | null = null;
  let dominantMoodCount = 0;
  for (const [mood, count] of moodCounts) {
    if (count > dominantMoodCount) {
      dominantMood = mood;
      dominantMoodCount = count;
    }
  }

  // Build a calm, reassuring summary line.
  const title = isWeekly ? `${family.name}: weekly summary` : `${family.name}: today's check-ins`;
  const parts: string[] = [];
  // A co-caregiver can't renew the plan or change a schedule: tell them who can.
  if (planEnded) {
    parts.push(isOwner
      ? "Check-ins are paused because your Daily OK plan has ended. Open the app to renew."
      : "Check-ins are paused because the family's Daily OK plan has ended. The family owner can renew it.");
  } else if (pausedCount > 0) {
    const fix = isOwner ? "Open the app to check their schedules." : "The family owner manages schedules.";
    parts.push(pausedCount === receivers.length
      ? `Check-ins aren't being sent to anyone right now. ${fix}`
      : `Check-ins aren't being sent to ${pausedCount} of ${receivers.length} people. ${fix}`);
  }
  parts.push(`${periodLabel}: ${totalCheckins} of ${expected} check-ins (${consistency}%).`);
  if (misses > 0) {
    parts.push(`${misses} missed.`);
  } else if (!planEnded && pausedCount === 0 && totalCheckins >= expected) {
    parts.push("No misses 🎉");
  }
  if (dominantMood) {
    const emoji = MOOD_EMOJI[dominantMood] ?? "";
    parts.push(`Mostly feeling ${dominantMood} ${emoji}`.trim() + ".");
  }
  const message = parts.join(" ");

  const result = await sendNotificationToUser(
    recipientId,
    {
      aps: {
        alert: { title, body: message },
        sound: "default",
        "thread-id": `digest-${family.id}`,
        "interruption-level": "passive",
      },
      type: "digest",
      family_id: family.id,
    },
    {
      title,
      body: message,
      data: { type: "digest", family_id: family.id },
    },
    { collapseId: `digest-${family.id}` }
  );

  return json({ ok: true, sent: result.sent, failed: result.failed, consistency }, 200);
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
