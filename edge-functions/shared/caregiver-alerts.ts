/**
 * What co-caregivers (viewers) are told about a missed check-in, and the
 * all-clear once it is resolved.
 *
 * escalation-tick pages every active co-caregiver at the last step. Before
 * this module:
 *   - that page was a plain "Family Alert: Mom has missed their check-in
 *     today." with interruption-level "active" (held back by Focus / Sleep,
 *     although the app tells co-caregivers to turn on Time Sensitive for
 *     exactly these alerts) and "View Details" instead of "Call Now";
 *   - nobody who was paged ever heard that it was over. The receiver checking
 *     in, or the owner reaching them and standing the alerts down, only told
 *     the owner (their routine "Checked in ✓"), so a sibling paged at 10:30
 *     stayed worried until they opened the app or phoned around.
 *
 * The copy builders are pure (caregiver-alerts-copy.ts, unit-tested). The
 * senders are best-effort: a failure here never fails the check-in or the
 * stand-down that triggered it.
 */
import { supabaseAdmin } from "./supabase.ts";
import { sendPushNotification } from "./apns.ts";
import type { APNsPayload } from "./apns.ts";
import { sendFCMNotification, buildFCMAlertPayload } from "./fcm.ts";
import { logError, logInfo } from "./logger.ts";
import { sanitizeDisplayName } from "./validation.ts";
import { escalationCollapseId, escalationResolvedCopy } from "./caregiver-alerts-copy.ts";

export {
  escalationCollapseId,
  escalationResolvedCopy,
  requestsResolvedByCheckIn,
  viewerMissedAlertCopy,
} from "./caregiver-alerts-copy.ts";

/**
 * Active co-caregivers who were paged about any of these requests
 * (notification_log 'viewer_alert'), excluding `exclude` (whoever resolved it).
 */
async function pagedViewers(familyId: string, requestIds: string[], exclude: string | null): Promise<string[]> {
  if (requestIds.length === 0) return [];
  const { data: logs } = await supabaseAdmin
    .from("notification_log")
    .select("user_id")
    .in("checkin_request_id", requestIds)
    .eq("type", "viewer_alert");
  const paged = new Set<string>((logs ?? []).map((r: { user_id: string }) => r.user_id));
  if (paged.size === 0) return [];

  const { data: viewers } = await supabaseAdmin
    .from("family_members")
    .select("user_id")
    .eq("family_id", familyId)
    .eq("role", "viewer")
    .eq("status", "active");
  return (viewers ?? [])
    .map((v: { user_id: string }) => v.user_id)
    .filter((id: string) => paged.has(id) && id !== exclude);
}

/**
 * Tell the co-caregivers who were paged about these requests that it's over.
 * New push `type: "escalation_resolved"`; older builds show it as a plain
 * banner (unknown types are displayed, not dropped).
 */
export async function notifyEscalationResolved(args: {
  familyId: string;
  receiverId: string;
  requestIds: string[];
  how: "checked_in" | "stood_down";
  atLocal?: string | null;
  byUserId?: string | null;
}): Promise<number> {
  try {
    const recipients = await pagedViewers(args.familyId, args.requestIds, args.byUserId ?? null);
    if (recipients.length === 0) return 0;

    const ids = [args.receiverId, ...(args.byUserId ? [args.byUserId] : [])];
    const { data: people } = await supabaseAdmin
      .from("users")
      .select("id, display_name")
      .in("id", ids);
    const nameOf = (id: string | null | undefined) =>
      (people ?? []).find((p: { id: string; display_name: string | null }) => p.id === id)?.display_name?.trim() || null;
    const receiverName = sanitize(nameOf(args.receiverId) ?? "Your family member");
    const byName = args.byUserId ? (nameOf(args.byUserId) ? sanitize(nameOf(args.byUserId)!) : null) : null;
    const { title, body } = escalationResolvedCopy({ receiverName, how: args.how, atLocal: args.atLocal, byName });

    const { data: tokens } = await supabaseAdmin
      .from("push_tokens")
      .select("token, platform, user_id")
      .in("user_id", recipients)
      .eq("is_active", true);
    if (!tokens?.length) return 0;

    // The alarm this answers (the newest request), so the all-clear lands in
    // the same thread and replaces it where the collapse id matches.
    const requestId = args.requestIds[args.requestIds.length - 1];
    const payload: APNsPayload = {
      aps: {
        alert: { title, body },
        sound: "default",
        "interruption-level": "active",
        "thread-id": `alert-${requestId}`,
      },
      checkin_request_id: requestId,
      receiver_id: args.receiverId,
      type: "escalation_resolved",
    };
    const fcmData: Record<string, string> = {
      checkin_request_id: requestId,
      receiver_id: args.receiverId,
      type: "escalation_resolved",
      notification_type: "escalation_resolved",
    };
    const results = await Promise.all(
      tokens.map((t: { token: string; platform: string }) =>
        t.platform === "android"
          ? sendFCMNotification(t.token, buildFCMAlertPayload(title, body, fcmData))
          : sendPushNotification(t.token, payload, { priority: 5, collapseId: escalationCollapseId(requestId) })
      ),
    );
    for (let i = 0; i < results.length; i++) {
      const gone = results[i].statusCode === 410 || results[i].reason === "NOT_FOUND" ||
        results[i].reason === "UNREGISTERED";
      if (gone) {
        await supabaseAdmin.from("push_tokens").update({ is_active: false }).eq("token", tokens[i].token);
      }
    }
    const sent = results.filter((r) => r.success).length;
    logInfo("Escalation all-clear sent to co-caregivers", {
      path: "caregiver-alerts",
      familyId: args.familyId,
      recipients: recipients.length,
      sent,
    });
    return sent;
  } catch (err) {
    logError("Escalation all-clear failed", err, { path: "caregiver-alerts", familyId: args.familyId });
    return 0;
  }
}

function sanitize(name: string): string {
  return sanitizeDisplayName(name) || "Your family member";
}
