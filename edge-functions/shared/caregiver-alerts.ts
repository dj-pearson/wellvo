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
import {
  careTeamRecipientIds,
  caregiverCheckedOnCopy,
  escalationCollapseId,
  escalationResolvedCopy,
} from "./caregiver-alerts-copy.ts";

export {
  careTeamRecipientIds,
  caregiverCheckedOnCopy,
  escalationCollapseId,
  escalationResolvedCopy,
  requestsResolvedByCheckIn,
  viewerMissedAlertCopy,
} from "./caregiver-alerts-copy.ts";

/**
 * Who hears an all-clear or a caregiver's action (careTeamRecipientIds):
 * co-caregivers paged about `requestIds`, plus, with `wholeTeam`, the owner
 * and every other active co-caregiver. Never `exclude` (the actor).
 */
async function careTeamRecipients(args: {
  familyId: string;
  requestIds: string[];
  exclude: string | null;
  wholeTeam: boolean;
}): Promise<string[]> {
  let paged: string[] = [];
  if (args.requestIds.length > 0) {
    const { data: logs } = await supabaseAdmin
      .from("notification_log")
      .select("user_id")
      .in("checkin_request_id", args.requestIds)
      .eq("type", "viewer_alert");
    paged = (logs ?? []).map((r: { user_id: string }) => r.user_id);
  }
  if (!args.wholeTeam && paged.length === 0) return [];

  const { data: viewers } = await supabaseAdmin
    .from("family_members")
    .select("user_id")
    .eq("family_id", args.familyId)
    .eq("role", "viewer")
    .eq("status", "active");
  let ownerId: string | null = null;
  if (args.wholeTeam) {
    const { data: family } = await supabaseAdmin
      .from("families")
      .select("owner_id")
      .eq("id", args.familyId)
      .single();
    ownerId = family?.owner_id ?? null;
  }
  return careTeamRecipientIds({
    ownerId,
    viewerIds: (viewers ?? []).map((v: { user_id: string }) => v.user_id),
    pagedIds: paged,
    actorId: args.exclude,
    wholeTeam: args.wholeTeam,
  });
}

/** Push one alert to these users' active devices; deactivates dead tokens. */
async function pushToUsers(
  userIds: string[],
  payload: APNsPayload,
  fcm: { title: string; body: string; data: Record<string, string> },
  apnsOptions: { priority?: 5 | 10; collapseId?: string },
): Promise<number> {
  if (userIds.length === 0) return 0;
  const { data: tokens } = await supabaseAdmin
    .from("push_tokens")
    .select("token, platform, user_id")
    .in("user_id", userIds)
    .eq("is_active", true);
  if (!tokens?.length) return 0;
  const results = await Promise.all(
    tokens.map((t: { token: string; platform: string }) =>
      t.platform === "android"
        ? sendFCMNotification(t.token, buildFCMAlertPayload(fcm.title, fcm.body, fcm.data))
        : sendPushNotification(t.token, payload, apnsOptions)
    ),
  );
  for (let i = 0; i < results.length; i++) {
    const gone = results[i].statusCode === 410 || results[i].reason === "NOT_FOUND" ||
      results[i].reason === "UNREGISTERED";
    if (gone) {
      await supabaseAdmin.from("push_tokens").update({ is_active: false }).eq("token", tokens[i].token);
    }
  }
  return results.filter((r) => r.success).length;
}

async function displayNames(ids: string[]): Promise<(id: string | null | undefined) => string | null> {
  const { data: people } = await supabaseAdmin
    .from("users")
    .select("id, display_name")
    .in("id", ids);
  return (id) => {
    const raw = (people ?? []).find((p: { id: string; display_name: string | null }) => p.id === id)?.display_name?.trim();
    return raw ? sanitizeDisplayName(raw) || null : null;
  };
}

/**
 * Tell the co-caregivers who were paged about these requests that it's over.
 * New push `type: "escalation_resolved"`; older builds show it as a plain
 * banner (unknown types are displayed, not dropped).
 *
 * `wholeTeam`: a co-caregiver stood the alerts down, so the owner and every
 * other active co-caregiver hear it too, paged or not.
 */
export async function notifyEscalationResolved(args: {
  familyId: string;
  receiverId: string;
  requestIds: string[];
  how: "checked_in" | "stood_down";
  atLocal?: string | null;
  byUserId?: string | null;
  wholeTeam?: boolean;
}): Promise<number> {
  try {
    const recipients = await careTeamRecipients({
      familyId: args.familyId,
      requestIds: args.requestIds,
      exclude: args.byUserId ?? null,
      wholeTeam: args.wholeTeam ?? false,
    });
    if (recipients.length === 0) return 0;

    const nameOf = await displayNames([args.receiverId, ...(args.byUserId ? [args.byUserId] : [])]);
    const receiverName = nameOf(args.receiverId) ?? "Your family member";
    const byName = args.byUserId ? nameOf(args.byUserId) : null;
    const { title, body } = escalationResolvedCopy({ receiverName, how: args.how, atLocal: args.atLocal, byName });

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
    const sent = await pushToUsers(recipients, payload, { title, body, data: fcmData }, {
      priority: 5,
      collapseId: escalationCollapseId(requestId),
    });
    logInfo("Escalation all-clear sent to caregivers", {
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

/**
 * A co-caregiver sent "Check on now": tell the owner and the other active
 * co-caregivers ("Tom checked on Mom"), so two people don't send one each and
 * the owner knows who asked. New push `type: "caregiver_checked_on"`; older
 * builds show it as a plain banner. Best-effort; never fails the check-in.
 */
export async function notifyCaregiverCheckedOn(args: {
  familyId: string;
  receiverId: string;
  requestId: string;
  actorId: string;
  delivered: boolean;
}): Promise<number> {
  try {
    const recipients = await careTeamRecipients({
      familyId: args.familyId,
      requestIds: [],
      exclude: args.actorId,
      wholeTeam: true,
    });
    if (recipients.length === 0) return 0;

    const nameOf = await displayNames([args.receiverId, args.actorId]);
    const { title, body } = caregiverCheckedOnCopy({
      actorName: nameOf(args.actorId),
      receiverName: nameOf(args.receiverId) ?? "Your family member",
      delivered: args.delivered,
    });
    const payload: APNsPayload = {
      aps: {
        alert: { title, body },
        sound: "default",
        "interruption-level": "active",
        "thread-id": `checkon-${args.receiverId}`,
      },
      // No checkin_request_id / request_id: both apps "confirm delivery" of
      // any push carrying one, and this push isn't the receiver's.
      receiver_id: args.receiverId,
      type: "caregiver_checked_on",
    };
    const fcmData: Record<string, string> = {
      receiver_id: args.receiverId,
      type: "caregiver_checked_on",
      notification_type: "caregiver_checked_on",
    };
    const sent = await pushToUsers(recipients, payload, { title, body, data: fcmData }, {
      priority: 5,
      collapseId: `checkon-${args.requestId}`,
    });
    logInfo("Co-caregiver check-on announced to care team", {
      path: "caregiver-alerts",
      familyId: args.familyId,
      recipients: recipients.length,
      sent,
    });
    return sent;
  } catch (err) {
    logError("Co-caregiver check-on notice failed", err, { path: "caregiver-alerts", familyId: args.familyId });
    return 0;
  }
}
