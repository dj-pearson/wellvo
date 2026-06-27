/**
 * Live Activity remote control (US-IOS127).
 *
 * The owner's escalation Live Activity is started/updated locally by the app's
 * EscalationActivityManager when the dashboard reloads. That leaves a window:
 * if the escalation resolves (receiver checks in, or the owner stands down)
 * while the owner's app is closed, the Lock Screen keeps showing a running
 * "Overdue" timer until the app is next opened.
 *
 * This module closes that window by ending the activity via an APNs
 * `liveactivity` push to the per-activity push tokens the app registered in
 * `live_activity_push_tokens` (migration 00048).
 */

import { supabaseAdmin } from "./supabase.ts";
import { sendLiveActivityUpdate } from "./apns.ts";
import { logError, logInfo } from "./logger.ts";

interface LiveActivityTokenRow {
  id: string;
  push_token: string;
}

/**
 * End any running escalation Live Activities for a receiver in a family.
 *
 * Best-effort and non-throwing: a push failure must never break the check-in /
 * stand-down response that triggered it. Tokens APNs reports as gone (410 /
 * BadDeviceToken / Unregistered) — which is the expected terminal state once an
 * activity ends — are deactivated so we stop targeting them.
 */
export async function endEscalationLiveActivities(
  familyId: string,
  receiverId: string
): Promise<void> {
  try {
    const { data: tokens, error } = await supabaseAdmin
      .from("live_activity_push_tokens")
      .select("id, push_token")
      .eq("family_id", familyId)
      .eq("receiver_id", receiverId)
      .eq("token_type", "update")
      .eq("is_active", true);

    if (error) {
      logError(`Failed to load live activity tokens (family ${familyId})`, error, { userId: receiverId });
      return;
    }
    if (!tokens?.length) return;

    const now = Math.floor(Date.now() / 1000);
    // Minimal valid ContentState (matches iOS EscalationActivityAttributes.
    // ContentState: status/escalationStep/dueSince). Dates are epoch seconds.
    const contentState = { status: "pending", escalationStep: 0, dueSince: now };

    const rows = tokens as LiveActivityTokenRow[];
    const results = await Promise.all(
      rows.map((t) =>
        sendLiveActivityUpdate(t.push_token, {
          event: "end",
          contentState,
          timestamp: now,
          dismissalDate: now,
        })
      )
    );

    const staleIds: string[] = [];
    for (let i = 0; i < results.length; i++) {
      const r = results[i];
      // Once an activity ends, its token is gone — a successful end push or an
      // APNs "gone" status both mean we should stop tracking it.
      const isGone =
        r.statusCode === 410 ||
        r.reason === "BadDeviceToken" ||
        r.reason === "Unregistered" ||
        r.reason === "ExpiredToken";
      if (r.success || isGone) {
        staleIds.push(rows[i].id);
      } else {
        logError(`Live activity end push failed (family ${familyId}, reason ${r.reason})`, null, {
          userId: receiverId,
          statusCode: r.statusCode,
        });
      }
    }

    if (staleIds.length) {
      await supabaseAdmin
        .from("live_activity_push_tokens")
        .update({ is_active: false })
        .in("id", staleIds);
      logInfo(`Ended escalation live activities (family ${familyId})`, {
        userId: receiverId,
      });
    }
  } catch (e) {
    // Never let a Live Activity push failure surface to the caller.
    logError(`endEscalationLiveActivities threw (family ${familyId})`, e, { userId: receiverId });
  }
}
