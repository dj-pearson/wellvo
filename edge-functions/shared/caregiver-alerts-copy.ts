/**
 * Copy and decisions for what co-caregivers are told about a missed check-in
 * and its all-clear. Pure (no database, no network) so it is unit-tested in
 * caregiver-alerts_test.ts; the senders are in caregiver-alerts.ts.
 */

/** Same key for the alarm and its all-clear, so iOS replaces one with the other. */
export function escalationCollapseId(requestId: string): string {
  return `escalation-${requestId}`;
}

/**
 * The last-step page to a co-caregiver. `sinceLocal` is when the check-in was
 * asked for, in the receiver's zone ("9:00 AM"); `ownerName` is who was
 * alerted before them. Either may be missing.
 */
export function viewerMissedAlertCopy(args: {
  receiverName: string;
  sinceLocal?: string | null;
  ownerName?: string | null;
  /** Someone already said "I'm on it" (claim_checkin_request, 00062). */
  claimedByName?: string | null;
}): { title: string; body: string } {
  const title = `${args.receiverName} hasn't checked in`;
  const since = args.sinceLocal ? `No answer since ${args.sinceLocal}.` : "No answer to today's check-in.";
  if (args.claimedByName) {
    return { title, body: `${since} ${args.claimedByName} is on it. Open Daily OK to see what's happening.` };
  }
  const owner = args.ownerName ? ` ${args.ownerName} was alerted too.` : "";
  return { title, body: `${since}${owner} Call them, or open Daily OK to see what's happening.` };
}

/** The all-clear. */
export function escalationResolvedCopy(args: {
  receiverName: string;
  how: "checked_in" | "stood_down";
  atLocal?: string | null;
  byName?: string | null;
}): { title: string; body: string } {
  const at = args.atLocal ? ` at ${args.atLocal}` : "";
  if (args.how === "checked_in") {
    return {
      title: `${args.receiverName} checked in ✓`,
      body: `${args.receiverName} checked in${at}. The missed check-in alert is over.`,
    };
  }
  const who = args.byName ?? "A caregiver";
  return {
    title: `${args.receiverName} was reached ✓`,
    body: `${who} reached ${args.receiverName} and stopped the alerts${at}.`,
  };
}

/**
 * Which requests a fresh check-in resolves for the co-caregivers who were
 * paged about them. A pending request that reached the viewer step (>= 3) is
 * being answered now. A missed request (the chain ran out) counts only when
 * it came after the receiver's previous check-in — otherwise it was already
 * answered and announced — and only if nobody stood it down (they were told
 * then).
 */
export function requestsResolvedByCheckIn(
  requests: { id: string; status: string; escalation_step: number | null; created_at: string; stood_down_at?: string | null }[],
  previousCheckInAt: string | null,
  allowMissed: boolean,
  answeredAt?: string | null,
): string[] {
  const prev = previousCheckInAt ? Date.parse(previousCheckInAt) : NaN;
  const answered = answeredAt ? Date.parse(answeredAt) : NaN;
  return requests
    .filter((r) => {
      if (r.status === "pending") return (r.escalation_step ?? 0) >= 3;
      if (r.status !== "missed" || !allowMissed || r.stood_down_at) return false;
      const created = Date.parse(r.created_at);
      // A replayed tap from before the request doesn't answer it.
      if (!Number.isNaN(answered) && created > answered) return false;
      return Number.isNaN(prev) || created > prev;
    })
    .map((r) => r.id);
}

/**
 * Who hears about an escalation's all-clear or a caregiver's action.
 *
 * `pagedIds` are the co-caregivers who were paged about the requests (the
 * all-clear always reaches them). With `wholeTeam` (the actor is a
 * co-caregiver: they stopped the alerts or sent a check-in) the owner and
 * every other active co-caregiver hear it too, so nobody phones Mom a second
 * time or wonders why the alerts stopped. The actor never hears about their
 * own action. Only active co-caregivers (`viewerIds`) and the owner qualify.
 */
export function careTeamRecipientIds(args: {
  ownerId: string | null;
  viewerIds: string[];
  pagedIds: string[];
  actorId: string | null;
  wholeTeam: boolean;
}): string[] {
  const actor = args.actorId?.toLowerCase() ?? null;
  const active = new Set(args.viewerIds.map((id) => id.toLowerCase()));
  const out: string[] = [];
  const seen = new Set<string>();
  const add = (id: string | null) => {
    if (!id) return;
    const key = id.toLowerCase();
    if (key === actor || seen.has(key)) return;
    seen.add(key);
    out.push(id);
  };
  if (args.wholeTeam) add(args.ownerId);
  for (const id of args.viewerIds) {
    if (args.wholeTeam || args.pagedIds.some((p) => p.toLowerCase() === id.toLowerCase())) add(id);
  }
  return out.filter((id) => id === args.ownerId || active.has(id.toLowerCase()));
}

/** "Tom sent Mom a check-in" — to the owner and the other co-caregivers. */
export function caregiverCheckedOnCopy(args: {
  actorName?: string | null;
  receiverName: string;
  delivered: boolean;
}): { title: string; body: string } {
  const who = args.actorName ?? "A caregiver";
  const title = `${who} checked on ${args.receiverName}`;
  const body = args.delivered
    ? `${who} sent ${args.receiverName} a check-in. Open Daily OK to see when they answer.`
    : `${who} sent ${args.receiverName} a check-in, but their phone couldn't be notified. You may want to call.`;
  return { title, body };
}
